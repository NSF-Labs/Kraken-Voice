/// Diarization Calibration Harness
///
/// Spec-driven runner: drop an audio file plus a sidecar `<name>.spec.json`
/// into [integration_test/fixtures/diarization_calibration/], push that
/// folder to the device, and run this test. The harness will:
///
///   1. Run [NemoDiarizer.processRecording] on each audio file with the
///      production defaults (or per-spec overrides).
///   2. Capture raw + post-process speaker counts, full segment timeline,
///      and processing time.
///   3. If `ground_truth_timeline` is present in the spec, compute per-turn
///      match %.
///   4. Write a structured JSON report to
///      [/data/local/tmp/diarization_calibration/results/<name>_report.json]
///      and stream a human-readable summary to debugPrint so the agent can
///      read the result from `flutter test` stdout.
///
/// ## Setup
///
/// Push fixtures to the device once (or whenever they change):
///
///   adb shell mkdir -p /data/local/tmp/diarization_calibration
///   adb push integration_test/fixtures/diarization_calibration/. \
///            /data/local/tmp/diarization_calibration/
///
/// Run:
///
///   flutter test integration_test/diarization_calibration_test.dart \
///                --flavor dev --timeout 900s
///
/// ## Spec format (`<name>.spec.json`)
///
/// Required:
///   `expected_speakers`: int — how many distinct speakers the recording
///                              actually has.
///
/// Optional:
///   `ground_truth_timeline`: list of `[startSec, endSec, speakerLabel]`.
///                            If provided, the harness aligns post-process
///                            speakers to the labels and reports per-turn
///                            match %.
///   `threshold_override`:    double — passed to DiarizationConfig.
///   `num_speakers_override`: int — forces an exact cluster count.
library;

import 'package:krak_en_voice/inference/model_file_downloader.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/audio/diarizer.dart';
import 'package:krak_en_voice/kernel/audio/nemo_diarizer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the agent expects to find pushed fixtures on the device. Apps can
/// read from /data/local/tmp/ but Android SELinux blocks writes — results
/// land in app-external storage instead so `adb pull` still works.
const _fixturesDir = '/data/local/tmp/diarization_calibration';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Diarization calibration harness', (tester) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  DIARIZATION CALIBRATION HARNESS');
    debugPrint('═══════════════════════════════════════════════════════');

    final fixturesRoot = Directory(_fixturesDir);
    if (!await fixturesRoot.exists()) {
      fail(
        'Fixtures directory $_fixturesDir not found on device. '
        'Run: adb push integration_test/fixtures/diarization_calibration/. '
        '$_fixturesDir/',
      );
    }

    // App-writable destination. On Android this resolves under the dev
    // flavor's external dir, e.g. /storage/emulated/0/Android/data/
    // com.kraken.hub.kraken_hub.dev/files/diarization_calibration_results/
    // — readable by `adb pull` without `run-as`.
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      fail('getExternalStorageDirectory() returned null. The harness needs '
          'an app-writable directory to dump reports.');
    }
    final resultsDir = p.join(externalDir.path, 'diarization_calibration_results');
    final resultsRoot = Directory(resultsDir);
    if (!await resultsRoot.exists()) {
      await resultsRoot.create(recursive: true);
    }
    debugPrint('   Results will be written to: $resultsDir');

    final diarizer = NemoDiarizer(downloadFile: ModelFileDownloader().download);
    debugPrint('   Ensuring diarization models are present...');
    await diarizer.ensureModelsDownloaded(
      onProgress: (_, label) => debugPrint('   $label'),
    );

    final fixtures = await _discoverFixtures(fixturesRoot);
    if (fixtures.isEmpty) {
      fail('No audio fixtures found in $_fixturesDir. '
          'Each audio file needs a matching <name>.spec.json sidecar.');
    }

    debugPrint('');
    debugPrint('   Found ${fixtures.length} fixture(s):');
    for (final f in fixtures) {
      debugPrint('     - ${p.basename(f.audioPath)} '
          '(expected_speakers=${f.spec.expectedSpeakers})');
    }

    final allReports = <Map<String, dynamic>>[];
    int passed = 0;
    int failed = 0;

    for (final fixture in fixtures) {
      debugPrint('');
      debugPrint('───────────────────────────────────────────────────────');
      debugPrint('  ${p.basename(fixture.audioPath)}');
      debugPrint('───────────────────────────────────────────────────────');

      // Build the list of configs to run. Sweep mode takes precedence over
      // a single thresholdOverride.
      final configs = <DiarizationConfig>[];
      if (fixture.spec.thresholdSweep.isNotEmpty) {
        for (final t in fixture.spec.thresholdSweep) {
          configs.add(DiarizationConfig(
            threshold: t,
            numSpeakers: fixture.spec.numSpeakersOverride,
          ));
        }
      } else {
        configs.add(DiarizationConfig(
          threshold: fixture.spec.thresholdOverride ?? 0.75,
          numSpeakers: fixture.spec.numSpeakersOverride,
        ));
      }

      final fixtureReports = <Map<String, dynamic>>[];
      for (final config in configs) {
        if (configs.length > 1) {
          debugPrint('');
          debugPrint('   ─── threshold=${config.threshold.toStringAsFixed(2)} '
              'numSpeakers=${config.numSpeakers ?? "auto"} ───');
        }
        final report = await _runFixture(diarizer, fixture, config);
        allReports.add(report);
        fixtureReports.add(report);
        if (report['passed'] == true) {
          passed++;
        } else {
          failed++;
        }
      }

      final reportPath = p.join(
        resultsDir,
        '${p.basenameWithoutExtension(fixture.audioPath)}_report.json',
      );
      // For sweep mode, write the full list; for single-config mode, write
      // the lone report unwrapped so existing consumers keep working.
      final payload = configs.length > 1 ? fixtureReports : fixtureReports.first;
      await File(reportPath)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
      debugPrint('   Wrote $reportPath');
    }

    // Aggregate report
    final summaryPath = p.join(resultsDir, '_summary.json');
    await File(summaryPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'total': fixtures.length,
        'passed': passed,
        'failed': failed,
        'reports': allReports,
      }),
    );

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('  SUMMARY: $passed passed / $failed failed '
        '(${fixtures.length} total)');
    debugPrint('  Aggregate report: $summaryPath');
    debugPrint('═══════════════════════════════════════════════════════');

    // Don't fail the test on count mismatch — that's a measurement, not a bug.
    // The agent reads the JSON report to interpret pass/fail per fixture.
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<List<_Fixture>> _discoverFixtures(Directory root) async {
  final entries = await root.list().toList();
  final audioExts = {'.wav', '.m4a', '.mp3', '.aac', '.flac', '.ogg'};
  final fixtures = <_Fixture>[];

  for (final entry in entries) {
    if (entry is! File) continue;
    final ext = p.extension(entry.path).toLowerCase();
    if (!audioExts.contains(ext)) continue;

    final stem = p.basenameWithoutExtension(entry.path);
    final specPath = p.join(p.dirname(entry.path), '$stem.spec.json');
    final specFile = File(specPath);
    if (!await specFile.exists()) {
      debugPrint('   ⚠️  Skipping ${p.basename(entry.path)} — '
          'no matching ${p.basename(specPath)}');
      continue;
    }

    try {
      final raw = await specFile.readAsString();
      final spec = _Spec.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      fixtures.add(_Fixture(audioPath: entry.path, spec: spec));
    } catch (e) {
      debugPrint('   ⚠️  Skipping ${p.basename(entry.path)} — '
          'spec parse error: $e');
    }
  }

  fixtures.sort((a, b) => a.audioPath.compareTo(b.audioPath));
  return fixtures;
}

