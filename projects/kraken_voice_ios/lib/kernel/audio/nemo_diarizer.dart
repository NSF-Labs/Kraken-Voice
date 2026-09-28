import 'dart:io';
import 'package:krak_en_voice/kernel/model_file_download.dart';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:krak_en_voice/kernel/model_storage_helper.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'diarizer.dart';
import 'embedding_cache.dart';

// ── Isolate support for background diarization ───────────────────────────
// compute() requires a TOP-LEVEL function and sendable parameter types.
// These live outside NemoDiarizer because Dart isolates cannot call
// instance methods or closures that capture non-sendable objects.

/// Parameter bundle sent to the background isolate.
class _DiarizeParams {
  final String wavPath;
  final String segModelPath;
  final String embModelPath;
  final double threshold;
  final int numClusters; // -1 = auto, > 0 = forced

  const _DiarizeParams({
    required this.wavPath,
    required this.segModelPath,
    required this.embModelPath,
    required this.threshold,
    required this.numClusters,
  });
}

/// Result bundle returned from the background isolate.
/// Uses only primitive/sendable types (no FFI pointers).
class _DiarizeIsolateResult {
  final List<Map<String, dynamic>> segments;
  final double audioDuration;

  const _DiarizeIsolateResult({
    required this.segments,
    required this.audioDuration,
  });
}

/// Top-level function executed in a background isolate via compute().
/// Initializes FFI bindings, reads the WAV, runs the heavy native
/// diarization pipeline, and returns sendable results.
_DiarizeIsolateResult _diarizeInIsolate(_DiarizeParams params) {
  // Each isolate has its own statics — re-init FFI bindings here.
  sherpa_onnx.initBindings();

  // Read audio (this allocates the big Float32List — but on this isolate's heap)
  final waveData = sherpa_onnx.readWave(params.wavPath);
  final audioDuration = waveData.samples.length / waveData.sampleRate;

  if (audioDuration < 3.0) {
    throw Exception(
      'Audio too short for diarization (${audioDuration.toStringAsFixed(1)}s). '
      'Minimum 3 seconds required.');
  }

  // Configure and run diarization
  final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
    segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
      pyannote: sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
        model: params.segModelPath,
      ),
    ),
    embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
      model: params.embModelPath,
    ),
    clustering: sherpa_onnx.FastClusteringConfig(
      numClusters: params.numClusters,
      threshold: params.threshold,
    ),
    minDurationOn: 0.3,
    minDurationOff: 0.5,
  );

  final sd = sherpa_onnx.OfflineSpeakerDiarization(config);

  final rawSegments = sd.processWithCallback(
    samples: waveData.samples,
    callback: (int processed, int total) => 0, // No cross-isolate progress
  );
  sd.free();

  // Convert to sendable types (no FFI pointers cross the boundary)
  final segments = rawSegments
      .map((s) => <String, dynamic>{
            'speaker': s.speaker,
            'start': s.start,
            'end': s.end,
          })
      .toList();

  return _DiarizeIsolateResult(
    segments: segments,
    audioDuration: audioDuration,
  );
}

/// Concrete [Diarizer] backed by NeMo TitanNet Small via sherpa-onnx.
///
/// This is the ONLY file in the codebase that imports sherpa_onnx.
/// All app code goes through the abstract [Diarizer] interface.
class NemoDiarizer implements Diarizer {
  // Singleton
  static final NemoDiarizer _instance = NemoDiarizer._internal();
  factory NemoDiarizer({required ModelFileDownload downloadFile}) {
    _instance._downloadFile = downloadFile;
    return _instance;
  }

  late ModelFileDownload _downloadFile;
  NemoDiarizer._internal();

  final EmbeddingCache _embeddingCache = EmbeddingCache();

  bool _bindingsInitialized = false;

  // ── Model URLs ──────────────────────────────────────────────────────────

  static const _segModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-segmentation-models/'
      'sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';

  // 3D-Speaker CAM++ (English, voxceleb-trained, 16kHz).
  // Replaced NeMo TitanNet Small in favor of better speaker
  // discrimination on conversational/meeting audio. Vector dimension
  // differs from the previous model — see embedding-cache invalidation
  // logic in [ensureModelsDownloaded] for the one-time migration.
  static const _embModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-recongition-models/'
      '3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx';

