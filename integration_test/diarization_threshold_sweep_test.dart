/// Threshold sweep: run diarization on Demo with varying clustering
/// thresholds to find the value that produces correct speaker counts.
///
/// Run:
///   flutter test integration_test/diarization_threshold_sweep_test.dart --flavor dev
library;

import 'package:krak_en_voice/inference/model_file_downloader.dart';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/audio/diarization_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Threshold sweep on all recordings', (tester) async {
    final service = DiarizationService(downloadFile: ModelFileDownloader().download);
    await service.ensureModelsDownloaded(
      onProgress: (_, label) => debugPrint('   $label'),
    );

    sherpa_onnx.initBindings();

    final segModel = await service.segModelPath;
    final embModel = await service.embModelPath;
    final docsDir = await getApplicationDocumentsDirectory();

    // Skip Mom (15min) — crashes with OOM on long content.
    final files = [
      ('/data/local/tmp/kraken_test_audio/Demo.m4a', 'Demo', 2),
      ('/data/local/tmp/kraken_test_audio/Demo_2.m4a', 'Demo_2', 2),
    ];

    // Two arms:
    //   • Auto: native clustering with numClusters=-1 across thresholds
    //   • Forced: explicit numClusters=2 / numClusters=3 (bypasses threshold)
    final autoThresholds = [0.65, 0.70, 0.75, 0.80, 0.85, 0.90];
    final forcedCounts = [2, 3, 4];

    for (final (path, label, expected) in files) {
      if (!await File(path).exists()) {
        debugPrint('⚠️ $label not found');
        continue;
      }

      final wavPath = p.join(docsDir.path, 'sweep_$label.wav');
      await FFmpegKit.execute(
        '-y -i "$path" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
      );

      final waveData = sherpa_onnx.readWave(wavPath);
      final audioDuration = waveData.samples.length / waveData.sampleRate;

      debugPrint('');
      debugPrint(
        '═══ $label (expected: $expected speakers, '
        '${audioDuration.toStringAsFixed(0)}s) ═══',
      );

      // ── Arm A: auto clustering with threshold sweep ──
      debugPrint('  [auto / numClusters=-1]');
      for (final threshold in autoThresholds) {
        final result = _runDiarization(
          segModel: segModel,
          embModel: embModel,
          samples: waveData.samples,
          numClusters: -1,
          threshold: threshold,
          audioDuration: audioDuration,
        );
        final match = result.finalCount == expected ? '✅' : '❌';
        debugPrint(
          '   threshold=$threshold → '
          'raw=${result.rawCount}, final=${result.finalCount} $match',
        );
      }

      // ── Arm B: forced cluster count ──
      debugPrint('  [forced / numClusters=N]');
      for (final n in forcedCounts) {
        final result = _runDiarization(
          segModel: segModel,
          embModel: embModel,
          samples: waveData.samples,
          numClusters: n,
          threshold: 0.5, // ignored when numClusters > 0
          audioDuration: audioDuration,
        );
        final match = result.finalCount == expected ? '✅' : '❌';
        debugPrint(
          '   numClusters=$n → '
          'raw=${result.rawCount}, final=${result.finalCount} $match',
        );
      }

      try {
        await File(wavPath).delete();
      } catch (_) {}
    }

    debugPrint('');
    debugPrint('════════════════════════════════════════════');
    debugPrint('  Find the threshold where all rows show ✅');
    debugPrint('════════════════════════════════════════════');
  });
}

class _DiarResult {
  final int rawCount;
  final int finalCount;
  const _DiarResult(this.rawCount, this.finalCount);
}

_DiarResult _runDiarization({
  required String segModel,
  required String embModel,
  required dynamic samples,
  required int numClusters,
  required double threshold,
  required double audioDuration,
}) {
  final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
    segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
      pyannote: sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
        model: segModel,
      ),
    ),
    embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(model: embModel),
    clustering: sherpa_onnx.FastClusteringConfig(
      numClusters: numClusters,
      threshold: threshold,
    ),
    minDurationOn: 0.15,
    minDurationOff: 0.5,
  );

  final sd = sherpa_onnx.OfflineSpeakerDiarization(config);
  final rawSegments = sd.processWithCallback(
    samples: samples,
    callback: (int processed, int total) => 0,
  );
  sd.free();

  final rawSegs = rawSegments
      .map(
        (s) => DiarizationSegment(
          speaker: s.speaker,
          startSeconds: s.start,
          endSeconds: s.end,
        ),
      )
      .toList();

  final rawCount = rawSegs.map((s) => s.speaker).toSet().length;
  final processed = DiarizationService.postProcessSegments(
    rawSegs,
    audioDuration,
  );
  final finalCount = processed.map((s) => s.speaker).toSet().length;
  return _DiarResult(rawCount, finalCount);
}
