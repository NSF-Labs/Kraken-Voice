/// Diarization Spike — Phase 1: Capture Whisper segment baseline
///
/// This test records 30 seconds of audio on-device, transcribes it with
/// Whisper, and dumps the full segment list to evaluate:
///   - How many segments Whisper produces
///   - Average segment duration
///   - Whether segment boundaries align with natural speech pauses
///
/// Run on a connected device with:
///   flutter test integration_test/diarization_spike_test.dart --flavor dev
///
/// For best results, play a 2-speaker podcast or conversation clip through
/// a secondary speaker while this test runs, so the mic captures real
/// multi-speaker audio.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:krak_en_voice/kernel/audio/audio_channel.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase 1A: Record audio and transcribe with full segments
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('Phase 1A · Record 30s → transcribe → dump segments', (tester) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  DIARIZATION SPIKE — Phase 1A: Segment Baseline');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');
    debugPrint('📢 For best results, play a 2-speaker conversation');
    debugPrint('   near the device microphone during this test.');
    debugPrint('');

    // ── Step 1: Record 30 seconds of audio ──
    final engine = AudioEngine();
    final filePath = await engine.startRecording();
    expect(filePath, isNotNull, reason: 'Recording should start');
    debugPrint('🎙️ Recording started: $filePath');

    await Future.delayed(const Duration(seconds: 30));

    final stoppedPath = await engine.stopRecording();
    expect(stoppedPath, isNotEmpty);

    final audioFile = File(filePath!);
    final audioSize = await audioFile.length();
    debugPrint('📁 Audio captured: ${(audioSize / 1024).toStringAsFixed(1)} KB');

    engine.recordingState.value = AudioRecordingState.idle;
    engine.recordingDuration.value = Duration.zero;

    // ── Step 2: Transcribe with full segment data ──
    debugPrint('');
    debugPrint('🔄 Transcribing with Whisper (base model)...');
    final transcriptionEngine = TranscriptionEngine();

    // Release any stale model context to prevent OOM
    await transcriptionEngine.releaseWhisper();
    debugPrint('🧹 Released stale Whisper context');

    // Ensure model is downloaded before transcription
    await transcriptionEngine.downloadModel();
    debugPrint('✅ Model ready');

    final sw = Stopwatch()..start();
    final response = await transcriptionEngine.transcribeFileWithSegments(filePath);
    sw.stop();

    expect(response, isNotNull, reason: 'Whisper should return a response');

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  RESULTS');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');
    debugPrint('⏱️ Transcription time: ${sw.elapsedMilliseconds}ms');
    debugPrint('📝 Full text (${response!.text.length} chars):');
    debugPrint('   "${response.text}"');
    debugPrint('');
    final segments = response.segments ?? [];
    debugPrint('📊 Segments: ${segments.length} total');
    debugPrint('');

    // ── Step 3: Dump each segment ──
    int totalDurationMs = 0;
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final fromMs = seg.fromTs.inMilliseconds;
      final toMs = seg.toTs.inMilliseconds;
      final durationMs = toMs - fromMs;
      totalDurationMs += durationMs;

      debugPrint('  [$i] ${_fmtDuration(seg.fromTs)} → ${_fmtDuration(seg.toTs)} '
          '(${durationMs}ms) "${seg.text.trim()}"');
    }

    debugPrint('');
    if (segments.isNotEmpty) {
      final avgMs = totalDurationMs ~/ segments.length;
      debugPrint('📐 Average segment duration: ${avgMs}ms');
      debugPrint('📐 Total segment coverage: ${totalDurationMs}ms');
    }

    // ── Step 4: Save raw segment JSON for later analysis ──
    final docsDir = await getApplicationDocumentsDirectory();
    final jsonPath = p.join(docsDir.path, 'diarization_spike_segments.json');
    final segmentData = segments.map((s) => {
      'from_ms': s.fromTs.inMilliseconds,
      'to_ms': s.toTs.inMilliseconds,
      'text': s.text,
    }).toList();

    final jsonOutput = const JsonEncoder.withIndent('  ').convert({
      'timestamp': DateTime.now().toIso8601String(),
      'audio_path': filePath,
      'audio_size_bytes': audioSize,
      'transcription_time_ms': sw.elapsedMilliseconds,
      'full_text': response.text,
      'segment_count': segments.length,
      'segments': segmentData,
    });

    await File(jsonPath).writeAsString(jsonOutput);
    debugPrint('');
    debugPrint('💾 Raw segment data saved to: $jsonPath');
    debugPrint('');

    // ── Assertions ──
    expect(segments.length, greaterThan(0),
        reason: 'Whisper should produce at least one segment');
    expect(response.text.length, greaterThan(0),
        reason: 'Transcript should have some content (even ambient noise labels)');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase 1B: Transcribe an existing audio file (if available)
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('Phase 1B · Transcribe existing file → segment analysis', (tester) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  DIARIZATION SPIKE — Phase 1B: Existing File');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');

    // Check for any existing recordings in the app documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final audioFiles = Directory(docsDir.path)
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.m4a') ||
            f.path.endsWith('.wav') ||
            f.path.endsWith('.mp3'))
        .toList();

    if (audioFiles.isEmpty) {
      debugPrint('⚠️ No existing audio files found in ${docsDir.path}');
      debugPrint('   Skipping Phase 1B — Phase 1A results are sufficient.');
      return;
    }

    // Pick the largest file (most likely to be a real recording)
    audioFiles.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
    final testFile = audioFiles.first;
    final fileSize = testFile.lengthSync();
    debugPrint('📁 Using: ${p.basename(testFile.path)} (${(fileSize / 1024).toStringAsFixed(1)} KB)');

    final transcriptionEngine = TranscriptionEngine();
    final sw = Stopwatch()..start();
    final response = await transcriptionEngine.transcribeFileWithSegments(testFile.path);
    sw.stop();

    if (response == null) {
      debugPrint('❌ Transcription returned null — file may be corrupt');
      return;
    }

    debugPrint('');
    debugPrint('⏱️ Transcription time: ${sw.elapsedMilliseconds}ms');
    final segments = response.segments ?? [];
    debugPrint('📊 Segments: ${segments.length}');
    debugPrint('📝 Text length: ${response.text.length} chars');
    debugPrint('');

    // Analyze segment distribution
    final gaps = <int>[];
    for (int i = 1; i < segments.length; i++) {
      final prevEnd = segments[i - 1].toTs.inMilliseconds;
      final currStart = segments[i].fromTs.inMilliseconds;
      gaps.add(currStart - prevEnd);
    }

    if (gaps.isNotEmpty) {
      gaps.sort();
      debugPrint('📐 Gap analysis (between segments):');
      debugPrint('   Min gap: ${gaps.first}ms');
      debugPrint('   Max gap: ${gaps.last}ms');
      debugPrint('   Median gap: ${gaps[gaps.length ~/ 2]}ms');
      debugPrint('   Gaps > 500ms (potential speaker turns): '
          '${gaps.where((g) => g > 500).length}');
    }

    // Dump first 20 segments
    final limit = segments.length.clamp(0, 20);
    for (int i = 0; i < limit; i++) {
      final seg = segments[i];
      debugPrint('  [$i] ${_fmtDuration(seg.fromTs)} → ${_fmtDuration(seg.toTs)} '
          '"${seg.text.trim()}"');
    }
    if (segments.length > 20) {
      debugPrint('  ... (${segments.length - 20} more segments)');
    }
  });
}

String _fmtDuration(Duration d) {
  final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final ms = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
  return '$min:$sec.$ms';
}
