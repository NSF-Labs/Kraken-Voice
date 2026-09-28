// ╔══════════════════════════════════════════════════════════════════════╗
// ║  DEPRECATED — DO NOT USE IN PRODUCTION CODE                        ║
// ║                                                                    ║
// ║  This file is the v0 diarization prototype. Production code should ║
// ║  use the Diarizer interface (diarizer.dart) and its concrete       ║
// ║  NemoDiarizer implementation (nemo_diarizer.dart).                 ║
// ║                                                                    ║
// ║  This file is retained only because integration test harnesses     ║
// ║  (diarization_*_test.dart) still import it for regression runs.    ║
// ║  It will be removed once those tests are migrated.                 ║
// ╚══════════════════════════════════════════════════════════════════════╝
import 'dart:io';
import 'package:krak_en_voice/kernel/model_file_download.dart';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:krak_en_voice/kernel/model_storage_helper.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

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
}

/// Result of a diarization run.
class DiarizationResult {
  final int speakerCount;
  final List<DiarizationSegment> segments;
  final Duration processingTime;
  final double audioDurationSeconds;

  /// Raw segments before post-processing (speaker merging).
  /// Useful for threshold sensitivity analysis.
  final List<DiarizationSegment> rawSegments;

  DiarizationResult({
    required this.speakerCount,
    required this.segments,
    required this.processingTime,
    required this.audioDurationSeconds,
    this.rawSegments = const [],
  });

  double get realtimeRatio =>
      processingTime.inMilliseconds / (audioDurationSeconds * 1000);

  /// Number of distinct speakers in the raw (pre-merge) output.
  int get rawSpeakerCount => rawSegments.map((s) => s.speaker).toSet().length;
}

/// Provides offline speaker diarization via sherpa-onnx.
///
/// Models are stored in the app's documents directory under
/// `diarization_models/`. They must be downloaded before use
/// (see [ensureModelsDownloaded]).
class DiarizationService {
  // Singleton
  static final DiarizationService _instance = DiarizationService._internal();
  factory DiarizationService({required ModelFileDownload downloadFile}) {
    _instance._downloadFile = downloadFile;
    return _instance;
  }

  late ModelFileDownload _downloadFile;
  DiarizationService._internal();

  static const _segModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-segmentation-models/'
      'sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';

  static const _embModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-recongition-models/'
      '3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx';

  /// Clustering threshold. Higher = fewer speakers (more aggressive merging).
  /// 0.75 is the production default for CAM++ on conversational audio.
  static const double _threshold = 0.75;

  /// Minimum speech percentage to qualify as a "real" speaker.
  /// Speakers below this are merged into the nearest major speaker.
  static const double _minSpeakerSharePercent = 3.0;

  /// Minimum speech duration (seconds) to qualify as a "real" speaker.
  static const double _minSpeakerDurationSec = 1.0;

  bool _bindingsInitialized = false;

  // ── Model paths ─────────────────────────────────────────────────────────

  Future<String> get _modelsDir async {
    final baseDir = await ModelStorageHelper().getModelsDirectory();
    return '$baseDir/diarization_models';
  }

  Future<String> get segModelPath async {
    final dir = await _modelsDir;
    return '$dir/sherpa-onnx-pyannote-segmentation-3-0/model.onnx';
  }

  Future<String> get embModelPath async {
    final dir = await _modelsDir;
    return '$dir/3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx';
  }

  /// Returns true if both models are downloaded and ready.
  Future<bool> hasModels() async {
    final seg = File(await segModelPath);
    final emb = File(await embModelPath);
    return await seg.exists() && await emb.exists();
  }

  /// Downloads models if not already present.
  Future<void> ensureModelsDownloaded({
    void Function(double progress, String label)? onProgress,
  }) async {
    final dir = await _modelsDir;
    await Directory(dir).create(recursive: true);

    final seg = File(await segModelPath);
    if (!await seg.exists()) {
      onProgress?.call(0.0, 'Downloading segmentation model...');
      final tarPath = '$dir/seg.tar.bz2';
      await _downloadFile(_segModelUrl, tarPath);
      final r = await Process.run('tar', ['xjf', tarPath, '-C', dir]);
      if (r.exitCode != 0) {
        throw Exception('Failed to extract segmentation model: ${r.stderr}');
      }
      try {
        await File(tarPath).delete();
      } catch (_) {}
    }

    final emb = File(await embModelPath);
    if (!await emb.exists()) {
      onProgress?.call(0.5, 'Downloading embedding model...');
      await _downloadFile(_embModelUrl, emb.path);
    }

    onProgress?.call(1.0, 'Models ready');
  }

  // ── Core diarization ──────────────────────────────────────────────────

  /// Runs speaker diarization on the given audio file.
  ///
  /// The audio file can be any format FFmpegKit can decode (m4a, mp3, wav, etc).
  /// It will be converted to 16kHz mono WAV internally.
  ///
  /// Returns a [DiarizationResult] with post-processed speaker labels.
  Future<DiarizationResult> diarize(
    String audioPath, {
    void Function(double progress)? onProgress,
  }) async {
    // Initialize native bindings once
    if (!_bindingsInitialized) {
      sherpa_onnx.initBindings();
      _bindingsInitialized = true;
    }

    // Ensure models are present
    if (!await hasModels()) {
      await ensureModelsDownloaded();
    }

    // Convert to 16kHz mono WAV
    final docsDir = await getApplicationDocumentsDirectory();
    final wavPath = p.join(docsDir.path, 'diarization_temp.wav');

    final needsConversion = !audioPath.toLowerCase().endsWith('.wav');
    String processPath = audioPath;

    if (needsConversion) {
      debugPrint('[DiarizationService] Converting to 16kHz WAV...');
      final wavFile = File(wavPath);
      if (await wavFile.exists()) await wavFile.delete();

      final session = await FFmpegKit.execute(
        '-y -i "$audioPath" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
      );
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        throw Exception(
          'FFmpeg conversion failed (code ${returnCode?.getValue()})',
        );
      }
      processPath = wavPath;
    }

