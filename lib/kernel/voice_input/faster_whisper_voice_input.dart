import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../audio/audio_channel.dart';
import '../audio/transcription_engine.dart';
import 'voice_input_service.dart';

class FasterWhisperVoiceInput implements VoiceInputService {
  final AudioEngine _audioEngine;
  bool _isRecording = false;

  final Future<String> Function(String) _transcribeFile;

  FasterWhisperVoiceInput(
    this._audioEngine, {
    Future<String> Function(String)? transcribeFile,
  }) : _transcribeFile = transcribeFile ?? TranscriptionEngine().transcribeFile;

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

      // Use the real Whisper engine via TranscriptionEngine instead of the
      // native channel stub. This is the same engine used by Meeting Notes.
      final text = await _transcribeFile(audioPath);
      if (text == 'Transcription failed.') {
        throw VoiceInputError.transcriptionFailed;
      }
      return text;
    } on VoiceInputError {
      rethrow;
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
      return null;
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
          // Use the real Whisper engine via TranscriptionEngine
          debugPrint('[VoiceInput] Transcribing live capture: $path');
          final text = await _transcribeFile(path);
          if (text == 'Transcription failed.') {
            _liveStreamController?.add(
              const TranscriptionErrorEvent(VoiceInputError.transcriptionFailed),
            );
          } else {
            _liveStreamController?.add(TranscriptionFinal(text, Duration.zero));
          }
          _deleteTempFile(path);
        }
      } catch (e) {
        debugPrint('[VoiceInput] Transcription error: $e');
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
