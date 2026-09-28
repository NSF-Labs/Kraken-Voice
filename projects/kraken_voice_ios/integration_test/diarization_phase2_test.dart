/// Diarization Spike — Phase 2: sherpa-onnx Speaker Diarization
///
/// Downloads pre-trained models + a known multi-speaker WAV,
/// runs offline diarization, and reports results.
///
/// Run on a connected device with:
///   flutter test integration_test/diarization_phase2_test.dart --flavor dev
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Model + test data URLs from sherpa-onnx GitHub releases
const _segModelDirectUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';

const _embModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-recongition-models/'
    '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

/// Known 4-speaker test file from sherpa-onnx releases
const _testWavUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-segmentation-models/0-four-speakers-zh.wav';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 2 · sherpa-onnx diarization on 4-speaker test clip',
      (tester) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  DIARIZATION SPIKE — Phase 2: sherpa-onnx');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');

    // Initialize sherpa-onnx native bindings
    // null = let Android linker find libsherpa-onnx-c-api.so from APK
    sherpa_onnx.initBindings();
    debugPrint('✅ sherpa-onnx native bindings initialized');

    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(docsDir.path, 'diarization_models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    // ── Step 1: Download models + test WAV if not cached ──
    debugPrint('');
    debugPrint('📦 Checking model files...');

    final segDir = Directory(
        p.join(modelsDir.path, 'sherpa-onnx-pyannote-segmentation-3-0'));
    final segModelPath = p.join(segDir.path, 'model.onnx');
    final embModelPath = p.join(modelsDir.path,
        '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx');
    final testWavPath = p.join(modelsDir.path, '0-four-speakers-zh.wav');

    // Download segmentation model (tar.bz2 → extract)
    if (!File(segModelPath).existsSync()) {
      debugPrint('⬇️ Downloading segmentation model (~6MB)...');
      final tarPath = p.join(modelsDir.path, 'seg.tar.bz2');
      await _downloadFile(_segModelDirectUrl, tarPath);

      try {
        final r = await Process.run('tar', ['xjf', tarPath, '-C', modelsDir.path]);
        if (r.exitCode == 0) {
          debugPrint('   ✅ Extracted segmentation model');
        } else {
          debugPrint('   ❌ tar failed: ${r.stderr}');
          fail('Cannot extract segmentation model — tar unavailable');
        }
      } catch (e) {
        fail('Cannot extract segmentation model: $e');
      }
      try { await File(tarPath).delete(); } catch (_) {}
    } else {
      debugPrint('   ✅ Segmentation model cached');
    }

    // Download embedding model
    if (!File(embModelPath).existsSync()) {
      debugPrint('⬇️ Downloading embedding model (~38MB)...');
      await _downloadFile(_embModelUrl, embModelPath);
    } else {
      debugPrint('   ✅ Embedding model cached');
    }

    // Download test WAV (known 4 speakers)
    if (!File(testWavPath).existsSync()) {
      debugPrint('⬇️ Downloading 4-speaker test WAV...');
      await _downloadFile(_testWavUrl, testWavPath);
    } else {
      debugPrint('   ✅ Test WAV cached');
    }

    // Verify all files exist
    expect(File(segModelPath).existsSync(), isTrue,
        reason: 'Segmentation model missing');
    expect(File(embModelPath).existsSync(), isTrue,
        reason: 'Embedding model missing');
    expect(File(testWavPath).existsSync(), isTrue,
        reason: 'Test WAV missing');

    final segSize = File(segModelPath).lengthSync();
    final embSize = File(embModelPath).lengthSync();
    final wavSize = File(testWavPath).lengthSync();
    debugPrint('');
    debugPrint('📊 File sizes:');
    debugPrint('   Segmentation model: ${_mb(segSize)} MB');
    debugPrint('   Embedding model:    ${_mb(embSize)} MB');
    debugPrint('   Total models:       ${_mb(segSize + embSize)} MB');
    debugPrint('   Test WAV:           ${_mb(wavSize)} MB');

    // ── Step 2: Configure + create diarizer ──
    debugPrint('');
    debugPrint('🧠 Configuring speaker diarization...');

    final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
      segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
        pyannote: sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
          model: segModelPath,
        ),
      ),
      embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
        model: embModelPath,
      ),
      // numClusters: -1 → auto-detect speaker count
      // threshold: 0.5  → default, lower = more speakers
      clustering: sherpa_onnx.FastClusteringConfig(
        numClusters: -1,
        threshold: 0.9,
      ),
      minDurationOn: 0.2,   // Min speech segment (seconds)
      minDurationOff: 0.5,  // Min silence gap (seconds)
    );

    final sd = sherpa_onnx.OfflineSpeakerDiarization(config);
    debugPrint('   ✅ Diarizer created');

    // ── Step 3: Read audio and run diarization ──
    debugPrint('');
    debugPrint('▶️ Reading test WAV...');
    final waveData = sherpa_onnx.readWave(testWavPath);
    debugPrint('   Sample rate: ${waveData.sampleRate} Hz');
    debugPrint('   Samples: ${waveData.samples.length}');
    final audioDuration = waveData.samples.length / waveData.sampleRate;
    debugPrint('   Duration: ${audioDuration.toStringAsFixed(1)}s');

    expect(sd.sampleRate, equals(waveData.sampleRate),
        reason: 'Sample rate mismatch');

    debugPrint('');
    debugPrint('🔬 Running diarization (this may take a while)...');

    final sw = Stopwatch()..start();
    final segments = sd.processWithCallback(
      samples: waveData.samples,
      callback: (int processed, int total) {
        final pct = 100.0 * processed / total;
        if (processed % 10 == 0 || processed == total) {
          debugPrint('   Progress: ${pct.toStringAsFixed(0)}% '
              '($processed/$total chunks)');
        }
        return 0; // 0 = continue, non-zero = abort
      },
    );
    sw.stop();

    // ── Step 4: Report results ──
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  RESULTS');
    debugPrint('═══════════════════════════════════════════════════');

    final diarizationMs = sw.elapsedMilliseconds;
    final realtimeRatio = diarizationMs / (audioDuration * 1000);
    final speakerIds = segments.map((s) => s.speaker).toSet();

    debugPrint('');
    debugPrint('⏱️ Diarization time: ${diarizationMs}ms '
        '(${realtimeRatio.toStringAsFixed(2)}x realtime)');
    debugPrint('📊 Segments: ${segments.length}');
    debugPrint('👥 Speakers detected: ${speakerIds.length}');
    debugPrint('   IDs: $speakerIds');
    debugPrint('');

    // Per-speaker breakdown
    for (final spk in speakerIds) {
      final spkSegs = segments.where((s) => s.speaker == spk).toList();
      final totalDur = spkSegs.fold<double>(
          0.0, (sum, s) => sum + (s.end - s.start));
      debugPrint('   Speaker $spk: ${spkSegs.length} segments, '
          '${totalDur.toStringAsFixed(1)}s total');
    }

    debugPrint('');
    debugPrint('📝 Segment timeline:');
    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      debugPrint('   ${s.start.toStringAsFixed(2)}s → '
          '${s.end.toStringAsFixed(2)}s  [Speaker ${s.speaker}]');
    }

    // ── Step 5: Save JSON results ──
    final jsonPath = p.join(docsDir.path, 'diarization_spike_phase2.json');
    final report = {
      'timestamp': DateTime.now().toIso8601String(),
      'device': 'S24 Ultra',
      'audio_file': '0-four-speakers-zh.wav',
      'audio_duration_s': audioDuration,
      'diarization_time_ms': diarizationMs,
      'realtime_ratio': realtimeRatio,
      'num_segments': segments.length,
      'num_speakers': speakerIds.length,
      'expected_speakers': 4,
      'speaker_ids': speakerIds.toList(),
      'model_sizes_mb': {
        'segmentation': segSize / 1024 / 1024,
        'embedding': embSize / 1024 / 1024,
        'total': (segSize + embSize) / 1024 / 1024,
      },
      'segments': segments
          .map((s) => {
                'start_s': s.start,
                'end_s': s.end,
                'speaker': s.speaker,
              })
          .toList(),
    };
    await File(jsonPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    debugPrint('');
    debugPrint('💾 Full results: $jsonPath');

    // ── Assertions ──
    debugPrint('');
    debugPrint('📋 Spike criteria:');

    final segOk = segments.isNotEmpty;
    final speedOk = diarizationMs < audioDuration * 1000 * 2; // < 2x realtime
    final speakerOk = speakerIds.length >= 2; // at least 2 of 4
    final sizeOk = (segSize + embSize) < 100 * 1024 * 1024; // < 100 MB

    debugPrint('   Segments produced: ${segOk ? "✅" : "❌"}');
    debugPrint('   Speed < 2x RT:    ${speedOk ? "✅" : "❌"} '
        '(${realtimeRatio.toStringAsFixed(2)}x)');
    debugPrint('   ≥2 speakers:      ${speakerOk ? "✅" : "❌"} '
        '(${speakerIds.length} found, 4 expected)');
    debugPrint('   Models < 100MB:   ${sizeOk ? "✅" : "❌"} '
        '(${_mb(segSize + embSize)} MB)');

    // Free native resources
    sd.free();

    expect(segOk, isTrue, reason: 'Should produce segments');
    expect(speakerOk, isTrue,
        reason: 'Should detect ≥2 speakers in 4-speaker clip');
  });
}

String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

/// Download a file, following redirects manually
Future<void> _downloadFile(String url, String outputPath) async {
  final client = HttpClient();
  try {
    var currentUrl = url;
    HttpClientResponse response;

    // Follow up to 5 redirects
    for (int i = 0; i < 5; i++) {
      final request = await client.getUrl(Uri.parse(currentUrl));
      request.followRedirects = false;
      response = await request.close();

      if (response.statusCode == 301 || response.statusCode == 302) {
        final location = response.headers.value('location');
        await response.drain();
        if (location == null) break;
        currentUrl = location;
        continue;
      }

      // Write response body
      final file = File(outputPath);
      final sink = file.openWrite();
      int total = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        total += chunk.length;
        if (total % (5 * 1024 * 1024) < chunk.length) {
          debugPrint('     ${_mb(total)} MB...');
        }
      }
      await sink.close();
      debugPrint('   ✅ Downloaded ${_mb(total)} MB');
      return;
    }
    fail('Too many redirects downloading $url');
  } finally {
    client.close();
  }
}
