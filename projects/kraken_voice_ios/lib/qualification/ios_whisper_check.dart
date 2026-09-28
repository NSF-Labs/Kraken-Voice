import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../app/ios_whisper_download.dart';
import '../kernel/audio/transcription_engine.dart';

/// Device-only qualification entry point. Uses generated speech, not user audio.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Checking Whisper download…');
  runApp(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: Center(
    child: Padding(padding: const EdgeInsets.all(24), child: ValueListenableBuilder(
      valueListenable: status, builder: (_, value, _) => Text(value, textAlign: TextAlign.center),
    )),
  ))));
  final report = File('${(await getApplicationDocumentsDirectory()).path}/ios_whisper_check.json');
  final result = <String, dynamic>{'passed': false};
  try {
    final download = IOSWhisperDownload.instance;
    download.addListener(() { status.value = download.verifying
      ? 'Verifying Whisper model…'
      : 'Testing Whisper download: ${(download.progress * 100).round()}%'; });
    await download.check();
    await download.download();
    if (!download.ready) throw StateError(download.error ?? 'Model missing');
    result['downloadVerified'] = true;
    status.value = 'Transcribing a generated test sentence on this iPhone…';
    final sample = await rootBundle.load('assets/qa/whisper_check.m4a');
    final file = File('${(await getTemporaryDirectory()).path}/ios_whisper_check.m4a');
    await file.writeAsBytes(sample.buffer.asUint8List(sample.offsetInBytes, sample.lengthInBytes));
    final clock = Stopwatch()..start();
    final engine = TranscriptionEngine();
    final text = await engine.transcribeFile(file.path);
    result['transcript'] = text;
    result['elapsedMs'] = clock.elapsedMilliseconds;
    result['passed'] = text.toLowerCase().contains('meeting') && text.toLowerCase().contains('tomorrow');
    await engine.releaseWhisper();
    await file.delete();
    status.value = 'Whisper check ${result['passed'] == true ? 'passed' : 'failed'}\n\n$text';
  } catch (e, stack) {
    result['error'] = e.toString();
    result['stack'] = stack.toString();
    status.value = 'Whisper check failed: $e';
  }
  await report.writeAsString(const JsonEncoder.withIndent('  ').convert(result), flush: true);
}
