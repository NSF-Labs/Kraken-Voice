/// Speaker diarization interface and supporting types.
///
/// All app code should depend on [Diarizer], never on the concrete
/// NeMo implementation. This enables model swaps (e.g., to eres2net)
/// with zero downstream changes.
library;

/// Configuration for a diarization run.
///
/// Both values are persisted alongside results so the system knows
/// what settings produced the current speaker labels.
class DiarizationConfig {
  /// Clustering threshold. Range: 0.3 – 0.95. Default: 0.75.
  ///
  /// Higher = more aggressive merging (fewer speakers). Lower = stricter
  /// merging (more speakers). This matches the convention used by the
  /// native sherpa-onnx FastClustering path and by the in-app "Adjust
  /// Speakers" sheet, where "Combine similar voices" raises the threshold
  /// and "Separate similar voices" lowers it.
  ///
  /// Ignored when [numSpeakers] is set (the native pipeline forces an
  /// exact cluster count).
  final double threshold;

  /// Minimum total speech duration (seconds) for a cluster to qualify as
  /// a distinct speaker. Effective floor scales down for short audio
  /// inside [postProcessSegments] so it never demands more than 5% of
  /// total audio duration. Default: 2.0.
  ///
  /// Bumped from 1.0 → 2.0 as part of the diarization-quality fix: a
  /// spurious cluster that survives at 1.0s often disappears at 2.0s
  /// without dropping any legitimate speaker.
  final double minDuration;

  /// If non-null, forces the clustering step to produce exactly this many
  /// speakers (passed through to sherpa-onnx FastClustering as `numClusters`).
  /// When null, the threshold-based auto-clustering is used.
  ///
  /// Use this when you know the meeting size — empirically the most
  /// reliable lever, since threshold tuning alone can't always reach the
  /// correct cluster count on similar-sounding voices.
  final int? numSpeakers;

  const DiarizationConfig({
    this.threshold = 0.75,
    this.minDuration = 2.0,
    this.numSpeakers,
  });

  DiarizationConfig copyWith({
    double? threshold,
    double? minDuration,
    int? numSpeakers,
    bool clearNumSpeakers = false,
  }) =>
      DiarizationConfig(
        threshold: threshold ?? this.threshold,
        minDuration: minDuration ?? this.minDuration,
        numSpeakers:
            clearNumSpeakers ? null : (numSpeakers ?? this.numSpeakers),
      );

  Map<String, dynamic> toJson() => {
        'threshold': threshold,
        'min_duration': minDuration,
        if (numSpeakers != null) 'num_speakers': numSpeakers,
      };

  factory DiarizationConfig.fromJson(Map<String, dynamic> json) =>
      DiarizationConfig(
        threshold: (json['threshold'] as num?)?.toDouble() ?? 0.75,
        minDuration: (json['min_duration'] as num?)?.toDouble() ?? 2.0,
        numSpeakers: (json['num_speakers'] as num?)?.toInt(),
      );

  @override
  String toString() => 'DiarizationConfig(threshold: $threshold, '
      'minDuration: $minDuration, numSpeakers: $numSpeakers)';
}

/// A single diarization segment with speaker assignment.
class DiarizationSegment {
  final int speaker;
  final double startSeconds;
  final double endSeconds;

  DiarizationSegment({
    required this.speaker,
    required this.startSeconds,
    required this.endSeconds,
  });