  /// Filename of the previous embedding model. Used by the migration
  /// path to delete the no-longer-needed file from disk.
  static const _legacyEmbModelFilename = 'nemo_en_titanet_small.onnx';

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

  // ── Post-processing constants ───────────────────────────────────────────

  /// Minimum speech percentage to qualify as a "real" speaker.
  static const double _minSpeakerSharePercent = 3.0;

  // ── Diarizer interface ──────────────────────────────────────────────────

  @override
  Future<bool> hasModels() async {
    final seg = File(await segModelPath);
    final emb = File(await embModelPath);
    return await seg.exists() && await emb.exists();
  }

  /// Downloads models if not already present, and migrates from the
  /// legacy TitanNet Small embedding model to CAM++ (deletes old .onnx
  /// and stale embedding caches).
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

    // One-time migration: delete the old TitanNet model if it's still
    // sitting on disk from a previous version of the app. New embedding
    // model is CAM++ (different filename).
    try {
      final legacy = File('$dir/$_legacyEmbModelFilename');
      if (await legacy.exists()) {
        debugPrint('[NemoDiarizer] Removing legacy embedding model '
            '($_legacyEmbModelFilename)');
        await legacy.delete();
      }
    } catch (e) {
      debugPrint('[NemoDiarizer] Could not delete legacy model: $e');
    }

    final emb = File(await embModelPath);
    if (!await emb.exists()) {
      onProgress?.call(0.5, 'Downloading embedding model...');
      await _downloadFile(_embModelUrl, emb.path);
    }

