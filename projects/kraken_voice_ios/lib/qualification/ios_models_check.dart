import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../kernel/audio/whisper_model_file.dart';
import '../kernel/audio/transcription_engine.dart';
import '../kernel/inference/local_inference_service.dart';

/// Uses generated speech and a synthetic meeting note; never reads user data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Installing bundled Whisper…');
  runApp(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: Center(child:
    ValueListenableBuilder(valueListenable: status, builder: (_, text, _) =>
      Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center))),
  ))));
  final report = File('${(await getApplicationDocumentsDirectory()).path}/ios_models_check.json');
  final result = <String, dynamic>{'complete': false, 'version': '0.1.4+5'};
  Future<void> save() async { await report.writeAsString(jsonEncode(result), flush: true); }
  const native = MethodChannel('kraken.kernel/inference');
  try {
    await WhisperModelFile.installBundled();
    result['whisperInstalled'] = await WhisperModelFile.isReady();
    status.value = 'Testing bundled Whisper transcription…';
    final sample = await rootBundle.load('assets/qa/whisper_check.m4a');
    final audio = File('${(await getTemporaryDirectory()).path}/kraken-qa.m4a');
    await audio.writeAsBytes(sample.buffer.asUint8List(sample.offsetInBytes, sample.lengthInBytes));
    final engine = TranscriptionEngine();
    final text = await engine.transcribeFile(audio.path);
    result['transcript'] = text;
    result['whisperPassed'] = text.toLowerCase().contains('meeting') && text.toLowerCase().contains('tomorrow');
    await engine.releaseWhisper();
    await audio.delete();
    var model = await native.invokeMapMethod<String, dynamic>('modelStatus');
    result['gemmaSupported'] = model?['supported'];
    if (model?['supported'] != true) {
      result['gemmaReason'] = model?['reason'];
    } else {
      await native.invokeMethod<void>('downloadModel');
      do {
        await Future<void>.delayed(const Duration(seconds: 2));
        model = await native.invokeMapMethod<String, dynamic>('modelStatus');
        result['gemmaStatus'] = model;
        status.value = 'Installing Gemma: ${(((model?['progress'] as num?) ?? 0) * 100).round()}%\nKeep this app open.';
        await save();
      } while (model?['downloading'] == true);
      if (model?['ready'] != true) throw StateError(model?['error']?.toString() ?? 'Gemma not ready');
      status.value = 'Testing Gemma on this device…';
      final inference = LocalInferenceService();
      await inference.loadModel();
      const prompt = 'Summarize this meeting note in one short sentence: Alex will send the budget to Morgan on Friday.';
      result['gemmaInputTokens'] = await inference.countTokens(prompt);
      final output = StringBuffer();
      await for (final token in inference.generateStream(prompt, maxTokens: 128)) {
        output.write(token.text);
      }
      result['gemmaOutput'] = output.toString();
      result['gemmaPassed'] = output.toString().toLowerCase().contains('budget') && output.toString().toLowerCase().contains('friday');
      await inference.unloadModel();
    }
    result['complete'] = true;
    status.value = 'Model checks complete.\n${jsonEncode(result)}';
  } catch (error, stack) {
    result['error'] = error.toString();
    result['stack'] = stack.toString();
    status.value = 'Model check failed: $error';
  }
  await save();
}
