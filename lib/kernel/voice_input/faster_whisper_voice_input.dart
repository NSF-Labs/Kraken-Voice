import 'dart:async';
import 'dart:io';
import '../audio/audio_channel.dart';
import 'voice_input_service.dart';

class FasterWhisperVoiceInput implements VoiceInputService {
  final AudioEngine _audioEngine;
  bool _isRecording = false;

  FasterWhisperVoiceInput(this._audioEngine);

  bool isEnabled = true;

  @override
  Future<String> transcribeUtterance({Duration? maxDuration}) async {
    if (!isEnabled) throw VoiceInputError.notImplemented;

    String? audioPath;
    try {
      _isRecording = true;

      // The startRecording method will block until silence is detected (or maxDuration if we implement it, but native handles silence)
      audioPath = await _audioEngine.startRecording(detectSilence: true);
      _isRecording = false;

      if (audioPath == null) throw VoiceInputError.transcriptionFailed;

      final text = await _audioEngine.transcribe(audioPath);
      return text;
    } on Exception catch (_) {
      throw VoiceInputError.transcriptionFailed;
    } finally {
      _isRecording = false;
      _deleteTempFile(audioPath);
    }
  }

  void _deleteTempFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Ignored
    }
  }

  StreamController<TranscriptionEvent>? _liveStreamController;

  @override
  Stream<TranscriptionEvent> startLiveTranscription() {
    if (!isEnabled) {
      return Stream.value(
        const TranscriptionErrorEvent(VoiceInputError.notImplemented),
      );
    }

    _liveStreamController?.close();
    _liveStreamController = StreamController<TranscriptionEvent>();

    _isRecording = true;
    _audioEngine.startRecording().catchError((e) {
      _isRecording = false;
      _liveStreamController?.add(
        const TranscriptionErrorEvent(VoiceInputError.micHardwareUnavailable),
      );
      _liveStreamController?.close();
    });

    return _liveStreamController!.stream;
  }

  @override
  Future<void> stopLiveTranscription() async {
    if (_isRecording) {
      try {
        final path = await _audioEngine.stopRecording();
        _isRecording = false;

        if (path.isEmpty) {
          _liveStreamController?.add(
            const TranscriptionErrorEvent(VoiceInputError.transcriptionFailed),
          );
        } else {
          final text = await _audioEngine.transcribe(path);
          _liveStreamController?.add(TranscriptionFinal(text, Duration.zero));
          _deleteTempFile(path);
        }
      } catch (e) {
        _liveStreamController?.add(
          const TranscriptionErrorEvent(VoiceInputError.transcriptionFailed),
        );
      } finally {
        _liveStreamController?.close();
      }
    }
  }

  @override
  Future<void> stopCapture() async {
    if (_isRecording) {
      await _audioEngine.stopRecording();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      if (_isRecording) {
        final path = await _audioEngine.stopRecording();
        _isRecording = false;
        _deleteTempFile(path);
      }
    } catch (_) {
    } finally {
      _liveStreamController?.close();
    }
  }
}