    try {
      // Read audio
      final waveData = sherpa_onnx.readWave(processPath);
      final audioDuration = waveData.samples.length / waveData.sampleRate;

      // Configure diarizer
      final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
          pyannote: sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
            model: await segModelPath,
          ),
        ),
        embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
          model: await embModelPath,
        ),
        clustering: sherpa_onnx.FastClusteringConfig(
          numClusters: -1,
          threshold: _threshold,
        ),
        minDurationOn: 0.3,
        minDurationOff: 0.5,
      );

      final sd = sherpa_onnx.OfflineSpeakerDiarization(config);

      // Run diarization
      final sw = Stopwatch()..start();
      final rawSegments = sd.processWithCallback(
        samples: waveData.samples,
        callback: (int processed, int total) {
          if (total > 0) {
            onProgress?.call(processed / total);
          }
          return 0;
        },
      );
      sw.stop();

      // Free native resources
      sd.free();

      // Convert to our segment type
      final rawSegs = rawSegments
          .map(
            (s) => DiarizationSegment(
              speaker: s.speaker,
              startSeconds: s.start,
              endSeconds: s.end,
            ),
          )
          .toList();

      // Post-process: merge minor speakers
      final processed = postProcessSegments(rawSegs, audioDuration);

      // Count final unique speakers
      final speakerIds = processed.map((s) => s.speaker).toSet();

      return DiarizationResult(
        speakerCount: speakerIds.length,
        segments: processed,
        processingTime: sw.elapsed,
        audioDurationSeconds: audioDuration,
        rawSegments: rawSegs,
      );
    } finally {
      // Clean up temp WAV
      if (needsConversion) {
        try {
          await File(wavPath).delete();
        } catch (_) {}
      }
    }
  }

  // ── Post-processing ───────────────────────────────────────────────────

  /// Merges minor speakers into the nearest major speaker.
  ///
  /// A speaker is "major" if both:
  ///   - Their share of total speech >= [minSharePercent]
  ///   - Their total speech duration >= [minDurationSec]
  ///
  /// This is deliberately public and static so that tests can sweep
  /// different threshold values against the same raw segment set
  /// without re-running the expensive inference.
  static List<DiarizationSegment> postProcessSegments(
    List<DiarizationSegment> segments,
    double totalAudioDuration, {
    double minSharePercent = _minSpeakerSharePercent,
    double minDurationSec = _minSpeakerDurationSec,
  }) {
    if (segments.isEmpty) return segments;

    // Calculate per-speaker totals
    final speakerDurations = <int, double>{};
    for (final seg in segments) {
      speakerDurations[seg.speaker] =
          (speakerDurations[seg.speaker] ?? 0) + seg.duration;
    }

    final totalSpeech = speakerDurations.values.fold(0.0, (a, b) => a + b);
    if (totalSpeech == 0) return segments;

    // Identify major speakers (above threshold)
    final majorSpeakers = <int>{};
    for (final entry in speakerDurations.entries) {
      final sharePercent = (entry.value / totalSpeech) * 100;
      if (sharePercent >= minSharePercent && entry.value >= minDurationSec) {
        majorSpeakers.add(entry.key);
      }
    }

    // If no major speakers found, keep the top 2 by duration
    if (majorSpeakers.isEmpty) {
      final sorted = speakerDurations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      majorSpeakers.addAll(sorted.take(2).map((e) => e.key));
    }

    debugPrint(
      '[DiarizationService] Major speakers: $majorSpeakers '
      '(from ${speakerDurations.length} total, '
      'minShare=$minSharePercent%, minDur=${minDurationSec}s)',
    );

    // Reassign minor speaker segments to nearest major speaker
    final merged = <DiarizationSegment>[];
    for (final seg in segments) {
      if (majorSpeakers.contains(seg.speaker)) {
        merged.add(seg);
      } else {
        // Find the nearest major speaker segment by time
        final midpoint = (seg.startSeconds + seg.endSeconds) / 2;
        int nearestSpeaker = majorSpeakers.first;
        double nearestDist = double.infinity;

        for (final other in segments) {
          if (!majorSpeakers.contains(other.speaker)) continue;
          final otherMid = (other.startSeconds + other.endSeconds) / 2;
          final dist = (midpoint - otherMid).abs();
          if (dist < nearestDist) {
            nearestDist = dist;
            nearestSpeaker = other.speaker;
          }
        }

        merged.add(
          DiarizationSegment(
            speaker: nearestSpeaker,
            startSeconds: seg.startSeconds,
            endSeconds: seg.endSeconds,
          ),
        );
      }
    }

    // Renumber speakers sequentially (0, 1, 2, ...)
    final speakerMap = <int, int>{};
    int nextId = 0;
    for (final seg in merged) {
      speakerMap.putIfAbsent(seg.speaker, () => nextId++);
    }

    return merged
        .map(
          (seg) => DiarizationSegment(
            speaker: speakerMap[seg.speaker]!,
            startSeconds: seg.startSeconds,
            endSeconds: seg.endSeconds,
          ),
        )
        .toList();
  }

  // ── Utilities ─────────────────────────────────────────────────────────


}
