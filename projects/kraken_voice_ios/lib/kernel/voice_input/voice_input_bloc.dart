import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'voice_input_service.dart';

abstract class VoiceInputEvent {}

class VoiceInputStartCapture extends VoiceInputEvent {
  final bool isLive;
  VoiceInputStartCapture({this.isLive = false});
}

class VoiceInputStopCapture extends VoiceInputEvent {}

class VoiceInputCancel extends VoiceInputEvent {}

class _VoiceInputPartialReceived extends VoiceInputEvent {
  final String text;
  final double confidence;
  _VoiceInputPartialReceived(this.text, this.confidence);
}

class _VoiceInputFinalReceived extends VoiceInputEvent {
  final String text;
  final Duration duration;
  _VoiceInputFinalReceived(this.text, this.duration);
}

class _VoiceInputErrorReceived extends VoiceInputEvent {
  final VoiceInputError error;
  _VoiceInputErrorReceived(this.error);
}

abstract class VoiceInputState {
  const VoiceInputState();
}

class VoiceInputIdle extends VoiceInputState {
  const VoiceInputIdle();
}

class VoiceInputListening extends VoiceInputState {
  const VoiceInputListening();
}

class VoiceInputTranscribing extends VoiceInputState {
  final String partialText;
  const VoiceInputTranscribing([this.partialText = '']);
}

class VoiceInputErrorState extends VoiceInputState {
  final VoiceInputError error;
  const VoiceInputErrorState(this.error);
}

class VoiceInputSuccess extends VoiceInputState {
  final String text;
  const VoiceInputSuccess(this.text);
}

class VoiceInputBloc extends Bloc<VoiceInputEvent, VoiceInputState> {
  final VoiceInputService _service;
  StreamSubscription<TranscriptionEvent>? _liveSubscription;

  VoiceInputBloc(this._service) : super(const VoiceInputIdle()) {
    on<VoiceInputStartCapture>(_onStartCapture);
    on<VoiceInputStopCapture>(_onStopCapture);
    on<VoiceInputCancel>(_onCancel);
    on<_VoiceInputPartialReceived>(
      (event, emit) => emit(VoiceInputTranscribing(event.text)),
    );
    on<_VoiceInputFinalReceived>(
      (event, emit) => emit(VoiceInputSuccess(event.text)),
    );
    on<_VoiceInputErrorReceived>(
      (event, emit) => emit(VoiceInputErrorState(event.error)),
    );
  }

  Future<void> _onStartCapture(
    VoiceInputStartCapture event,
    Emitter<VoiceInputState> emit,
  ) async {
    emit(const VoiceInputListening());
    if (event.isLive) {
      _liveSubscription?.cancel();
      _liveSubscription = _service.startLiveTranscription().listen((event) {
        if (event is TranscriptionPartial) {
          add(_VoiceInputPartialReceived(event.text, event.confidence));
        } else if (event is TranscriptionFinal) {
          add(_VoiceInputFinalReceived(event.text, event.audioDuration));
        } else if (event is TranscriptionErrorEvent) {
          add(_VoiceInputErrorReceived(event.error));
        }
      });
    } else {
      try {
        final text = await _service.transcribeUtterance();
        emit(VoiceInputSuccess(text));
      } catch (e) {
        if (e is VoiceInputError) {
          emit(VoiceInputErrorState(e));
        } else {
          emit(const VoiceInputErrorState(VoiceInputError.transcriptionFailed));
        }
      }
    }
  }

  Future<void> _onStopCapture(
    VoiceInputStopCapture event,
    Emitter<VoiceInputState> emit,
  ) async {
    emit(const VoiceInputTranscribing());
    await _service.stopLiveTranscription();
    await _service.stopCapture();
  }

  Future<void> _onCancel(
    VoiceInputCancel event,
    Emitter<VoiceInputState> emit,
  ) async {
    await _liveSubscription?.cancel();
    _liveSubscription = null;
    await _service.cancel();
    emit(const VoiceInputIdle());
  }

  @override
  Future<void> close() {
    _liveSubscription?.cancel();
    return super.close();
  }
}
