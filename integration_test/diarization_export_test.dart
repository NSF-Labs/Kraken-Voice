/// Quick attribution export: re-diarize and export per-speaker WAV
/// segments to /data/local/tmp/ for adb pull.
///
/// Run:
///   flutter test integration_test/diarization_export_test.dart --flavor dev
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Export per-speaker WAV segments to /data/local/tmp/',
      (tester) async {
    final service = DiarizationService(downloadFile: ModelFileDownloader().download);

    // Delete the old Chinese eres2net model if present, to force NeMo download
    final docsDir0 = await getApplicationDocumentsDirectory();
    final oldModel = File('${docsDir0.path}/diarization_models/'
        '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx');
    if (await oldModel.exists()) {
      debugPrint('🔄 Removing old Chinese embedding model...');
      await oldModel.delete();
    }

    await service.ensureModelsDownloaded(
      onProgress: (_, label) => debugPrint('   $label'),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(docsDir.path, 'diarization_exports'));
    if (await exportDir.exists()) {
      await exportDir.delete(recursive: true);
    }
    await exportDir.create(recursive: true);

    // We'll also copy to /sdcard/Download/ for easy adb pull
    final pullDir = '/sdcard/Download/diarization_exports';
    try {
      await Directory(pullDir).create(recursive: true);
    } catch (_) {
      debugPrint('Note: Cannot create $pullDir, will try direct export');
    }

    final files = [
      ('/data/local/tmp/kraken_test_audio/Demo.m4a', 'Demo'),
      ('/data/local/tmp/kraken_test_audio/Demo_2.m4a', 'Demo_2'),
      ('/data/local/tmp/kraken_test_audio/Mom.m4a', 'Mom'),
    ];

    for (final (path, label) in files) {
      if (!await File(path).exists()) {
        debugPrint('⚠️ $label not found');
        continue;
      }

      debugPrint('');
      debugPrint('═══ $label ═══');

      // Diarize
      final result = await service.diarize(path, onProgress: (p) {
        if ((p * 100).toInt() % 25 == 0) {
          debugPrint('   ${(p * 100).toStringAsFixed(0)}%');
        }
      });

      debugPrint('   ${result.speakerCount} speakers detected');

      // Convert source to WAV for segment extraction
      final wavPath = p.join(docsDir.path, 'temp_$label.wav');
      await FFmpegKit.execute(
        '-y -i "$path" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
      );

      // Export per-speaker
      final speakers = result.segments.map((s) => s.speaker).toSet().toList()
        ..sort();

      for (final spk in speakers) {
        final segs = result.segments.where((s) => s.speaker == spk).toList();
        final dur = segs.fold<double>(0, (sum, s) => sum + s.duration);

        final outPath = p.join(exportDir.path, '${label}_speaker_$spk.wav');

        // Extract each segment individually, then concatenate.
        // The aselect filter approach was silently failing due to escaping.
        final segDir = Directory(p.join(docsDir.path, 'seg_tmp_$label'));
        if (await segDir.exists()) await segDir.delete(recursive: true);
        await segDir.create();

        final concatLines = <String>[];
        for (int i = 0; i < segs.length; i++) {
          final s = segs[i];
          final segPath = p.join(segDir.path, 'seg_${i.toString().padLeft(4, '0')}.wav');
          final segSession = await FFmpegKit.execute(
            '-y -i "$wavPath" '
            '-ss ${s.startSeconds.toStringAsFixed(3)} '
            '-to ${s.endSeconds.toStringAsFixed(3)} '
            '-c:a pcm_s16le "$segPath"',
          );
          if (ReturnCode.isSuccess(await segSession.getReturnCode())) {
            concatLines.add("file '$segPath'");
          }
        }

        // Write concat list
        final listPath = p.join(segDir.path, 'concat.txt');
        await File(listPath).writeAsString(concatLines.join('\n'));

        // Concatenate all segments
        final catSession = await FFmpegKit.execute(
          '-y -f concat -safe 0 -i "$listPath" -c:a pcm_s16le "$outPath"',
        );

        // Clean up temp segments
        try { await segDir.delete(recursive: true); } catch (_) {}

        if (ReturnCode.isSuccess(await catSession.getReturnCode())) {
          final kb = (File(outPath).lengthSync() / 1024).toStringAsFixed(0);
          debugPrint('   ✅ Speaker $spk → ${dur.toStringAsFixed(1)}s → $kb KB');
          // Copy to pullable location
          try {
            final pullPath = '$pullDir/${label}_speaker_$spk.wav';
            await File(outPath).copy(pullPath);
          } catch (_) {}
        } else {
          debugPrint('   ❌ Speaker $spk export failed');
        }
      }

      try { await File(wavPath).delete(); } catch (_) {}
    }

    debugPrint('');
    debugPrint('════════════════════════════════════════════');
    debugPrint('  Pull exports:');
    debugPrint('  adb pull /sdcard/Download/diarization_exports/ ./exports');
    debugPrint('════════════════════════════════════════════');

    // List final files
    final exported = exportDir.listSync();
    for (final f in exported) {
      debugPrint('  ${p.basename(f.path)}');
    }

    expect(exported.isNotEmpty, isTrue);
  });
}