Future<Map<String, dynamic>> _runFixture(
  NemoDiarizer diarizer,
  _Fixture fixture,
  DiarizationConfig config,
) async {
  debugPrint('   Config: threshold=${config.threshold} '
      'numSpeakers=${config.numSpeakers ?? "auto"}');

  final sw = Stopwatch()..start();
  final result = await diarizer.processRecording(
    fixture.audioPath,
    config: config,
    onProgress: (p) {
      final pct = (p * 100).toInt();
      if (pct % 25 == 0 && pct > 0) {
        debugPrint('   Progress: $pct%');
      }
    },
  );
  sw.stop();

  final rawCount = result.rawSpeakerCount;
  final postCount = result.speakerCount;
  final expected = fixture.spec.expectedSpeakers;
  final countMatches = postCount == expected;

  debugPrint('   Raw speakers:          $rawCount');
  debugPrint('   Post-process speakers: $postCount  (expected $expected)  '
      '${countMatches ? "✅" : "❌"}');
  debugPrint('   Audio duration:        ${result.audioDurationSeconds.toStringAsFixed(1)}s');
  debugPrint('   Processing time:       ${sw.elapsed.inSeconds}s '
      '(rt-ratio ${result.realtimeRatio.toStringAsFixed(2)})');

  // Per-speaker speech share
  final perSpeakerDur = <int, double>{};
  for (final seg in result.segments) {
    perSpeakerDur[seg.speaker] =
        (perSpeakerDur[seg.speaker] ?? 0) + seg.duration;
  }
  final totalSpeech = perSpeakerDur.values.fold<double>(0, (a, b) => a + b);
  final speakers = perSpeakerDur.keys.toList()..sort();
  for (final spk in speakers) {
    final dur = perSpeakerDur[spk]!;
    final pct = totalSpeech > 0 ? (dur / totalSpeech * 100) : 0;
    debugPrint('     speaker $spk: ${dur.toStringAsFixed(1)}s '
        '(${pct.toStringAsFixed(0)}%)');
  }

  // Optional: per-turn match against ground truth
  double? matchPercent;
  if (fixture.spec.groundTruthTimeline != null &&
      fixture.spec.groundTruthTimeline!.isNotEmpty) {
    matchPercent = _computeTurnMatch(
      result.segments,
      fixture.spec.groundTruthTimeline!,
    );
    debugPrint('   Per-turn match:        '
        '${matchPercent.toStringAsFixed(1)}%');
  }

  // The pass criterion is count-only when no ground truth is provided.
  final passed = countMatches &&
      (matchPercent == null || matchPercent >= 90.0);

  return {
    'fixture': p.basename(fixture.audioPath),
    'expected_speakers': expected,
    'raw_speaker_count': rawCount,
    'post_process_speaker_count': postCount,
    'count_matches': countMatches,
    'audio_duration_s': result.audioDurationSeconds,
    'processing_time_ms': sw.elapsedMilliseconds,
    'realtime_ratio': result.realtimeRatio,
    'config': config.toJson(),
    'per_speaker_seconds': {
      for (final spk in speakers) '$spk': perSpeakerDur[spk],
    },
    'segments': result.segments.map((s) => s.toJson()).toList(),
    'raw_segments': result.rawSegments.map((s) => s.toJson()).toList(),
    'per_turn_match_percent': ?matchPercent,
    'passed': passed,
  };
}