  double get duration => endSeconds - startSeconds;

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'start_s': startSeconds,
        'end_s': endSeconds,
      };

  factory DiarizationSegment.fromJson(Map<String, dynamic> json) =>
      DiarizationSegment(
        speaker: json['speaker'] as int,
        startSeconds: (json['start_s'] as num).toDouble(),
        endSeconds: (json['end_s'] as num).toDouble(),
      );

  /// Returns the speaker that has the most temporal overlap with the
  /// interval `[s, e]` across [segments].
  ///
  /// Used to align Whisper sub-segments to diarization output. Replaces the
  /// older midpoint-lookup, which would mis-assign a long Whisper segment to
  /// the wrong speaker whenever its midpoint happened to land inside a
  /// short opposite-speaker sliver.
  ///
  /// Behavior:
  ///   • If any speaker has positive overlap, return the one with the most.
  ///   • If two speakers tie, prefer the one whose segment ends earlier
  ///     (continuation bias — speakers are more likely to finish their turn
  ///     than a new one to start mid-Whisper-segment).
  ///   • If there's no overlap at all, fall back to the speaker of the
  ///     nearest segment by midpoint distance — but only if that nearest
  ///     segment is within [maxFallbackGapSec] of the query interval.
  ///     Beyond that, return `null` so the caller can render the chunk
  ///     unattributed rather than confidently mislabel it.
  static int? speakerByOverlap(
    double s,
    double e,
    List<DiarizationSegment> segments, {
    double maxFallbackGapSec = 1.0,
  }) {
    if (segments.isEmpty || e <= s) return null;

    double bestOverlap = 0;
    int? bestSpeaker;
    double bestSpeakerEarliestEnd = double.infinity;

    final overlapBySpeaker = <int, double>{};
    final earliestEndBySpeaker = <int, double>{};

    for (final seg in segments) {
      final ovStart = s > seg.startSeconds ? s : seg.startSeconds;
      final ovEnd = e < seg.endSeconds ? e : seg.endSeconds;
      final ov = ovEnd - ovStart;
      if (ov <= 0) continue;

      overlapBySpeaker[seg.speaker] =
          (overlapBySpeaker[seg.speaker] ?? 0) + ov;
      final prevEnd = earliestEndBySpeaker[seg.speaker];
      if (prevEnd == null || seg.endSeconds < prevEnd) {
        earliestEndBySpeaker[seg.speaker] = seg.endSeconds;
      }
    }

    overlapBySpeaker.forEach((spk, ov) {
      final earliestEnd = earliestEndBySpeaker[spk]!;
      // Strictly more overlap wins; tie → earlier-ending speaker.
      final isBetter = ov > bestOverlap ||
          (ov == bestOverlap && earliestEnd < bestSpeakerEarliestEnd);
      if (isBetter) {
        bestOverlap = ov;
        bestSpeaker = spk;
        bestSpeakerEarliestEnd = earliestEnd;
      }
    });

    if (bestSpeaker != null) return bestSpeaker;

    // No overlap. Try the nearest segment by midpoint distance.
    final queryMid = (s + e) / 2;
    int? fallbackSpeaker;
    double fallbackDist = double.infinity;
    for (final seg in segments) {
      final segMid = (seg.startSeconds + seg.endSeconds) / 2;
      final dist = (queryMid - segMid).abs();
      if (dist < fallbackDist) {
        fallbackDist = dist;
        fallbackSpeaker = seg.speaker;
      }
    }
    // Only accept the fallback if the gap to the nearest segment edge is
    // within tolerance — otherwise we'd be inventing a label for a chunk
    // that's nowhere near any speaker turn.
    if (fallbackSpeaker != null) {
      double minEdgeGap = double.infinity;
      for (final seg in segments) {
        if (seg.speaker != fallbackSpeaker) continue;
        // Distance from [s, e] to [seg.start, seg.end]. Zero if they touch.
        final gap = e < seg.startSeconds
            ? seg.startSeconds - e
            : (s > seg.endSeconds ? s - seg.endSeconds : 0.0);
        if (gap < minEdgeGap) minEdgeGap = gap;
      }
      if (minEdgeGap <= maxFallbackGapSec) return fallbackSpeaker;
    }

    return null;
  }
}

/// Result of a diarization run.
class DiarizationResult {
  final int speakerCount;
  final List<DiarizationSegment> segments;
  final Duration processingTime;
  final double audioDurationSeconds;

  /// The config that produced this result.
  final DiarizationConfig config;

  /// Path to cached embeddings file (null if not cached yet).
  final String? embeddingsPath;

  /// Raw segments before post-processing (speaker merging).
  final List<DiarizationSegment> rawSegments;

  DiarizationResult({
    required this.speakerCount,
    required this.segments,
    required this.processingTime,
    required this.audioDurationSeconds,
    required this.config,
    this.embeddingsPath,
    this.rawSegments = const [],
  });

  double get realtimeRatio =>
      processingTime.inMilliseconds / (audioDurationSeconds * 1000);

  /// Number of distinct speakers in the raw (pre-merge) output.
  int get rawSpeakerCount =>
      rawSegments.map((s) => s.speaker).toSet().length;
}

/// A single segment with its speaker embedding vector.
/// Used for caching and re-clustering.
class SegmentEmbedding {
  final double startSeconds;
  final double endSeconds;
  final List<double> embedding;

  SegmentEmbedding({
    required this.startSeconds,
    required this.endSeconds,
    required this.embedding,
  });

  Map<String, dynamic> toJson() => {
        'start_s': startSeconds,
        'end_s': endSeconds,
        'embedding': embedding,
      };

  factory SegmentEmbedding.fromJson(Map<String, dynamic> json) =>
      SegmentEmbedding(
        startSeconds: (json['start_s'] as num).toDouble(),
        endSeconds: (json['end_s'] as num).toDouble(),
        embedding: (json['embedding'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

/// Abstract diarization interface.
///
/// All diarization calls go through this interface. The concrete
/// NeMo implementation lives behind it — no app code should import
/// or reference NeMo/sherpa_onnx directly.
abstract class Diarizer {
  /// Full pipeline: extract embeddings, cluster, return labels.
  /// Slow (~4 min for 15-min recording on NeMo TitanNet Small).
  ///
  /// Caches extracted embeddings to [embeddingsCachePath] for fast
  /// re-clustering later.
  Future<DiarizationResult> processRecording(
    String audioPath, {
    DiarizationConfig config = const DiarizationConfig(),
    String? embeddingsCachePath,
    void Function(double progress)? onProgress,
  });

  /// Re-cluster from cached embeddings. Fast (seconds).
  ///
  /// Reads embeddings from [embeddingsPath], runs clustering only
  /// with the new [config], returns updated speaker labels.
  Future<DiarizationResult> reclusterRecording({
    required String embeddingsPath,
    required DiarizationConfig config,
  });

  /// Check if required models are downloaded and ready.
  Future<bool> hasModels();
}
