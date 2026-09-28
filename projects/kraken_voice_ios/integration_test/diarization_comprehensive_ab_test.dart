/// Comprehensive A/B comparison: eres2net vs NeMo TitanNet
///
/// Metrics per model per recording:
///   1. Speaker count vs ground truth (at multiple clustering thresholds)
///   2. Min-duration threshold sensitivity (8s, 10s, 15s, 20s)
///   3. Per-speaker WAV export for manual attribution review
///   4. Inference time on S24
///   5. Model file size
///
/// Run:
///   flutter test integration_test/diarization_comprehensive_ab_test.dart --flavor dev --timeout 1800s
library;

import 'package:krak_en_voice/inference/model_file_downloader.dart';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/audio/diarization_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Comprehensive A/B: eres2net vs NeMo', (tester) async {
    sherpa_onnx.initBindings();

    final service = DiarizationService(downloadFile: ModelFileDownloader().download);
    await service.ensureModelsDownloaded(
      onProgress: (_, label) => debugPrint('   $label'),
    );

    final segModel = await service.segModelPath;
    final nemoModel = await service.embModelPath;
    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = '${docsDir.path}/diarization_models';

    // ── Download eres2net if needed ──
    final eres2netPath = '$modelsDir/'
        '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';
    if (!await File(eres2netPath).exists()) {
      debugPrint('📥 Downloading eres2net model...');
      final url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
          'speaker-recongition-models/'
          '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';
      final client = HttpClient();
      try {
        var currentUrl = url;
        for (int i = 0; i < 5; i++) {
          final request = await client.getUrl(Uri.parse(currentUrl));
          request.followRedirects = false;
          final response = await request.close();
          if (response.statusCode == 301 || response.statusCode == 302) {
            final location = response.headers.value('location');
            await response.drain();
            if (location == null) break;
            currentUrl = location;
            continue;
          }
          final sink = File(eres2netPath).openWrite();
          await for (final chunk in response) {
            sink.add(chunk);
          }
          await sink.close();
          debugPrint('   eres2net downloaded');
          break;
        }
      } finally {
        client.close();
      }
    }

    // ── Metric 5: Model file sizes ──
    final eres2netSize = await File(eres2netPath).length();
    final nemoSize = await File(nemoModel).length();
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════╗');
    debugPrint('║  MODEL FILE SIZES                            ║');
    debugPrint('╠══════════════════════════════════════════════╣');
    debugPrint('║  eres2net (zh-cn): ${(eres2netSize / 1024 / 1024).toStringAsFixed(1)} MB');
    debugPrint('║  nemo_titanet (en): ${(nemoSize / 1024 / 1024).toStringAsFixed(1)} MB');
    debugPrint('╚══════════════════════════════════════════════╝');

    // ── Models config ──
    final models = <(String path, String tag, List<double> clusterThresholds)>[
      (eres2netPath, 'eres2net', [0.5, 0.7, 0.9]),
      (nemoModel, 'nemo', [0.5, 0.7, 0.9]),
    ];

    final minDurationValues = [8.0, 10.0, 15.0, 20.0];

    // ── Test recordings (path, label, expectedSpeakers) ──
    final recordings = [
      ('/data/local/tmp/kraken_test_audio/Demo_2.m4a', 'Demo_2', 2),
      ('/data/local/tmp/kraken_test_audio/Demo.m4a', 'Demo', 2),
      ('/data/local/tmp/kraken_test_audio/Mom.m4a', 'Mom', 3),
    ];

    // Pull directory
    final pullBase = '/sdcard/Download/diarization_comprehensive';
    try {
      final d = Directory(pullBase);
      if (await d.exists()) await d.delete(recursive: true);
      await d.create(recursive: true);
    } catch (_) {}

    // ══════════════════════════════════════════════════════════
    // MAIN LOOP: per recording
    // ══════════════════════════════════════════════════════════
    for (final (audioPath, label, expected) in recordings) {
      if (!await File(audioPath).exists()) {
        debugPrint('⚠️ $label not found at $audioPath — skipping');
        continue;
      }

      // Convert to WAV once
      final wavPath = p.join(docsDir.path, 'comprehensive_$label.wav');
      await FFmpegKit.execute(
        '-y -i "$audioPath" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
      );
      final waveData = sherpa_onnx.readWave(wavPath);
      final audioDur = waveData.samples.length / waveData.sampleRate;

      debugPrint('');
      debugPrint('┌────────────────────────────────────────────┐');
      debugPrint('│  RECORDING: $label');
      debugPrint('│  Duration: ${audioDur.toStringAsFixed(1)}s');
      debugPrint('│  Expected speakers: $expected');
      debugPrint('└────────────────────────────────────────────┘');

      // Per model
      for (final (embModelPath, modelTag, clusterThresholds) in models) {
        debugPrint('');
        debugPrint('  ┌── MODEL: $modelTag ──');

        // ── Try each clustering threshold ──
        // Track best: first threshold that matches expected count at minDur=10
        double? bestClusterThreshold;
        List<DiarizationSegment>? bestRawSegs;
        Duration? bestInferenceTime;

        for (final ct in clusterThresholds) {
          final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
            segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
              pyannote:
                  sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
                model: segModel,
              ),
            ),
            embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
              model: embModelPath,
            ),
            clustering: sherpa_onnx.FastClusteringConfig(
              numClusters: -1,
              threshold: ct,
            ),
            minDurationOn: 0.3,
            minDurationOff: 0.5,
          );

          final sd = sherpa_onnx.OfflineSpeakerDiarization(config);

          // ── Metric 4: Inference time ──
          final sw = Stopwatch()..start();
          final rawSegments = sd.processWithCallback(
            samples: waveData.samples,
            callback: (int processed, int total) => 0,
          );
          sw.stop();
          sd.free();

          final rawSegs = rawSegments
              .map((s) => DiarizationSegment(
                    speaker: s.speaker,
                    startSeconds: s.start,
                    endSeconds: s.end,
                  ))
              .toList();

          final rawCount = rawSegs.map((s) => s.speaker).toSet().length;

          // ── Metric 2: Min-duration threshold sensitivity ──
          debugPrint('  │');
          debugPrint('  │  cluster_threshold=$ct  '
              '(raw_speakers=$rawCount, inference=${sw.elapsed.inSeconds}s)');

          for (final minDur in minDurationValues) {
            final processed = DiarizationService.postProcessSegments(
              rawSegs,
              audioDur,
              minDurationSec: minDur,
            );
            final finalCount =
                processed.map((s) => s.speaker).toSet().length;
            final match = finalCount == expected ? '✅' : '❌';
            debugPrint(
                '  │    minDur=${minDur.toInt()}s → $finalCount speakers $match');
          }

          // Track best result (matching at minDur=10)
          final at10 = DiarizationService.postProcessSegments(
            rawSegs,
            audioDur,
            minDurationSec: 10.0,
          );
          if (at10.map((s) => s.speaker).toSet().length == expected &&
              bestClusterThreshold == null) {
            bestClusterThreshold = ct;
            bestRawSegs = rawSegs;
            bestInferenceTime = sw.elapsed;
          }
        }

        // ── Metric 3: Export per-speaker WAVs for best threshold ──
        if (bestRawSegs != null) {
          final processed = DiarizationService.postProcessSegments(
            bestRawSegs,
            audioDur,
            minDurationSec: 10.0,
          );

          debugPrint('  │');
          debugPrint(
              '  │  BEST: cluster=${bestClusterThreshold!.toStringAsFixed(1)}'
              '  inference=${bestInferenceTime!.inSeconds}s');

          final speakers =
              processed.map((s) => s.speaker).toSet().toList()..sort();

          final pullDir = '$pullBase/${label}_$modelTag';
          try {
            await Directory(pullDir).create(recursive: true);
          } catch (_) {}

          for (final spk in speakers) {
            final segs =
                processed.where((s) => s.speaker == spk).toList();
            final dur =
                segs.fold<double>(0, (sum, s) => sum + s.duration);

            final outPath = p.join(
                docsDir.path, '${label}_${modelTag}_spk$spk.wav');

            // Extract & concat segments
            final segTmpDir = Directory(
                p.join(docsDir.path, 'tmp_${label}_${modelTag}_$spk'));
            if (await segTmpDir.exists()) {
              await segTmpDir.delete(recursive: true);
            }
            await segTmpDir.create();

            final concatLines = <String>[];
            for (int i = 0; i < segs.length; i++) {
              final s = segs[i];
              final segFile = p.join(segTmpDir.path,
                  '${i.toString().padLeft(4, '0')}.wav');
              final ss = await FFmpegKit.execute(
                '-y -i "$wavPath" '
                '-ss ${s.startSeconds.toStringAsFixed(3)} '
                '-to ${s.endSeconds.toStringAsFixed(3)} '
                '-c:a pcm_s16le "$segFile"',
              );
              if (ReturnCode.isSuccess(await ss.getReturnCode())) {
                concatLines.add("file '$segFile'");
              }
            }

            final listPath = p.join(segTmpDir.path, 'concat.txt');
            await File(listPath).writeAsString(concatLines.join('\n'));

            final cat = await FFmpegKit.execute(
              '-y -f concat -safe 0 -i "$listPath" '
              '-c:a pcm_s16le "$outPath"',
            );

            try {
              await segTmpDir.delete(recursive: true);
            } catch (_) {}

            if (ReturnCode.isSuccess(await cat.getReturnCode())) {
              final kb =
                  (File(outPath).lengthSync() / 1024).toStringAsFixed(0);
              debugPrint('  │  ✅ Spk $spk: '
                  '${dur.toStringAsFixed(1)}s / ${segs.length} segments'
                  ' → $kb KB');
              try {
                await File(outPath).copy('$pullDir/spk_$spk.wav');
              } catch (_) {}
            }
          }
        } else {
          debugPrint('  │  ⚠️ No clustering threshold matched expected=$expected');
        }

        debugPrint('  └──────────────────────');
      }

      try {
        await File(wavPath).delete();
      } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════
    // SUMMARY
    // ══════════════════════════════════════════════════════════
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════╗');
    debugPrint('║  PULL ALL EXPORTS:                           ║');
    debugPrint('║  adb pull $pullBase/ ./comprehensive_exports');
    debugPrint('║                                              ║');
    debugPrint('║  Folders:                                    ║');
    for (final (_, label, _) in recordings) {
      debugPrint('║    ${label}_eres2net/  vs  ${label}_nemo/');
    }
    debugPrint('╚══════════════════════════════════════════════╝');
  });
}