/// Best-effort per-turn match: maps each ground-truth turn to the predicted
/// speaker that owns the most overlap, then reports the fraction of total
/// ground-truth time correctly attributed when the same predicted speaker
/// consistently maps to the same ground-truth label.
double _computeTurnMatch(
  List<DiarizationSegment> predicted,
  List<List<dynamic>> groundTruth,
) {
  // Build per-(predictedSpeaker, gtLabel) overlap matrix.
  final overlap = <int, Map<String, double>>{};
  for (final turn in groundTruth) {
    final gtStart = (turn[0] as num).toDouble();
    final gtEnd = (turn[1] as num).toDouble();
    final gtLabel = turn[2] as String;
    for (final seg in predicted) {
      final ov = _overlapSeconds(gtStart, gtEnd, seg.startSeconds, seg.endSeconds);
      if (ov <= 0) continue;
      overlap.putIfAbsent(seg.speaker, () => {});
      overlap[seg.speaker]![gtLabel] =
          (overlap[seg.speaker]![gtLabel] ?? 0) + ov;
    }
  }

  // Greedy 1:1 assignment: for each predicted speaker, pick the gt label it
  // overlaps most with (and vice versa). Captures the "speaker-id permutation"
  // that diarization is allowed to choose freely.
  final assignment = <int, String>{};
  for (final entry in overlap.entries) {
    final spk = entry.key;
    final byLabel = entry.value;
    if (byLabel.isEmpty) continue;
    final best = byLabel.entries.reduce((a, b) => a.value >= b.value ? a : b);
    assignment[spk] = best.key;
  }

  double matched = 0;
  double total = 0;
  for (final turn in groundTruth) {
    final gtStart = (turn[0] as num).toDouble();
    final gtEnd = (turn[1] as num).toDouble();
    final gtLabel = turn[2] as String;
    final dur = gtEnd - gtStart;
    total += dur;
    for (final seg in predicted) {
      final ov = _overlapSeconds(gtStart, gtEnd, seg.startSeconds, seg.endSeconds);
      if (ov <= 0) continue;
      if (assignment[seg.speaker] == gtLabel) matched += ov;
    }
  }

  return total > 0 ? (matched / total * 100) : 0.0;
}

double _overlapSeconds(double aStart, double aEnd, double bStart, double bEnd) {
  final s = aStart > bStart ? aStart : bStart;
  final e = aEnd < bEnd ? aEnd : bEnd;
  final d = e - s;
  return d > 0 ? d : 0.0;
}

class _Fixture {
  final String audioPath;
  final _Spec spec;
  _Fixture({required this.audioPath, required this.spec});
}

class _Spec {
  final int expectedSpeakers;
  final List<List<dynamic>>? groundTruthTimeline;
  final double? thresholdOverride;
  final int? numSpeakersOverride;
  /// When non-empty, the harness runs the fixture once per threshold value
  /// in this list (in addition to the base config). Lets one test invocation
  /// sweep multiple thresholds without re-installing the APK.
  final List<double> thresholdSweep;

  _Spec({
    required this.expectedSpeakers,
    this.groundTruthTimeline,
    this.thresholdOverride,
    this.numSpeakersOverride,
    this.thresholdSweep = const [],
  });

  factory _Spec.fromJson(Map<String, dynamic> json) {
    return _Spec(
      expectedSpeakers: (json['expected_speakers'] as num).toInt(),
      groundTruthTimeline: (json['ground_truth_timeline'] as List?)
          ?.map((e) => List<dynamic>.from(e as List))
          .toList(),
      thresholdOverride: (json['threshold_override'] as num?)?.toDouble(),
      numSpeakersOverride: (json['num_speakers_override'] as num?)?.toInt(),
      thresholdSweep: (json['threshold_sweep'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
    );
  }
}
