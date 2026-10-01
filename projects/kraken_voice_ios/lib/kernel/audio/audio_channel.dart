import 'microphone_level.dart';
import '../entitlements/creation_access.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AudioRecordingState { idle, recording, paused, transcribing }

class AudioEngine {
  final MethodChannel _channel = const MethodChannel('kraken.kernel/audio');
  final EventChannel _amplitudeEventChannel = const EventChannel(
    'kraken.kernel/audio/amplitude',
  );

  // Global State
  final ValueNotifier<AudioRecordingState> recordingState = ValueNotifier(
    AudioRecordingState.idle,
  );
  final ValueNotifier<Duration> recordingDuration = ValueNotifier(
    Duration.zero,
  );
  String? currentFilePath;
  Timer? _timer;
  Future<int> Function()? recordingLimitSeconds;
  Future<void> Function(String path, int durationMs)?
  onBackgroundRecordingStopped;
  Future<void> updateRecordingLimit(int seconds) =>
      _channel.invokeMethod<void>('setRecordingLimit', {'seconds': seconds});

  /// Callback invoked when the user taps Stop from the notification.
  /// The RecordingScreen should listen to this and trigger its own stop flow.
  VoidCallback? onNotificationStop;

  /// Callback invoked when the user taps Pause/Resume from the notification.
  VoidCallback? onNotificationPause;

  Stream<double>? _amplitudeStream;

  AudioEngine() {
    // Listen for notification-triggered actions from the native side
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onNotificationStop':
          _timer?.cancel();
          final path = currentFilePath;
          final duration =
              (call.arguments as Map?)?['durationMs'] as int? ??
              recordingDuration.value.inMilliseconds;
          recordingState.value = AudioRecordingState.idle;
          if (path != null)
            await onBackgroundRecordingStopped?.call(path, duration);
          currentFilePath = null;
          recordingDuration.value = Duration.zero;
          onNotificationStop?.call();
          break;
        case 'onNotificationPause':
          if (recordingState.value == AudioRecordingState.paused) {
            recordingState.value = AudioRecordingState.recording;
          } else if (recordingState.value == AudioRecordingState.recording) {
            recordingState.value = AudioRecordingState.paused;
          }
          onNotificationPause?.call();
          break;
      }
    });
  }

  /// Force-stop any orphaned native recording service and reset Dart state.
  /// Call once during app startup to clean up after crashes / hot-reloads.
  Future<void> cleanupStaleState() async {
    if (recordingState.value != AudioRecordingState.idle) {
      debugPrint(
        '[AudioEngine] Resetting stale state: ${recordingState.value}',
      );
      _timer?.cancel();
      _timer = null;
      recordingState.value = AudioRecordingState.idle;
      recordingDuration.value = Duration.zero;
      currentFilePath = null;
    }
    // Send a stop command to the native side in case the service is still
    // running from a previous session. This is idempotent — if the service
    // isn't running, the intent is simply ignored.
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (_) {
      // Service wasn't running — expected, ignore.
    }
  }

  /// Microphone power in dBFS on every platform (-160 = silence, 0 = full scale).
  Stream<double> get amplitudeStream {
    _amplitudeStream ??= _amplitudeEventChannel.receiveBroadcastStream().map(
      (event) => microphoneDecibels(
        (event as num).toDouble(), isDecibels: Platform.isIOS,
      ),
    );
    return _amplitudeStream!;
  }

  Future<String?> startRecording({bool detectSilence = false}) async {
    await CreationAccess.require();
    try {
      final path = await _channel.invokeMethod<String>('startRecording', {
        'detectSilence': detectSilence,
        'limitSeconds': await recordingLimitSeconds?.call() ?? 1200,
      });
      if (path != null) {
        currentFilePath = path;
        recordingState.value = AudioRecordingState.recording;
        recordingDuration.value = Duration.zero;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (recordingState.value == AudioRecordingState.recording) {
            recordingDuration.value = Duration(
              seconds: recordingDuration.value.inSeconds + 1,
            );
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
      if (Platform.isIOS && path != null) {
        recordingDuration.value = await getDuration(path);
      }
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
    } on PlatformException catch (_) {
      return Duration.zero;
    }
  }
}
