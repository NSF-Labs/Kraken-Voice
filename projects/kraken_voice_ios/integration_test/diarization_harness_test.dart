/// Diarization Test Harness
///
/// Reads all .wav files from /sdcard/diarization_clips/ on the device,
/// runs speaker diarization at thresholds 0.7, 0.8, 0.9 for each clip,
/// and outputs per-clip findings with segment timestamps.
///
/// ## Setup
///
/// 1. Convert recordings to 16kHz mono WAV:
///      ffmpeg -i clip.m4a -ar 16000 -ac 1 clip.wav
///
/// 2. Push to device:
///      adb shell mkdir -p /sdcard/diarization_clips
///      adb push clip1.wav /sdcard/diarization_clips/
///      adb push clip2.wav /sdcard/diarization_clips/
///
/// 3. Run:
///      flutter test integration_test/diarization_harness_test.dart --flavor dev
///
/// ## Output
///
/// - Console: per-clip, per-threshold speaker count + segment timeline
/// - JSON:    /sdcard/diarization_clips/results/<clip>_results.json
/// - Segments: /sdcard/diarization_clips/results/<clip>_seg_<N>_spk<S>.wav
///
/// Segment WAV files let you play each segment and verify speaker
/// attribution by ear.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

const _clipsDir = '/sdcard/diarization_clips';
const _thresholds = [0.7, 0.8, 0.9];

