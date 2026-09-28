/// Diarization Validation Suite
///
/// Addresses three evidence gaps:
///   A) Attribution spot-check: per-speaker segment export for manual review
///   B) Additional test recordings: 4-speaker clip + synthesized brief-speaker clip
///   C) Post-processing threshold sensitivity sweep (8s, 10s, 15s)
///
/// Prerequisites:
///   adb push <file>.m4a /data/local/tmp/kraken_test_audio/<file>.m4a
///
/// Run:
///   flutter test integration_test/diarization_validation_test.dart --flavor dev --timeout 900s
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

  testWidgets('Diarization validation suite', (tester) async {
    final service = DiarizationService(downloadFile: ModelFileDownloader().download);
    await service.ensureModelsDownloaded(
      onProgress: (_, label) => debugPrint('   $label'),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('/data/local/tmp/diarization_exports');
    if (!await exportDir.exists()) await exportDir.create(recursive: true);

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE A: Attribution spot-check
    //  Run diarization, export per-speaker segments as WAV files
    // ═══════════════════════════════════════════════════════════════════

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  A) ATTRIBUTION SPOT-CHECK');
    debugPrint('═══════════════════════════════════════════════════════');

    final userFiles = [
      ('/data/local/tmp/kraken_test_audio/Demo.m4a', 'Demo', 2),
      ('/data/local/tmp/kraken_test_audio/Demo_2.m4a', 'Demo 2', 2),
      ('/data/local/tmp/kraken_test_audio/Mom.m4a', 'Mom', 3),
    ];

    final rawResults = <String, DiarizationResult>{};

    for (final (path, label, expectedSpeakers) in userFiles) {
      if (!await File(path).exists()) {
        debugPrint('   ⚠️ Skipping $label — not found');
        continue;
      }

      debugPrint('');
      debugPrint('── $label ──');
      final result = await service.diarize(path, onProgress: (p) {
        if ((p * 100).toInt() % 25 == 0) {
          debugPrint('   Progress: ${(p * 100).toStringAsFixed(0)}%');
        }
      });
      rawResults[label] = result;

      debugPrint('   Raw: ${result.rawSpeakerCount} speakers → '
          'Post-processed: ${result.speakerCount} speakers '
          '(expected: $expectedSpeakers)');

      // Export per-speaker WAV segments for manual listening
      // We need the converted WAV to extract from; re-convert once
      final wavPath = p.join(docsDir.path, 'temp_export_$label.wav');
      final session = await FFmpegKit.execute(
        '-y -i "$path" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"',
      );
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        debugPrint('   ❌ Cannot convert for export');
        continue;
      }

      // For each post-processed speaker, extract their segments
      final speakers = result.segments.map((s) => s.speaker).toSet().toList()
        ..sort();

      for (final spk in speakers) {
        final spkSegs = result.segments.where((s) => s.speaker == spk).toList();
        final totalDur =
            spkSegs.fold<double>(0, (sum, s) => sum + s.duration);
        final pct =
            (totalDur / result.audioDurationSeconds * 100).toStringAsFixed(0);

        debugPrint('');
        debugPrint('   Speaker $spk: ${spkSegs.length} segments, '
            '${totalDur.toStringAsFixed(1)}s ($pct%)');

        // Build ffmpeg filter to extract all segments for this speaker
        // into a single WAV file
        final outPath =
            p.join(exportDir.path, '${label}_speaker_$spk.wav');
        final filterParts = <String>[];
        for (int i = 0; i < spkSegs.length; i++) {
          final s = spkSegs[i];
          // Trim each segment
          filterParts.add(
              'between(t\\,${s.startSeconds.toStringAsFixed(3)}'
              '\\,${s.endSeconds.toStringAsFixed(3)})');
        }
        final filter =
            "aselect='${filterParts.join('+')}',asetpts=N/SR/TB";

        final exportSession = await FFmpegKit.execute(
          '-y -i "$wavPath" -af "$filter" "$outPath"',
        );
        if (ReturnCode.isSuccess(await exportSession.getReturnCode())) {
          final size = File(outPath).lengthSync();
          debugPrint('   → Exported: ${p.basename(outPath)} '
              '(${(size / 1024).toStringAsFixed(0)} KB)');
        } else {
          debugPrint('   → Export failed for speaker $spk');
        }

        // Print first 5 segment timestamps for visual inspection
        final limit = spkSegs.length.clamp(0, 5);
        for (int i = 0; i < limit; i++) {
          final s = spkSegs[i];
          debugPrint('      ${s.startSeconds.toStringAsFixed(1)}s → '
              '${s.endSeconds.toStringAsFixed(1)}s '
              '(${s.duration.toStringAsFixed(1)}s)');
        }
        if (spkSegs.length > 5) {
          debugPrint('      ... (${spkSegs.length - 5} more segments)');
        }
      }

      // Clean up temp WAV
      try {
        await File(wavPath).delete();
      } catch (_) {}
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE B: Additional test recordings
    // ═══════════════════════════════════════════════════════════════════

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  B) ADDITIONAL TEST RECORDINGS');
    debugPrint('═══════════════════════════════════════════════════════');

    // B1: Known 4-speaker Chinese clip (sherpa-onnx reference audio)
    debugPrint('');
    debugPrint('── B1: 4-Speaker Reference Clip ──');

    final fourSpkUrl =
        'https://huggingface.co/csukuangfj/sherpa-onnx-speaker-diarization-test-data'
        '/resolve/main/0-four-speakers-zh.wav';
    final fourSpkPath = p.join(docsDir.path, '4speakers_ref.wav');

    if (!File(fourSpkPath).existsSync()) {
      debugPrint('   ⬇️ Downloading 4-speaker reference clip...');
      await _downloadFile(fourSpkUrl, fourSpkPath);
    }

    final fourSpkResult = await service.diarize(fourSpkPath, onProgress: (p) {
      if ((p * 100).toInt() % 25 == 0) {
        debugPrint('   Progress: ${(p * 100).toStringAsFixed(0)}%');
      }
    });
    rawResults['4-Speaker Ref'] = fourSpkResult;

    debugPrint('   Raw: ${fourSpkResult.rawSpeakerCount} speakers → '
        'Post-processed: ${fourSpkResult.speakerCount} speakers '
        '(expected: 4)');

    // Per-speaker breakdown
    final fourSpkSpeakers =
        fourSpkResult.segments.map((s) => s.speaker).toSet().toList()..sort();
    for (final spk in fourSpkSpeakers) {
      final segs =
          fourSpkResult.segments.where((s) => s.speaker == spk).toList();
      final dur = segs.fold<double>(0, (sum, s) => sum + s.duration);
      debugPrint('      Speaker $spk: ${segs.length} segs, '
          '${dur.toStringAsFixed(1)}s');
    }

    // B2: Synthesize a "brief speaker" clip
    // Take Demo.m4a (2 speakers, ~2 min), inject a 15s segment
    // from Mom.m4a at the 60s mark to create a 3-speaker clip
    // where speaker 3 has only ~15s of speech
    debugPrint('');
    debugPrint('── B2: Brief Speaker (Synthesized) ──');

    final demoPath = '/data/local/tmp/kraken_test_audio/Demo.m4a';
    final momPath = '/data/local/tmp/kraken_test_audio/Mom.m4a';

    if (await File(demoPath).exists() && await File(momPath).exists()) {
      final briefSpkPath = p.join(docsDir.path, 'brief_speaker_test.wav');

      // Extract 15s from Mom (a distinct voice) and mix into Demo at 60s
      // 1) Convert Demo to WAV
      final demoWav = p.join(docsDir.path, 'brief_demo.wav');
      await FFmpegKit.execute(
        '-y -i "$demoPath" -ar 16000 -ac 1 -c:a pcm_s16le "$demoWav"',
      );
      // 2) Extract 15s from Mom starting at 40s (mid-recording, clear speech)
      final momClip = p.join(docsDir.path, 'brief_mom_clip.wav');
      await FFmpegKit.execute(
        '-y -i "$momPath" -ss 40 -t 15 -ar 16000 -ac 1 -c:a pcm_s16le '
        '"$momClip"',
      );
      // 3) Overlay mom's voice onto demo at the 60s mark
      // Use amerge to create a mix where mom's voice replaces demo at 60-75s
      final mixSession = await FFmpegKit.execute(
        '-y -i "$demoWav" -i "$momClip" '
        '-filter_complex '
        '"[1]adelay=60000|60000[delayed];'
        '[0][delayed]amix=inputs=2:duration=first:dropout_transition=0" '
        '"$briefSpkPath"',
      );

      if (ReturnCode.isSuccess(await mixSession.getReturnCode())) {
        debugPrint('   ✅ Synthesized brief-speaker clip');
        debugPrint('   Design: Demo (2 speakers) + 15s of Mom\'s voice at 60s');
        debugPrint('   Expected: 3 speakers (Speaker 3 has ~15s)');

        final briefResult =
            await service.diarize(briefSpkPath, onProgress: (p) {
          if ((p * 100).toInt() % 25 == 0) {
            debugPrint('   Progress: ${(p * 100).toStringAsFixed(0)}%');
          }
        });
        rawResults['Brief Speaker'] = briefResult;

        debugPrint('   Raw: ${briefResult.rawSpeakerCount} speakers → '
            'Post-processed: ${briefResult.speakerCount} speakers');

        // Key question: does the 15s speaker survive or get merged?
        final briefSpeakers =
            briefResult.segments.map((s) => s.speaker).toSet().toList()..sort();
        for (final spk in briefSpeakers) {
          final segs =
              briefResult.segments.where((s) => s.speaker == spk).toList();
          final dur = segs.fold<double>(0, (sum, s) => sum + s.duration);
          final pct =
              (dur / briefResult.audioDurationSeconds * 100).toStringAsFixed(0);
          debugPrint('      Speaker $spk: ${dur.toStringAsFixed(1)}s ($pct%)');
        }

        // Also show what happens with raw (no post-processing)
        final rawSpeakers =
            briefResult.rawSegments.map((s) => s.speaker).toSet();
        debugPrint('   Note: Raw detected ${rawSpeakers.length} speakers, '
            'post-processing → ${briefResult.speakerCount}');

        // Clean up
        try {
          await File(demoWav).delete();
          await File(momClip).delete();
        } catch (_) {}
      } else {
        debugPrint('   ❌ FFmpeg mix failed — skipping brief speaker test');
      }
    } else {
      debugPrint('   ⚠️ Demo or Mom not found — skipping');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE C: Threshold sensitivity sweep
    //  Re-apply post-processing with 8s, 10s, 15s on raw segments
    //  NO re-running of diarization — instant
    // ═══════════════════════════════════════════════════════════════════

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  C) THRESHOLD SENSITIVITY SWEEP');
    debugPrint('═══════════════════════════════════════════════════════');

    final thresholds = [8.0, 10.0, 15.0];

    // Header
    debugPrint('');
    final headerParts = ['Recording'.padRight(18)];
    headerParts.add('Raw'.padLeft(4));
    for (final t in thresholds) {
      headerParts.add('${t.toInt()}s'.padLeft(5));
    }
    debugPrint('   ${headerParts.join(' │ ')}');
    debugPrint('   ${'─' * (18 + 4 + thresholds.length * 8 + 6)}');

    for (final entry in rawResults.entries) {
      final label = entry.key;
      final result = entry.value;
      final raw = result.rawSegments;
      final dur = result.audioDurationSeconds;

      if (raw.isEmpty) continue;

      final parts = [label.padRight(18)];
      parts.add('${result.rawSpeakerCount}'.padLeft(4));

      for (final t in thresholds) {
        final processed = DiarizationService.postProcessSegments(
          raw,
          dur,
          minDurationSec: t,
        );
        final count = processed.map((s) => s.speaker).toSet().length;
        parts.add('$count'.padLeft(5));
      }

      debugPrint('   ${parts.join(' │ ')}');
    }

    // Detailed per-file analysis for each threshold
    debugPrint('');
    for (final entry in rawResults.entries) {
      final label = entry.key;
      final result = entry.value;
      final raw = result.rawSegments;
      final dur = result.audioDurationSeconds;

      if (raw.isEmpty) continue;

      debugPrint('');
      debugPrint('── $label: per-speaker durations at each threshold ──');

      // Show raw speaker durations
      final rawDurations = <int, double>{};
      for (final seg in raw) {
        rawDurations[seg.speaker] =
            (rawDurations[seg.speaker] ?? 0) + seg.duration;
      }
      final sortedRaw = rawDurations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      debugPrint('   Raw speakers (${sortedRaw.length} total):');
      for (final e in sortedRaw.take(8)) {
        final pct = (e.value / dur * 100).toStringAsFixed(0);
        debugPrint('      Spk ${e.key}: ${e.value.toStringAsFixed(1)}s ($pct%)');
      }
      if (sortedRaw.length > 8) {
        debugPrint('      ... (${sortedRaw.length - 8} more under '
            '${sortedRaw[7].value.toStringAsFixed(1)}s)');
      }

      for (final t in thresholds) {
        final processed = DiarizationService.postProcessSegments(
          raw,
          dur,
          minDurationSec: t,
        );
        final speakers = processed.map((s) => s.speaker).toSet().toList()
          ..sort();
        debugPrint('   At ${t.toInt()}s threshold → ${speakers.length} speakers');
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SUMMARY
    // ═══════════════════════════════════════════════════════════════════

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  VALIDATION SUMMARY');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('');
    debugPrint('  Speaker exports saved to: ${exportDir.path}');
    debugPrint('  → Pull with: adb pull ${exportDir.path} ./diarization_exports');
    debugPrint('');

    for (final entry in rawResults.entries) {
      debugPrint('  ${entry.key}: '
          'raw=${entry.value.rawSpeakerCount} → '
          'final=${entry.value.speakerCount} speakers, '
          '${entry.value.realtimeRatio.toStringAsFixed(2)}x RT');
    }

    expect(rawResults.isNotEmpty, isTrue);
  });
}

Future<void> _downloadFile(String url, String outputPath) async {
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
      final file = File(outputPath);
      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
      }
      await sink.close();
      return;
    }
    throw Exception('Too many redirects');
  } finally {
    client.close();
  }
}
