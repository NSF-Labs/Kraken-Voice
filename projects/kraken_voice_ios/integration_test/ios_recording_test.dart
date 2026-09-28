import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/kernel/audio/whisper_model_file.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/main.dart' as app;

// Recording UI contains continuous animations. Wait for route transitions
// without requiring the app to stop scheduling frames.
Future<void> renderTransitions(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Run on an unlocked iOS device and allow the microphone permission prompt.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const audio = MethodChannel('kraken.kernel/audio');

  testWidgets(
    'native capture persists playable audio across pause/resume',
    (tester) async {
      await app.main();
      // The welcome logo animates continuously, so settling never finishes.
      for (var attempt = 0; attempt < 120; attempt++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('Get Started').evaluate().isNotEmpty ||
            find.text('Settings').evaluate().isNotEmpty) break;
      }
      if (find.text('Get Started').evaluate().isNotEmpty) {
        await tester.tap(find.text('Get Started'));
        await renderTransitions(tester);
        await tester.tap(find.text('Next'));
        await renderTransitions(tester);
        expect(find.text('AI Models'), findsOneWidget);
        expect(await WhisperModelFile.isReady(), isTrue);
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await renderTransitions(tester);
      }
      for (var attempt = 0; attempt < 120; attempt++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('Settings').evaluate().isNotEmpty) break;
      }
      expect(find.text('Settings'), findsWidgets);
      await tester.tap(find.text('Settings').last);
      await renderTransitions(tester);
      await tester.ensureVisible(find.text('Manage AI Models'));
      await tester.tap(find.text('Manage AI Models'));
      await renderTransitions(tester);
      expect(find.text('AI Models'), findsOneWidget);
      expect(find.text('Installed · Ready for offline transcription'), findsOneWidget);
      await tester.pageBack();
      await renderTransitions(tester);
      expect(find.text('Manage AI Models'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Exercise the actual bundled model and AAC conversion, not a mock.
      final sample = await rootBundle.load('assets/qa/whisper_check.m4a');
      final sampleFile = File('${(await getTemporaryDirectory()).path}/simulator-whisper-check.m4a');
      await sampleFile.writeAsBytes(sample.buffer.asUint8List(sample.offsetInBytes, sample.lengthInBytes));
      try {
        final transcript = await TranscriptionEngine().transcribeFile(sampleFile.path);
        expect(transcript.toLowerCase(), contains('meeting'));
        expect(transcript.toLowerCase(), contains('tomorrow'));
      } finally {
        await TranscriptionEngine().releaseWhisper();
        await sampleFile.delete();
      }
      String? path;
      try {
        path = await audio.invokeMethod<String>('startRecording', {
          'limitSeconds': 10,
        });
        expect(path, isNotNull);
        await Future<void>.delayed(const Duration(seconds: 2));
        await audio.invokeMethod<void>('pauseRecording');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await audio.invokeMethod<void>('resumeRecording');
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(await audio.invokeMethod<String>('stopRecording'), path);
        final file = File(path!);
        expect(await file.exists(), isTrue);
        expect(await file.length(), greaterThan(1024));
        final milliseconds = await audio.invokeMethod<int>('getDuration', {
          'path': path,
        });
        expect(milliseconds, greaterThanOrEqualTo(2000));
        expect(milliseconds, lessThan(5000));
        expect(await audio.invokeMethod<String>('stopRecording'), isNull);
        final player = AudioPlayer();
        try {
          final duration = await player.setFilePath(path);
          expect(duration!.inMilliseconds, greaterThanOrEqualTo(2000));
          final playback = player.play();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(player.position.inMilliseconds, greaterThan(0));
          await player.stop();
          await playback;
        } finally {
          await player.dispose();
        }
      } finally {
        await audio.invokeMethod<void>('stopRecording');
        if (path != null && await File(path).exists())
          await File(path).delete();
      }
    },
    skip: !Platform.isIOS,
  );
}
