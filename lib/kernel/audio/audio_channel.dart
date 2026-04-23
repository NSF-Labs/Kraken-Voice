import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AudioRecordingState { idle, recording, paused, transcribing }

class AudioEngine {
  final MethodChannel _channel = const MethodChannel('kraken.kernel/audio');
  final EventChannel _amplitudeEventChannel = const EventChannel('kraken.kernel/audio/amplitude');

  // Global State
  final ValueNotifier<AudioRecordingState> recordingState = ValueNotifier(AudioRecordingState.idle);
  final ValueNotifier<Duration> recordingDuration = ValueNotifier(Duration.zero);
  String? currentFilePath;
  Timer? _timer;

  Stream<double>? _amplitudeStream;

  Stream<double> get amplitudeStream {
    _amplitudeStream ??= _amplitudeEventChannel
        .receiveBroadcastStream()
        .map((event) => (event as num).toDouble());
    return _amplitudeStream!;
  }

  Future<String?> startRecording({bool detectSilence = false}) async {
    try {
      final path = await _channel.invokeMethod<String>('startRecording', {
        'detectSilence': detectSilence,
      });
      if (path != null) {
        currentFilePath = path;
        recordingState.value = AudioRecordingState.recording;
        recordingDuration.value = Duration.zero;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (recordingState.value == AudioRecordingState.recording) {
            recordingDuration.value = Duration(seconds: recordingDuration.value.inSeconds + 1);
          }
        });
      }
      return path;
    } on PlatformException catch (e) {
      throw Exception('Failed to start recording: ${e.message}');
    }
  }

  Future<void> pauseRecording() async {
    try {
      await _channel.invokeMethod('pauseRecording');
      recordingState.value = AudioRecordingState.paused;
    } on PlatformException catch (e) {
      throw Exception('Failed to pause recording: ${e.message}');
    }
  }

  Future<void> resumeRecording() async {
    try {
      await _channel.invokeMethod('resumeRecording');
      recordingState.value = AudioRecordingState.recording;
    } on PlatformException catch (e) {
      throw Exception('Failed to resume recording: ${e.message}');
    }
  }

  Future<String> stopRecording() async {
    _timer?.cancel();
    _timer = null;
    recordingState.value = AudioRecordingState.transcribing;
    try {
      final path = await _channel.invokeMethod<String>('stopRecording');
      return path ?? '';
    } on PlatformException catch (e) {
      throw Exception('Failed to stop recording: ${e.message}');
    }
  }

  Future<String> transcribe(String audioPath) async {
    try {
      final result = await _channel.invokeMethod<String>('transcribe', {
        'path': audioPath,
      });
      recordingState.value = AudioRecordingState.idle;
      currentFilePath = null;
      recordingDuration.value = Duration.zero;
      return result ?? '';
    } on PlatformException catch (e) {
      recordingState.value = AudioRecordingState.idle;
      throw Exception('Failed to transcribe: ${e.message}');
    }
  }

  Future<Duration> getDuration(String audioPath) async {
    try {
      final durationMs = await _channel.invokeMethod<int>('getDuration', {
        'path': audioPath,
      });
      return Duration(milliseconds: durationMs ?? 0);
    } on PlatformException catch (e) {
      return Duration.zero;
    }
  }
}
