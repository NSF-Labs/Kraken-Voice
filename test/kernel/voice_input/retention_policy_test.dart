import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/kernel/voice_input/faster_whisper_voice_input.dart';

class MockAudioEngine implements AudioEngine {
  bool isRecording = false;
  int stopCalledCount = 0;
  bool shouldThrowOnTranscribe = false;

  @override
  Future<String?> startRecording({bool detectSilence = false}) async {
    isRecording = true;
    return 'mock_path.m4a';
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
}

void main() {
  group('Retention Policy Tests', () {
    late MockAudioEngine mockAudioEngine;
    late FasterWhisperVoiceInput voiceInput;

    setUp(() {
      mockAudioEngine = MockAudioEngine();
      voiceInput = FasterWhisperVoiceInput(mockAudioEngine);
    });

    test('Audio file deletion (via stopRecording) occurs after successful transcription', () async {
      await voiceInput.transcribeUtterance(maxDuration: const Duration(milliseconds: 10));
      expect(mockAudioEngine.stopCalledCount, 1);
      expect(mockAudioEngine.isRecording, false);
    });

    test('Audio file deletion (via stopRecording) occurs even if transcription throws', () async {
      mockAudioEngine.shouldThrowOnTranscribe = true;
      try {
        await voiceInput.transcribeUtterance(maxDuration: const Duration(milliseconds: 10));
        fail('Should have thrown an error');
      } catch (e) {
        expect(e, isA<VoiceInputError>());
      }
      expect(mockAudioEngine.stopCalledCount, 1);
      expect(mockAudioEngine.isRecording, false);
    });
  });
}
