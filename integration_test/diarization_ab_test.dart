/// A/B Model Comparison: Run Demo 2 through BOTH embedding models
/// with the fixed concat-based export, so the user can listen
/// side-by-side and pick the better one.
///
/// Run:
///   flutter test integration_test/diarization_ab_test.dart --flavor dev
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

  testWidgets('A/B: eres2net vs NeMo TitanNet on Demo 2', (tester) async {
    sherpa_onnx.initBindings();

    final service = DiarizationService(downloadFile: ModelFileDownloader().download);
    await service.ensureModelsDownloaded(
      onProgress: (_, label) => debugPrint('   $label'),
    );

    final segModel = await service.segModelPath;
    final nemoModel = await service.embModelPath; // NeMo (current)
    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = '${docsDir.path}/diarization_models';

    // Download eres2net if not present
    final eres2netFile = '$modelsDir/'
        '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';
    if (!await File(eres2netFile).exists()) {
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
          final file = File(eres2netFile);
          final sink = file.openWrite();
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

    // Test files
    final files = [
      ('/data/local/tmp/kraken_test_audio/Demo_2.m4a', 'Demo_2', 2),
      ('/data/local/tmp/kraken_test_audio/Demo.m4a', 'Demo', 2),
    ];

    // Models to compare
    final models = [
      (eres2netFile, 'eres2net_zh', 0.9),  // Chinese model at original threshold
      (nemoModel, 'nemo_en', 0.5),          // NeMo at sherpa-onnx default
    ];

    // Prepare pull directory
    final pullBase = '/sdcard/Download/diarization_ab';
    try {
      await Directory(pullBase).create(recursive: true);
    } catch (_) {}

    for (final (audioPath, label, expected) in files) {
      if (!await File(audioPath).exists()) {
        debugPrint('⚠️ $label not found');
        continue;
      }

      // Convert to WAV once
      final wavPath = p.join(docsDir.path, 'ab_$label.wav');
      final convertSession = await FFmpegKit.execute(
        '-y -i "$audioPath" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
      );
      if (!ReturnCode.isSuccess(await convertSession.getReturnCode())) {
        debugPrint('❌ WAV conversion failed for $label');
        continue;
      }

      final waveData = sherpa_onnx.readWave(wavPath);

      for (final (embModel, modelTag, threshold) in models) {
        debugPrint('');
        debugPrint('═══ $label × $modelTag (threshold=$threshold) ═══');

        final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
          segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote:
                sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
              model: segModel,
            ),
          ),
          embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model: embModel,
          ),
          clustering: sherpa_onnx.FastClusteringConfig(
            numClusters: -1,
            threshold: threshold,
          ),
          minDurationOn: 0.3,
          minDurationOff: 0.5,
        );

        final sd = sherpa_onnx.OfflineSpeakerDiarization(config);
        final rawSegments = sd.processWithCallback(
          samples: waveData.samples,
          callback: (int processed, int total) {
            final pct = (processed / total * 100).toInt();
            if (pct % 25 == 0) debugPrint('   $pct%');
            return 0;
          },
        );
        sd.free();

        // Convert to our types & post-process
        final rawSegs = rawSegments
            .map((s) => DiarizationSegment(
                  speaker: s.speaker,
                  startSeconds: s.start,
                  endSeconds: s.end,
                ))
            .toList();

        final audioDur = waveData.samples.length / waveData.sampleRate;
        final processed = DiarizationService.postProcessSegments(
          rawSegs,
          audioDur,
        );

        final rawCount = rawSegs.map((s) => s.speaker).toSet().length;
        final finalCount = processed.map((s) => s.speaker).toSet().length;
        final match = finalCount == expected ? '✅' : '❌';
        debugPrint('   raw=$rawCount → post=$finalCount $match');

        // Export per-speaker WAVs
        final speakers = processed.map((s) => s.speaker).toSet().toList()
          ..sort();

        final outDir = Directory(p.join(docsDir.path, 'ab_${label}_$modelTag'));
        if (await outDir.exists()) await outDir.delete(recursive: true);
        await outDir.create();

        final pullDir = '$pullBase/${label}_$modelTag';
        try {
          await Directory(pullDir).create(recursive: true);
        } catch (_) {}

        for (final spk in speakers) {
          final segs =
              processed.where((s) => s.speaker == spk).toList();
          final dur = segs.fold<double>(0, (sum, s) => sum + s.duration);

          final outPath = p.join(outDir.path, 'spk_$spk.wav');

          // Extract each segment then concat
          final segTmpDir =
              Directory(p.join(outDir.path, 'tmp_spk_$spk'));
          await segTmpDir.create();

          final concatLines = <String>[];
          for (int i = 0; i < segs.length; i++) {
            final s = segs[i];
            final segPath = p.join(
                segTmpDir.path, '${i.toString().padLeft(4, '0')}.wav');
            final ss = await FFmpegKit.execute(
              '-y -i "$wavPath" '
              '-ss ${s.startSeconds.toStringAsFixed(3)} '
              '-to ${s.endSeconds.toStringAsFixed(3)} '
              '-c:a pcm_s16le "$segPath"',
            );
            if (ReturnCode.isSuccess(await ss.getReturnCode())) {
              concatLines.add("file '$segPath'");
            }
          }

          final listPath = p.join(segTmpDir.path, 'concat.txt');
          await File(listPath).writeAsString(concatLines.join('\n'));

          final catSession = await FFmpegKit.execute(
            '-y -f concat -safe 0 -i "$listPath" -c:a pcm_s16le "$outPath"',
          );

          try {
            await segTmpDir.delete(recursive: true);
          } catch (_) {}

          if (ReturnCode.isSuccess(await catSession.getReturnCode())) {
            final kb =
                (File(outPath).lengthSync() / 1024).toStringAsFixed(0);
            debugPrint(
                '   ✅ Speaker $spk → ${dur.toStringAsFixed(1)}s → $kb KB');
            try {
              await File(outPath)
                  .copy('$pullDir/spk_$spk.wav');
            } catch (_) {}
          } else {
            debugPrint('   ❌ Speaker $spk export failed');
          }
        }
      }

      try {
        await File(wavPath).delete();
      } catch (_) {}
    }

    debugPrint('');
    debugPrint('════════════════════════════════════════════');
    debugPrint('  Pull A/B exports:');
    debugPrint('  adb pull /sdcard/Download/diarization_ab/ ./ab_exports');
    debugPrint('');
    debugPrint('  Compare folders:');
    debugPrint('    Demo_2_eres2net_zh/  vs  Demo_2_nemo_en/');
    debugPrint('    Demo_eres2net_zh/    vs  Demo_nemo_en/');
    debugPrint('════════════════════════════════════════════');
  });
}
