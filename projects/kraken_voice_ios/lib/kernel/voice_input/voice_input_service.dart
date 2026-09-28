abstract class VoiceInputService {
  /// Push-to-talk: capture one utterance, transcribe, return text.
  /// Audio is deleted immediately after transcription completes.
  /// Throws VoiceInputError on mic-permission-denied, hardware-failure,
  /// transcription-failure, or cancellation.
  Future<String> transcribeUtterance({Duration? maxDuration});

  /// Continuous capture with live partial transcriptions.
  /// Emits TranscriptionPartial events as the user speaks,
  /// TranscriptionFinal when silence is detected or stopLiveTranscription is called.
  /// Audio buffer is deleted as soon as final transcription is emitted.
  Stream<TranscriptionEvent> startLiveTranscription();

  /// Stop an in-flight live transcription. Emits a final event and closes the stream.
  Future<void> stopLiveTranscription();

  /// Stop an in-flight push-to-talk utterance capture early and transcribe what was recorded.
  Future<void> stopCapture();

  /// Cancel any in-flight capture or transcription. No event emitted.
  /// Audio buffer is deleted.
  Future<void> cancel();
}

sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

class TranscriptionPartial extends TranscriptionEvent {
  final String text;
  final double confidence;
  const TranscriptionPartial(this.text, this.confidence);
}

class TranscriptionFinal extends TranscriptionEvent {
  final String text;
  final Duration audioDuration;
  const TranscriptionFinal(this.text, this.audioDuration);
}

class TranscriptionErrorEvent extends TranscriptionEvent {
  final VoiceInputError error;
  const TranscriptionErrorEvent(this.error);
}

enum VoiceInputError {
  micPermissionDenied,
  micHardwareUnavailable,
  transcriptionFailed,
  cancelled,
  notImplemented,
}