    onProgress?.call(1.0, 'Models ready');
  }

  @override
  Future<DiarizationResult> processRecording(
    String audioPath, {
    DiarizationConfig config = const DiarizationConfig(),
    String? embeddingsCachePath,
    void Function(double progress)? onProgress,
  }) async {
    _ensureBindings();

    if (!await hasModels()) {
      await ensureModelsDownloaded();
    }

    // Always convert to 16kHz mono WAV via FFmpeg to ensure correct format.
    // Even .wav files may have wrong sample rate or channel count which can
    // crash the native sherpa_onnx bindings.
    final docsDir = await getApplicationDocumentsDirectory();
    final wavPath = p.join(docsDir.path, 'diarization_temp.wav');
    debugPrint('[NemoDiarizer] Converting to 16kHz mono WAV...');
    
    final wavFile = File(wavPath);
    if (await wavFile.exists()) await wavFile.delete();

    final session = await FFmpegKit.execute(
      '-y -i "$audioPath" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
    );
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception(
          'FFmpeg conversion failed (code ${returnCode?.getValue()})');
    }
    
    // Validate converted file
    final convertedFile = File(wavPath);
    if (!await convertedFile.exists()) {
      throw Exception('FFmpeg produced no output file');
    }
    final convertedSize = await convertedFile.length();
    if (convertedSize < 1000) {
      throw Exception('Converted WAV too small ($convertedSize bytes) — audio may be corrupt');
    }
    debugPrint('[NemoDiarizer] Converted WAV: $convertedSize bytes');
    
    // Memory guard: for files over ~45 min (> 80MB WAV), skip embedding cache.
    // 16kHz × 2 bytes × 60s × 45min ≈ 86MB
    final isLargeFile = convertedSize > 80 * 1024 * 1024;
    if (isLargeFile) {
      debugPrint('[NemoDiarizer] ⚠️ Large file (${(convertedSize / 1024 / 1024).toStringAsFixed(0)}MB), '
          'skipping embedding cache to save memory.');
    }

    // Resolve model paths before entering the isolate (they use async path_provider).
    final resolvedSegModelPath = await segModelPath;
    final resolvedEmbModelPath = await embModelPath;

    try {
      // ── Run the heavy native work in a background isolate ────────────────
      // processWithCallback is a SYNCHRONOUS native FFI call that blocks the
      // calling Dart isolate's event loop. By using compute(), the main UI
      // isolate stays responsive (spinner keeps spinning, user can interact).
      debugPrint('[NemoDiarizer] Dispatching to background isolate...');
      final sw = Stopwatch()..start();

      final isolateResult = await compute(
        _diarizeInIsolate,
        _DiarizeParams(
          wavPath: wavPath,
          segModelPath: resolvedSegModelPath,
          embModelPath: resolvedEmbModelPath,
          threshold: config.threshold,
          numClusters: config.numSpeakers ?? -1,
        ),
      );
      sw.stop();

      debugPrint('[NemoDiarizer] Isolate returned in ${sw.elapsedMilliseconds}ms, '
          '${isolateResult.segments.length} raw segments, '
          'audio ${isolateResult.audioDuration.toStringAsFixed(1)}s');

      // Convert returned data back to our domain types
      final rawSegs = isolateResult.segments
          .map((s) => DiarizationSegment(
                speaker: s['speaker'] as int,
                startSeconds: s['start'] as double,
                endSeconds: s['end'] as double,
              ))
          .toList();

      onProgress?.call(0.7);

      // Step 2: Extract per-segment embeddings for caching (enables fast re-clustering)
      // For large files, skip embedding extraction to save memory.
      String? cachedPath;
      if (embeddingsCachePath != null && rawSegs.isNotEmpty && !isLargeFile) {
        debugPrint('[NemoDiarizer] Extracting per-segment embeddings for cache...');
        // Re-read wave data on main isolate for embedding extraction
        // (smaller files only, so memory is manageable)
        final waveData = sherpa_onnx.readWave(wavPath);
        final embeddings = await _extractSegmentEmbeddings(
          waveData.samples,
          waveData.sampleRate,
          rawSegs,
        );

        if (embeddings.isNotEmpty) {
          await _embeddingCache.save(embeddingsCachePath, embeddings);
          cachedPath = embeddingsCachePath;
        }
      } else if (isLargeFile) {
        debugPrint('[NemoDiarizer] Skipping embedding cache for large file to save memory');
      }

      onProgress?.call(0.9);

      // Step 3: Post-process (merge minor speakers)
      final processed = postProcessSegments(
        rawSegs,
        isolateResult.audioDuration,
        minDurationSec: config.minDuration,
      );

      final speakerIds = processed.map((s) => s.speaker).toSet();

      onProgress?.call(1.0);

      return DiarizationResult(
        speakerCount: speakerIds.length,
        segments: processed,
        processingTime: sw.elapsed,
        audioDurationSeconds: isolateResult.audioDuration,
        config: config,
        embeddingsPath: cachedPath,
        rawSegments: rawSegs,
      );
    } finally {
      try {
        await File(wavPath).delete();
      } catch (_) {}
    }
  }

  @override
  Future<DiarizationResult> reclusterRecording({
    required String embeddingsPath,
    required DiarizationConfig config,
  }) async {
    final sw = Stopwatch()..start();

    // Load cached embeddings
    final embeddings = await _embeddingCache.load(embeddingsPath);
    if (embeddings == null || embeddings.isEmpty) {
      throw StateError(
          'No cached embeddings found at $embeddingsPath. '
          'Run processRecording first.');
    }

    debugPrint('[NemoDiarizer] Re-clustering ${embeddings.length} segments '
        'with threshold=${config.threshold} '
        'numSpeakers=${config.numSpeakers ?? "auto"}');

    // Run agglomerative clustering on cached embeddings
    final clusterAssignments = _agglomerativeCluster(
      embeddings,
      threshold: config.threshold,
      forcedClusters: config.numSpeakers,
    );

    // Build segments with new speaker assignments
    final rawSegs = <DiarizationSegment>[];
    for (int i = 0; i < embeddings.length; i++) {
      rawSegs.add(DiarizationSegment(
        speaker: clusterAssignments[i],
        startSeconds: embeddings[i].startSeconds,
        endSeconds: embeddings[i].endSeconds,
      ));
    }

    // Calculate total audio duration from segment boundaries
    final audioDuration = embeddings.isEmpty
        ? 0.0
        : embeddings.map((e) => e.endSeconds).reduce(math.max);

    // Post-process
    final processed = postProcessSegments(
      rawSegs,
      audioDuration,
      minDurationSec: config.minDuration,
    );

    final speakerIds = processed.map((s) => s.speaker).toSet();
    sw.stop();

    debugPrint('[NemoDiarizer] Re-clustering complete in ${sw.elapsedMilliseconds}ms '
        '→ ${speakerIds.length} speakers');

    return DiarizationResult(
      speakerCount: speakerIds.length,
      segments: processed,
      processingTime: sw.elapsed,
      audioDurationSeconds: audioDuration,
      config: config,
      embeddingsPath: embeddingsPath,
      rawSegments: rawSegs,
    );
  }

  // ── Embedding extraction ──────────────────────────────────────────────

  /// Extracts per-segment speaker embeddings using SpeakerEmbeddingExtractor.
  Future<List<SegmentEmbedding>> _extractSegmentEmbeddings(
    Float32List allSamples,
    int sampleRate,
    List<DiarizationSegment> segments,
  ) async {
    final embModel = await embModelPath;
    final extractorConfig = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
      model: embModel,
    );
    final extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
      config: extractorConfig,
    );

    final results = <SegmentEmbedding>[];

    for (final seg in segments) {
      final startSample = (seg.startSeconds * sampleRate).round();
      final endSample = (seg.endSeconds * sampleRate).round()
          .clamp(0, allSamples.length);

      if (startSample >= endSample || startSample >= allSamples.length) continue;

      // Extract audio slice for this segment
      final slice = Float32List.sublistView(
        allSamples,
        startSample,
        endSample,
      );

      if (slice.length < sampleRate ~/ 10) continue; // Skip < 100ms segments

      // Feed audio into an OnlineStream, then compute embedding
      final stream = extractor.createStream();
      stream.acceptWaveform(samples: slice, sampleRate: sampleRate);
      // isReady is typically true immediately for offline extraction
      final embedding = extractor.compute(stream);
      stream.free();

      if (embedding.isEmpty) continue;

      results.add(SegmentEmbedding(
        startSeconds: seg.startSeconds,
        endSeconds: seg.endSeconds,
        embedding: embedding.toList(),
      ));
    }

    extractor.free();

    debugPrint('[NemoDiarizer] Extracted ${results.length} embeddings '
        '(dim=${results.isNotEmpty ? results.first.embedding.length : 0})');

    return results;
  }

  // ── Agglomerative clustering ──────────────────────────────────────────

  /// Simple agglomerative clustering using cosine *distance*.
  ///
  /// The [threshold] follows the same convention as the native sherpa-onnx
  /// FastClustering path and the in-app "Adjust Speakers" sheet:
  ///   • higher threshold → merge clusters that are farther apart →
  ///     more aggressive merging → fewer speakers
  ///   • lower threshold  → only merge very close clusters →
  ///     less merging → more speakers
  ///
  /// If [forcedClusters] is non-null, the algorithm ignores the threshold
  /// and keeps merging the closest pair until exactly that many clusters
  /// remain. Use this when the meeting size is known.
  List<int> _agglomerativeCluster(
    List<SegmentEmbedding> embeddings, {
    required double threshold,
    int? forcedClusters,
  }) {
    final n = embeddings.length;
    if (n == 0) return [];
    if (n == 1) return [0];

    // Initialize: each segment is its own cluster
    final assignments = List<int>.generate(n, (i) => i);

    // Precompute normalized embeddings for fast cosine similarity
    final normalized = embeddings.map((e) {
      final vec = e.embedding;
      final norm = math.sqrt(vec.fold<double>(0, (s, v) => s + v * v));
      if (norm == 0) return vec;
      return vec.map((v) => v / norm).toList();
    }).toList();

    // Pairwise cosine distance: 1 - cos_sim. Range [0, 2], with 0 = identical.
    final distance = List.generate(
      n,
      (i) => List.generate(n, (j) {
        if (i == j) return 0.0;
        double dot = 0;
        for (int k = 0; k < normalized[i].length; k++) {
          dot += normalized[i][k] * normalized[j][k];
        }
        return 1.0 - dot;
      }),
    );

    // Iteratively merge the two closest clusters. Stop condition depends
    // on whether a forced cluster count was given.
    while (true) {
      final clusterIds = assignments.toSet().toList();
      if (forcedClusters != null && clusterIds.length <= forcedClusters) {
        break;
      }

      double bestDist = double.infinity;
      int bestI = -1, bestJ = -1;

      for (int ci = 0; ci < clusterIds.length; ci++) {
        for (int cj = ci + 1; cj < clusterIds.length; cj++) {
          final d = _averageLinkDistance(
            assignments,
            clusterIds[ci],
            clusterIds[cj],
            distance,
          );
          if (d < bestDist) {
            bestDist = d;
            bestI = clusterIds[ci];
            bestJ = clusterIds[cj];
          }
        }
      }

      if (bestI == -1) break;

      // When auto-clustering, stop once the closest remaining pair is
      // farther apart than the threshold. When forced, keep merging
      // until we reach the target count regardless of distance.
      if (forcedClusters == null && bestDist > threshold) break;

      for (int i = 0; i < n; i++) {
        if (assignments[i] == bestJ) {
          assignments[i] = bestI;
        }
      }
    }

    // Renumber clusters sequentially (0, 1, 2, ...)
    final clusterMap = <int, int>{};
    int nextId = 0;
    for (int i = 0; i < n; i++) {
      clusterMap.putIfAbsent(assignments[i], () => nextId++);
    }
    return assignments.map((a) => clusterMap[a]!).toList();
  }

  /// Average-link cosine distance between two clusters.
  double _averageLinkDistance(
    List<int> assignments,
    int clusterA,
    int clusterB,
    List<List<double>> distance,
  ) {
    double total = 0;
    int count = 0;
    for (int i = 0; i < assignments.length; i++) {
      if (assignments[i] != clusterA) continue;
      for (int j = 0; j < assignments.length; j++) {
        if (assignments[j] != clusterB) continue;
        total += distance[i][j];
        count++;
      }
    }
    return count > 0 ? total / count : double.infinity;
  }

  // ── Post-processing ───────────────────────────────────────────────────

  /// Merges minor speakers into the nearest major speaker.
  ///
  /// A speaker is "major" if both:
  ///   - Their share of total speech >= [minSharePercent]
  ///   - Their total speech duration >= [minDurationSec]
  ///
  /// This is deliberately public and static so that re-clustering
  /// and tests can use it without instantiating the full service.
  static List<DiarizationSegment> postProcessSegments(
    List<DiarizationSegment> segments,
    double totalAudioDuration, {
    double minSharePercent = _minSpeakerSharePercent,
    double minDurationSec = 1.0,
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

    // Scale the minimum-duration gate so it never demands more than 5%
    // of total audio length. Without this, short clips (<minDurationSec)
    // collapse to "no major speakers" and fall through to the arbitrary
    // top-2-by-duration fallback, which mis-attributes minor segments.
    final effectiveMinDur = totalAudioDuration > 0
        ? math.min(minDurationSec, totalAudioDuration * 0.05)
        : minDurationSec;

    // Identify major speakers (above threshold)
    final majorSpeakers = <int>{};
    for (final entry in speakerDurations.entries) {
      final sharePercent = (entry.value / totalSpeech) * 100;
      if (sharePercent >= minSharePercent && entry.value >= effectiveMinDur) {
        majorSpeakers.add(entry.key);
      }
    }

    // If no major speakers found, keep the top 2 by duration
    if (majorSpeakers.isEmpty) {
      final sorted = speakerDurations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      majorSpeakers.addAll(sorted.take(2).map((e) => e.key));
    }

    debugPrint('[NemoDiarizer] Major speakers: $majorSpeakers '
        '(from ${speakerDurations.length} total, '
        'minShare=$minSharePercent%, minDur=${effectiveMinDur.toStringAsFixed(2)}s '
        'of ${totalAudioDuration.toStringAsFixed(1)}s audio)');

    // Reassign minor speaker segments to nearest major speaker
    final merged = <DiarizationSegment>[];
    for (final seg in segments) {
      if (majorSpeakers.contains(seg.speaker)) {
        merged.add(seg);
      } else {
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

        merged.add(DiarizationSegment(
          speaker: nearestSpeaker,
          startSeconds: seg.startSeconds,
          endSeconds: seg.endSeconds,
        ));
      }
    }

    // Renumber speakers sequentially (0, 1, 2, ...)
    final speakerMap = <int, int>{};
    int nextId = 0;
    for (final seg in merged) {
      speakerMap.putIfAbsent(seg.speaker, () => nextId++);
    }

    return merged
        .map((seg) => DiarizationSegment(
              speaker: speakerMap[seg.speaker]!,
              startSeconds: seg.startSeconds,
              endSeconds: seg.endSeconds,
            ))
        .toList();
  }

  // ── Private helpers ───────────────────────────────────────────────────

  void _ensureBindings() {
    if (!_bindingsInitialized) {
      sherpa_onnx.initBindings();
      _bindingsInitialized = true;
    }
  }


}
