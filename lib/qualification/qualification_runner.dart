import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../kernel/qualification_channel.dart';
import '../kernel/device_support.dart';
import '../kernel/documents/document_extractor.dart';
import '../kernel/inference/local_inference_service.dart';
import '../kernel/inference/model_profile.dart';
import '../inference/model_manager.dart';

class QualificationRunner extends ChangeNotifier {
  final channel = QualificationChannel();
  final inference = LocalInferenceService();
  Map<String, dynamic> device = {};
  Map<String, dynamic> report = {};
  String stage = 'Reading hardware';
  bool busy = false, available = false, modelReady = false;
  bool _cancelled = false, _disposed = false;
  double progress = 0;
  String? backend;
  StreamIterator<dynamic>? _tokens;
  CancelToken? _downloadCancel;
  File? reportFile;
  final elapsed = Stopwatch();

  void update() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      device = await channel.snapshot();
      if (device['qualificationBuild'] != true) {
        throw StateError('Requires qualification flavor');
      }
      available = true;
      final directory =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      reportFile = File('${directory.path}/qualification/latest.json');
      if (await reportFile!.exists()) {
        report = Map<String, dynamic>.from(
          jsonDecode(await reportFile!.readAsString()) as Map,
        );
        if (report['status'] == 'running') {
          report['status'] = 'interrupted';
          report['note'] =
              'Previous process ended before completion; crash vs termination is not known.';
          await save();
        }
      }
      if (await DeviceSupport.isSupported()) {
        backend = ModelProfile.gpu ? 'GPU' : 'NPU';
        modelReady = await ModelManager().hasModel();
      }
      stage = 'Ready';
      final options = await channel.launchOptions();
      if (options['backend'] == 'GPU' || options['backend'] == 'NPU') {
        if (!await select(options['backend'] as String)) {
          report = {
            'schema': 1,
            'startedUtc': DateTime.now().toUtc().toIso8601String(),
            'mode': options['mode'],
            'status': 'failed',
            'error': stage,
            'aiQualification': 'not_tested',
            'requestedBackend': options['backend'],
          };
          await save();
          return;
        }
      }
      if (options['mode'] == 'compatibility') {
        await run(compatibilityOnly: true);
      } else if (options['mode'] == 'quick') {
        await run();
      } else if (options['mode'] == 'stress') {
        await run(stress: const Duration(minutes: 10));
      }
    } catch (e) {
      stage = '$e';
    }
    update();
  }

  Future<bool> select(String value) async {
    if (busy) return false;
    var success = false;
    busy = true;
    stage = 'Selecting $value';
    update();
    try {
      if (backend != null) await inference.unloadModel();
      await channel.select(value);
      ModelProfile.clearAfterUnload();
      if (!await DeviceSupport.isSupported()) {
        throw StateError('Candidate profile rejected');
      }
      backend = value;
      modelReady = await ModelManager().hasModel();
      device = await channel.snapshot();
      stage = 'Ready';
      success = true;
    } catch (e) {
      stage = '$e';
    } finally {
      busy = false;
      update();
    }
    return success;
  }

  Future<void> download() async {
    if (busy || backend == null) return;
    busy = true;
    _cancelled = false;
    progress = 0;
    stage = 'Downloading selected model; keep this app open';
    update();
    _downloadCancel = CancelToken();
    try {
      await channel.keepAwake(true);
      await ModelManager().downloadModel(
        ModelProfile.url,
        cancelToken: _downloadCancel,
        onProgress: (fraction, size) {
          progress = fraction.clamp(0, 1);
          stage = 'Downloading model · $size';
          update();
        },
      );
      modelReady = await ModelManager().hasModel();
      stage = 'Download complete; checksum checked during load';
    } catch (e) {
      stage = _cancelled ? 'Download cancelled' : '$e';
    } finally {
      try {
        await channel.keepAwake(false);
      } catch (_) {}
      _downloadCancel = null;
      busy = false;
      update();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    stage = 'Cancelling; waiting for native work to finish';
    update();
    _downloadCancel?.cancel();
    await _tokens?.cancel();
  }

  void checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<void> save() async {
    if (reportFile == null) return;
    await reportFile!.parent.create(recursive: true);
    final temporary = File('${reportFile!.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await temporary.rename(reportFile!.path);
  }

  Future<void> checkpoint(String name) async {
    stage = name;
    report['stage'] = name;
    update();
    await save();
    checkCancelled();
  }

  static bool correctFacts(String output) {
    final normalized = output.toLowerCase().replaceAll(',', '');
    return normalized.contains('42750') &&
        normalized.contains('maya') &&
        normalized.contains('october') &&
        normalized.contains('16') &&
        !normalized.contains('90000');
  }

  static const facts =
      'A proposed budget of 90000 dollars was rejected. '
      'The final approved budget is 42750 dollars. Maya owns the audit, due October 16. '
      'State only the approved budget, owner, and due date in one sentence.';

  Future<Map<String, dynamic>> generate(
    String prompt, {
    bool firstOnly = false,
  }) async {
    final timer = Stopwatch()..start();
    int? firstMs;
    final output = StringBuffer();
    final iterator = StreamIterator(
      inference.generateStream(prompt, maxTokens: 128),
    );
    _tokens = iterator;
    try {
      while (await iterator.moveNext().timeout(const Duration(seconds: 90))) {
        checkCancelled();
        final text = iterator.current.text;
        if (text.isNotEmpty) {
          firstMs ??= timer.elapsedMilliseconds;
          output.write(text);
        }
        if (firstOnly && output.isNotEmpty) break;
      }
    } finally {
      await iterator.cancel();
      _tokens = null;
    }
    checkCancelled();
    return {
      'output': output.toString(),
      'firstTextMs': firstMs,
      'totalMs': timer.elapsedMilliseconds,
      'characters': output.length,
      'charactersPerSecond': timer.elapsedMicroseconds == 0
          ? null
          : output.length * 1000000 / timer.elapsedMicroseconds,
      'native': (await channel.snapshot())['inference'],
    };
  }

  Future<void> documents() async {
    final temp = await (await getTemporaryDirectory()).createTemp(
      'qualification_',
    );
    try {
      const text =
          'Approved budget: 42750 dollars. Maya owns the audit. Deadline: October 16.';
      final pdf = pw.Document()..addPage(pw.Page(build: (_) => pw.Text(text)));
      final pdfFile = File('${temp.path}/fixture.pdf');
      await pdfFile.writeAsBytes(await pdf.save());
      final archive = Archive();
      final xml = utf8.encode(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:body></w:document>',
      );
      archive.addFile(ArchiveFile('word/document.xml', xml.length, xml));
      final docx = File('${temp.path}/fixture.docx');
      await docx.writeAsBytes(ZipEncoder().encode(archive));
      for (final file in [pdfFile, docx]) {
        checkCancelled();
        final result = await DocumentExtractor().extract(file.path);
        if (!correctFacts(result.text)) {
          throw StateError('Document extraction facts failed');
        }
      }
      report['documentExtraction'] = 'passed';
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<void> run({
    bool compatibilityOnly = false,
    Duration stress = Duration.zero,
  }) async {
    if (busy || !available) return;
    busy = true;
    _cancelled = false;
    progress = 0;
    elapsed.reset();
    elapsed.start();
    final samples = <Map<String, dynamic>>[];
    final runs = <Map<String, dynamic>>[];
    Timer? ticker;
    var sampling = false;
    var loadAttempted = false;
    report = {
      'schema': 1,
      'suite': 'hardware-qualification-v1',
      'startedUtc': DateTime.now().toUtc().toIso8601String(),
      'status': 'running',
      'mode': compatibilityOnly
          ? 'compatibility'
          : stress == Duration.zero
          ? 'quick'
          : 'stress',
      'stressSeconds': stress.inSeconds,
      'requestedBackend': backend,
      'samples': samples,
      'runs': runs,
      'certified': false,
      'notes': [
        'Synthetic content only',
        'PSS is sampled process memory, not total GPU allocation',
        'Temperature is battery temperature, not SoC temperature',
        'Characters/sec is not tokens/sec; native token metrics provided only when available',
        'Quick pass is not sustained-performance approval',
        'Compatibility mode covers document extraction and sandbox I/O, not all app flows',
      ],
    };
    try {
      device = await channel.snapshot();
      report['device'] = device;
      await channel.keepAwake(true);
      await checkpoint('Checking PDF and Word extraction');
      await documents();
      progress = 0.1;
      if (!compatibilityOnly) {
        if (device['emulator'] == true || backend == null) {
          throw StateError('No eligible physical accelerator profile');
        }
        if (!modelReady) {
          throw StateError('Download or stage the selected model first');
        }
        report['model'] = {
          'filename': ModelProfile.filename,
          'bytes': ModelProfile.bytes,
          'url': ModelProfile.url,
        };
        ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
          if (sampling) return;
          sampling = true;
          try {
            final snapshot = await channel.snapshot();
            if (busy) {
              samples.add({
                'elapsedMs': elapsed.elapsedMilliseconds,
                ...snapshot,
              });
            }
          } catch (_) {
            /* A failed sample must not invent a measurement. */
          } finally {
            sampling = false;
            update();
          }
        });
        await checkpoint('Loading and verifying model');
        final load = Stopwatch()..start();
        loadAttempted = true;
        await inference.loadModel();
        report['loadMs'] = load.elapsedMilliseconds;
        report['loadedBackend'] = (await channel.snapshot())['inference'];
        checkCancelled();
        progress = 0.3;
        await checkpoint('Checking summary facts');
        final summary = await generate(facts);
        runs.add({'test': 'facts', ...summary});
        if (!correctFacts(summary['output'] as String)) {
          throw StateError('Summary fact check failed');
        }
        progress = 0.5;
        await checkpoint('Checking cancellation and next request');
        await generate('Count from one to fifty.', firstOnly: true);
        final next = await generate(
          'What is 17 plus 25? Answer only the number.',
        );
        runs.add({'test': 'afterCancellation', ...next});
        if (!RegExp(r'\b42\b').hasMatch(next['output'] as String)) {
          throw StateError('Response after cancellation failed');
        }
        progress = 0.7;
        await checkpoint('Checking unload and reload');
        await inference.unloadModel();
        await inference.loadModel();
        checkCancelled();
        final reloaded = await generate(facts);
        runs.add({'test': 'afterReload', ...reloaded});
        if (!correctFacts(reloaded['output'] as String)) {
          throw StateError('Response after reload failed');
        }
        final stressClock = Stopwatch()..start();
        while (stressClock.elapsed < stress) {
          checkCancelled();
          progress =
              0.8 +
              0.19 * stressClock.elapsedMilliseconds / stress.inMilliseconds;
          await checkpoint(
            'Sustained inference · ${stressClock.elapsed.inSeconds}/${stress.inSeconds}s',
          );
          final item = await generate(facts);
          runs.add({'test': 'sustained', ...item});
          if (!correctFacts(item['output'] as String)) {
            throw StateError('Sustained summary fact check failed');
          }
          final thermal =
              (await channel.snapshot())['thermalStatus'] as int? ?? 0;
          if (thermal >= 3) {
            throw StateError('Stopped at severe thermal status ($thermal)');
          }
        }
      }
      report['status'] = 'passed';
      report['aiQualification'] = compatibilityOnly
          ? 'not_tested'
          : 'test_passed_not_certified';
      progress = 1;
      stage = compatibilityOnly
          ? 'Compatibility checks passed · AI not tested'
          : 'Test passed · not certified';
    } catch (e) {
      report['status'] = _cancelled ? 'cancelled' : 'failed';
      report['error'] = '$e';
      stage = _cancelled ? 'Cancelled' : 'Failed: $e';
    } finally {
      ticker?.cancel();
      if (loadAttempted) {
        try {
          await inference.unloadModel();
        } catch (e) {
          report['cleanupError'] = '$e';
          report['status'] = 'failed';
          stage = 'Native cleanup failed';
        }
      }
      elapsed.stop();
      try {
        await channel.keepAwake(false);
      } catch (_) {}
      report['elapsedMs'] = elapsed.elapsedMilliseconds;
      report['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
      try {
        await save();
      } catch (e) {
        stage = 'Report could not be saved: $e';
      }
      busy = false;
      update();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}

class _Cancelled {
  const _Cancelled();
  @override
  String toString() => 'Cancelled';
}
