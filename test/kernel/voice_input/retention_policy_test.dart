import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/kernel/voice_input/faster_whisper_voice_input.dart';

class MockAudioEngine implements AudioEngine {
  String audioPath = '';
  bool isRecording = false;
  int stopCalledCount = 0;
  bool shouldThrowOnTranscribe = false;

  @override
  Future<String?> startRecording({bool detectSilence = false}) async {
    // Silence detection returns only after native capture has stopped.
    isRecording = !detectSilence;
    return audioPath;
  }

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  @override
  Stream<double> get amplitudeStream => const Stream.empty();

  @override
  Future<String> stopRecording() async {
    isRecording = false;
    stopCalledCount++;
    return 'mock_path.wav';
  }

  @override
  Future<String> transcribe(String audioFilePath) async {
    if (shouldThrowOnTranscribe) {
      throw Exception('Mock transcription error');
    }
    return 'Mock transcribed text';
  }

  @override
  final ValueNotifier<AudioRecordingState> recordingState = ValueNotifier(AudioRecordingState.idle);

  @override
  final ValueNotifier<Duration> recordingDuration = ValueNotifier(Duration.zero);

  @override
  String? currentFilePath;

  @override
  Future<Duration> getDuration(String audioPath) async => Duration.zero;

  @override
  Future<void> cleanupStaleState() async {}

  @override
  VoidCallback? onNotificationStop;

  @override
  VoidCallback? onNotificationPause;
}

void main() {
  group('Retention Policy Tests', () {
    late MockAudioEngine mockAudioEngine;
    late FasterWhisperVoiceInput voiceInput;
    late Directory tempDir;
    late File audio;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('voice_retention_');
      audio = await File('${tempDir.path}/utterance.m4a').writeAsBytes([1, 2, 3]);
      mockAudioEngine = MockAudioEngine();
      mockAudioEngine.audioPath = audio.path;
      voiceInput = FasterWhisperVoiceInput(
        mockAudioEngine,
        transcribeFile: mockAudioEngine.transcribe,
      );
    });

    tearDown(() async => tempDir.delete(recursive: true));

    test('Temporary utterance audio is deleted after successful transcription', () async {
      final text = await voiceInput.transcribeUtterance(maxDuration: const Duration(milliseconds: 10));
      expect(text, 'Mock transcribed text');
      expect(await audio.exists(), false);
      expect(mockAudioEngine.stopCalledCount, 0);
      expect(mockAudioEngine.isRecording, false);
    });

    test('Temporary utterance audio is deleted when transcription throws', () async {
      mockAudioEngine.shouldThrowOnTranscribe = true;
      try {
        await voiceInput.transcribeUtterance(maxDuration: const Duration(milliseconds: 10));
        fail('Should have thrown an error');
      } catch (e) {
        expect(e, isA<VoiceInputError>());
      }
      expect(await audio.exists(), false);
      expect(mockAudioEngine.stopCalledCount, 0);
      expect(mockAudioEngine.isRecording, false);
    });
  });
}
