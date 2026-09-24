/// Diarization Phase 3: Real user recordings via DiarizationService
///
/// Prerequisites:
///   adb push <file>.m4a /data/local/tmp/kraken_test_audio/<file>.m4a
///
/// Run on connected device:
///   flutter test integration_test/diarization_real_recordings_test.dart --flavor dev
library;

import 'package:krak_en_voice/inference/model_file_downloader.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/audio/diarization_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 3 · Diarize real recordings via DiarizationService',
      (tester) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  DIARIZATION — Phase 3: Real Recordings');
    debugPrint('  (with post-processing speaker merging)');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');

    final service = DiarizationService(downloadFile: ModelFileDownloader().download);

    // Ensure models
    await service.ensureModelsDownloaded(
      onProgress: (p, label) => debugPrint('   $label'),
    );

    // Target files (pushed via adb)
    final targets = [
      ('/data/local/tmp/kraken_test_audio/Demo.m4a', 'Demo'),
      ('/data/local/tmp/kraken_test_audio/Demo_2.m4a', 'Demo 2'),
      ('/data/local/tmp/kraken_test_audio/Mom.m4a', "Mom's radiologist"),
    ];

    final results = <(String, DiarizationResult)>[];

    for (final (path, label) in targets) {
      if (!await File(path).exists()) {
        debugPrint('⚠️ Skipping $label — file not found');
        continue;
      }

      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('  $label (${_mb(File(path).lengthSync())} MB)');
      debugPrint('═══════════════════════════════════════════════════');

      final result = await service.diarize(
        path,
        onProgress: (p) {
          if ((p * 100).toInt() % 25 == 0) {
            debugPrint('   Progress: ${(p * 100).toStringAsFixed(0)}%');
          }
        },
      );

      results.add((label, result));

      debugPrint('');
      debugPrint('   ⏱️ ${result.processingTime.inSeconds}s '
          '(${result.realtimeRatio.toStringAsFixed(2)}x RT)');
      debugPrint('   👥 ${result.speakerCount} speakers');
      debugPrint('   📊 ${result.segments.length} segments');

      // Per-speaker breakdown
      final speakerDur = <int, double>{};
      for (final seg in result.segments) {
        speakerDur[seg.speaker] = (speakerDur[seg.speaker] ?? 0) + seg.duration;
      }
      for (final entry in speakerDur.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))) {
        final pct = (entry.value / result.audioDurationSeconds * 100).toStringAsFixed(0);
        debugPrint('      Speaker ${entry.key}: '
            '${entry.value.toStringAsFixed(1)}s ($pct%)');
      }

      // First 20 segments
      debugPrint('');
      debugPrint('   📝 Timeline (first 20):');
      for (int i = 0; i < result.segments.length && i < 20; i++) {
        final s = result.segments[i];
        debugPrint('      ${s.startSeconds.toStringAsFixed(1)}s → '
            '${s.endSeconds.toStringAsFixed(1)}s  [Spk ${s.speaker}]');
      }
      if (result.segments.length > 20) {
        debugPrint('      ... (${result.segments.length - 20} more)');
      }
    }

    // Overall summary
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  OVERALL SUMMARY');
    debugPrint('═══════════════════════════════════════════════════');
    for (final (label, r) in results) {
      debugPrint('  $label: '
          '${_fmtDur(Duration(seconds: r.audioDurationSeconds.toInt()))} | '
          '${r.speakerCount} spk | '
          '${r.segments.length} seg | '
          '${r.realtimeRatio.toStringAsFixed(2)}x RT');
    }

    expect(results.isNotEmpty, isTrue,
        reason: 'Should process at least one file');
  });
}

String _mb(int b) => (b / 1024 / 1024).toStringAsFixed(1);
String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
}