const _segModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';
const _embModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-recongition-models/'
    '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Diarization harness — per-clip multi-threshold evaluation', (
    tester,
  ) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  DIARIZATION TEST HARNESS');
    debugPrint('═══════════════════════════════════════════════════════');

    // ── Init ──
    sherpa_onnx.initBindings();

    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(docsDir.path, 'diarization_models'));
    if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

    final segModelPath = p.join(
      modelsDir.path,
      'sherpa-onnx-pyannote-segmentation-3-0',
      'model.onnx',
    );
    final embModelPath = p.join(
      modelsDir.path,
      '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
    );

    // ── Download models if needed ──
    if (!File(segModelPath).existsSync()) {
      debugPrint('⬇️ Downloading segmentation model...');
      final tarPath = p.join(modelsDir.path, 'seg.tar.bz2');
      await _downloadFile(_segModelUrl, tarPath);
      final r = await Process.run('tar', [
        'xjf',
        tarPath,
        '-C',
        modelsDir.path,
      ]);
      expect(r.exitCode, 0, reason: 'tar failed: ${r.stderr}');
      try {
        await File(tarPath).delete();
      } catch (_) {}
    }
    if (!File(embModelPath).existsSync()) {
      debugPrint('⬇️ Downloading embedding model...');
      await _downloadFile(_embModelUrl, embModelPath);
    }
    debugPrint('✅ Models ready');

    // ── Find clips ──
    final clipsDirectory = Directory(_clipsDir);
    if (!await clipsDirectory.exists()) {
      debugPrint('');
      debugPrint('❌ No clips folder found at $_clipsDir');
      debugPrint('');
      debugPrint('   To set up:');
      debugPrint('   1. ffmpeg -i recording.m4a -ar 16000 -ac 1 clip.wav');
      debugPrint('   2. adb shell mkdir -p $_clipsDir');
      debugPrint('   3. adb push clip.wav $_clipsDir/');
      debugPrint('');
      fail('Create $_clipsDir and add .wav files');
    }

    final wavFiles =
        clipsDirectory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    if (wavFiles.isEmpty) {
      fail('No .wav files found in $_clipsDir');
    }

    debugPrint('📂 Found ${wavFiles.length} clip(s) in $_clipsDir');
    for (final f in wavFiles) {
      debugPrint('   • ${p.basename(f.path)}');
    }

    // ── Results directory ──
    final resultsDir = Directory(p.join(_clipsDir, 'results'));
    if (!await resultsDir.exists()) await resultsDir.create(recursive: true);

    // ── Process each clip ──
    for (final wavFile in wavFiles) {
      final clipName = p.basenameWithoutExtension(wavFile.path);
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('  CLIP: $clipName');
      debugPrint('═══════════════════════════════════════════════════════');

      final waveData = sherpa_onnx.readWave(wavFile.path);
      final duration = waveData.samples.length / waveData.sampleRate;
      final fileSizeMb = wavFile.lengthSync() / 1024 / 1024;

      debugPrint('   Sample rate: ${waveData.sampleRate} Hz');
      debugPrint(
        '   Duration: ${duration.toStringAsFixed(1)}s '
        '(${(duration / 60).toStringAsFixed(1)} min)',
      );
      debugPrint('   File size: ${fileSizeMb.toStringAsFixed(1)} MB');

      if (waveData.sampleRate != 16000) {
        debugPrint(
          '   ⚠️ Sample rate is ${waveData.sampleRate}, '
          'expected 16000. Convert with:',
        );
        debugPrint(
          '   ffmpeg -i ${p.basename(wavFile.path)} '
          '-ar 16000 -ac 1 ${clipName}_16k.wav',
        );
        continue;
      }

      final clipResults = <Map<String, dynamic>>[];

      for (final threshold in _thresholds) {
        debugPrint('');
        debugPrint('  ── Threshold: $threshold ──');

        final config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
          segmentation: sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote: sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
              model: segModelPath,
            ),
          ),
          embedding: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model: embModelPath,
          ),
          clustering: sherpa_onnx.FastClusteringConfig(
            numClusters: -1,
            threshold: threshold,
          ),
          minDurationOn: 0.2,
          minDurationOff: 0.5,
        );

        final sd = sherpa_onnx.OfflineSpeakerDiarization(config);

        final sw = Stopwatch()..start();
        final segments = sd.processWithCallback(
          samples: waveData.samples,
          callback: (int done, int total) {
            if (done % 20 == 0 || done == total) {
              debugPrint('     ${(100.0 * done / total).toStringAsFixed(0)}%');
            }
            return 0;
          },
        );
        sw.stop();

        final speakerIds = segments.map((s) => s.speaker).toSet();
        final diaMs = sw.elapsedMilliseconds;
        final rtRatio = diaMs / (duration * 1000);

        debugPrint('');
        debugPrint('  ⏱️ ${diaMs}ms (${rtRatio.toStringAsFixed(2)}x RT)');
        debugPrint(
          '  📊 ${segments.length} segments, '
          '${speakerIds.length} speakers',
        );

        // Per-speaker summary
        for (final spk in speakerIds) {
          final segs = segments.where((s) => s.speaker == spk).toList();
          final total = segs.fold<double>(
            0,
            (s, seg) => s + (seg.end - seg.start),
          );
          debugPrint(
            '     Speaker $spk: ${segs.length} segs, '
            '${total.toStringAsFixed(1)}s',
          );
        }

        // Full timeline
        debugPrint('');
        debugPrint('  📝 Segment timeline:');
        for (int i = 0; i < segments.length; i++) {
          final s = segments[i];
          final durS = s.end - s.start;
          debugPrint(
            '     [$i] ${_ts(s.start)} → ${_ts(s.end)} '
            '(${durS.toStringAsFixed(1)}s)  Speaker ${s.speaker}',
          );
        }

        // Save per-segment WAV snippets (only for threshold 0.9)
        if (threshold == 0.9) {
          debugPrint('');
          debugPrint('  💾 Saving segment WAV snippets...');
          for (int i = 0; i < segments.length; i++) {
            final s = segments[i];
            final startSample = (s.start * waveData.sampleRate).round();
            final endSample = (s.end * waveData.sampleRate).round();
            final clampedStart = startSample.clamp(0, waveData.samples.length);
            final clampedEnd = endSample.clamp(0, waveData.samples.length);

            if (clampedEnd <= clampedStart) continue;

            final segSamples = Float32List.sublistView(
              waveData.samples,
              clampedStart,
              clampedEnd,
            );

            final segPath = p.join(
              resultsDir.path,
              '${clipName}_seg${i.toString().padLeft(2, '0')}'
              '_spk${s.speaker}.wav',
            );

            sherpa_onnx.writeWave(
              filename: segPath,
              samples: segSamples,
              sampleRate: waveData.sampleRate,
            );
          }
          debugPrint('     Saved ${segments.length} snippets to:');
          debugPrint('     ${resultsDir.path}/');
          debugPrint('');
          debugPrint('     Pull with: adb pull $_clipsDir/results/');
        }

        clipResults.add({
          'threshold': threshold,
          'diarization_ms': diaMs,
          'realtime_ratio': rtRatio,
          'num_segments': segments.length,
          'num_speakers': speakerIds.length,
          'speakers': speakerIds.toList(),
          'segments': segments
              .map(
                (s) => {
                  'index': segments.indexOf(s),
                  'start_s': double.parse(s.start.toStringAsFixed(2)),
                  'end_s': double.parse(s.end.toStringAsFixed(2)),
                  'duration_s': double.parse(
                    (s.end - s.start).toStringAsFixed(2),
                  ),
                  'speaker': s.speaker,
                },
              )
              .toList(),
        });

        sd.free();
      }

      // ── Per-clip threshold comparison ──
      debugPrint('');
      debugPrint('  ┌───────────┬──────────┬──────────┬───────────┐');
      debugPrint('  │ Threshold │ Speakers │ Segments │ Time (ms) │');
      debugPrint('  ├───────────┼──────────┼──────────┼───────────┤');
      for (final r in clipResults) {
        debugPrint(
          '  │ ${(r['threshold'] as double).toStringAsFixed(1)}'
          '       │ ${(r['num_speakers'] as int).toString().padLeft(8)}'
          ' │ ${(r['num_segments'] as int).toString().padLeft(8)}'
          ' │ ${(r['diarization_ms'] as int).toString().padLeft(9)} │',
        );
      }
      debugPrint('  └───────────┴──────────┴──────────┴───────────┘');

      // Save per-clip JSON
      final jsonPath = p.join(resultsDir.path, '${clipName}_results.json');
      await File(jsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'clip': clipName,
          'file': wavFile.path,
          'duration_s': duration,
          'sample_rate': waveData.sampleRate,
          'file_size_mb': fileSizeMb,
          'timestamp': DateTime.now().toIso8601String(),
          'thresholds': clipResults,
        }),
      );
      debugPrint('');
      debugPrint('  💾 JSON: $jsonPath');
    }

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  HARNESS COMPLETE');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('');
    debugPrint('  Pull all results:');
    debugPrint('    adb pull $_clipsDir/results/ ./diarization_results/');
    debugPrint('');
    debugPrint('  Segment WAVs are named:');
    debugPrint('    <clip>_seg<NN>_spk<S>.wav');
    debugPrint('  Play each to verify speaker attribution.');

    expect(wavFiles.isNotEmpty, isTrue);
  });
}

/// Format seconds as MM:SS.s
String _ts(double seconds) {
  final min = seconds ~/ 60;
  final sec = seconds % 60;
  return '${min.toString().padLeft(2, '0')}:${sec.toStringAsFixed(1).padLeft(4, '0')}';
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
        final loc = response.headers.value('location');
        await response.drain();
        if (loc == null) break;
        currentUrl = loc;
        continue;
      }
      final sink = File(outputPath).openWrite();
      int total = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        total += chunk.length;
      }
      await sink.close();
      debugPrint(
        '   ✅ Downloaded ${(total / 1024 / 1024).toStringAsFixed(1)} MB',
      );
      return;
    }
  } finally {
    client.close();
  }
}
