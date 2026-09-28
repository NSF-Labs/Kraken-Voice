import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../data/summary_prompt.dart';
import '../kernel/inference/local_inference_service.dart';

/// Synthetic source only. Measures a 3 GB target; does not emulate an OS limit.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Measuring summary memory…');
  runApp(MaterialApp(home: Scaffold(body: Center(child: ValueListenableBuilder(
    valueListenable: status,
    builder: (_, text, _) => Text(text, textAlign: TextAlign.center),
  )))));
  const native = MethodChannel('kraken.kernel/inference');
  final file = File('${(await getApplicationDocumentsDirectory()).path}/ios_summary_memory_check.json');
  final report = <String, dynamic>{'complete': false, 'targetBytes': 3000000000, 'enforcedLimit': false};
  final samples = <Map<String, dynamic>>[];
  final cases = <Map<String, dynamic>>[];
  report['samples'] = samples;
  report['cases'] = cases;
  var stage = 'startup';
  var sampling = false;
  Future<void> sample() async {
    if (sampling) return;
    sampling = true;
    try {
      final memory = await native.invokeMapMethod<String, dynamic>('memoryStatus');
      samples.add({'stage': stage, ...?memory});
      await file.writeAsString(jsonEncode(report), flush: true);
    } finally { sampling = false; }
  }
  Timer? timer;
  final inference = LocalInferenceService();
  try {
    await sample();
    report['model'] = await native.invokeMapMethod<String, dynamic>('modelStatus');
    if ((report['model'] as Map)['supported'] != true) {
      report['skipped'] = 'Gemma is disabled on this device by the production RAM requirement.';
    } else {
      stage = 'load';
      await sample();
      timer = Timer.periodic(const Duration(seconds: 1), (_) { unawaited(sample()); });
      await inference.loadModel();
      for (final count in [1, 20, 60]) {
        stage = 'summary-$count';
        status.value = 'Testing synthetic summary ($count notes)…';
        final source = List.generate(count, (i) => 'Agenda item ${i + 1}: Alex will send the budget to Morgan on Friday. The team approved a 500 dollar budget.').join('\n');
        final prompt = SummaryPrompt.initial(source);
        final test = <String, dynamic>{'notes': count, 'inputTokens': await inference.countTokens(prompt)};
        cases.add(test);
        await sample();
        final output = StringBuffer();
        final watch = Stopwatch()..start();
        await for (final token in inference.generateStream(prompt, maxTokens: 512)) {
          output.write(token.text);
        }
        test['elapsedMs'] = watch.elapsedMilliseconds;
        test['output'] = output.toString();
        test['passed'] = output.toString().toLowerCase().contains('budget') && output.toString().toLowerCase().contains('friday');
        await sample();
      }
      stage = 'unload';
      await inference.unloadModel();
      await sample();
    }
    report['complete'] = true;
  } catch (error, stack) {
    report['error'] = error.toString();
    report['stack'] = stack.toString();
  } finally {
    timer?.cancel();
    while (sampling) { await Future<void>.delayed(const Duration(milliseconds: 20)); }
    report['sampledPeakFootprintBytes'] = samples.fold<int>(0, (peak, s) => (s['processFootprintBytes'] as int? ?? 0) > peak ? s['processFootprintBytes'] as int : peak);
    await file.writeAsString(jsonEncode(report), flush: true);
    status.value = report['complete'] == true ? 'Memory check complete.' : 'Memory check failed: ${report['error']}';
  }
}
