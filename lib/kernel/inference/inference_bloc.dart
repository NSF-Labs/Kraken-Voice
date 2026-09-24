import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'local_inference_service.dart';

// --- Events ---
abstract class InferenceEvent extends Equatable {
  const InferenceEvent();
  @override
  List<Object?> get props => [];
}

class InferenceLoadRequested extends InferenceEvent {
  final String? modelPath;
  const InferenceLoadRequested({this.modelPath});
  @override
  List<Object?> get props => [modelPath];
}

class InferenceUnloadRequested extends InferenceEvent {}

class InferencePromptSubmitted extends InferenceEvent {
  final String prompt;
  const InferencePromptSubmitted(this.prompt);
  @override
  List<Object?> get props => [prompt];
}

// --- States ---
abstract class InferenceState extends Equatable {
  const InferenceState();
  @override
  List<Object?> get props => [];
}

class InferenceUninitialized extends InferenceState {}

class InferenceLoading extends InferenceState {}

class InferenceWarm extends InferenceState {
  final String? lastResponse;
  const InferenceWarm([this.lastResponse]);
  @override
  List<Object?> get props => [lastResponse];
}

class InferenceGenerating extends InferenceState {
  final String currentText;
  const InferenceGenerating(this.currentText);
  @override
  List<Object?> get props => [currentText];
}

class InferenceError extends InferenceState {
  final String message;
  const InferenceError(this.message);
  @override
  List<Object?> get props => [message];
}

// --- BLoC ---
class InferenceBloc extends Bloc<InferenceEvent, InferenceState> {
  final LocalInferenceService _service;

  InferenceBloc(this._service) : super(InferenceUninitialized()) {
    on<InferenceLoadRequested>(_onLoad);
    on<InferenceUnloadRequested>(_onUnload);
    on<InferencePromptSubmitted>(_onPrompt);
  }

  Future<void> _onLoad(
    InferenceLoadRequested event,
    Emitter<InferenceState> emit,
  ) async {
    emit(InferenceLoading());
    try {
      await _service.loadModel(modelPath: event.modelPath);
      emit(InferenceWarm());
    } catch (e) {
      emit(InferenceError(e.toString()));
      emit(InferenceUninitialized()); // fallback
    }
  }

  Future<void> _onUnload(
    InferenceUnloadRequested event,
    Emitter<InferenceState> emit,
  ) async {
    try {
      await _service.unloadModel();
      emit(InferenceUninitialized());
    } catch (e) {
      emit(InferenceError(e.toString()));
    }
  }

  Future<void> _onPrompt(
    InferencePromptSubmitted event,
    Emitter<InferenceState> emit,
  ) async {
    if (state is! InferenceWarm) return;

    emit(const InferenceGenerating(''));
    String buffer = '';

    await emit.forEach<InferenceToken>(
      _service.generateStream(event.prompt),
      onData: (token) {
        buffer += token.text;
        return InferenceGenerating(buffer);
      },
      onError: (error, stackTrace) => InferenceError(error.toString()),
    );

    // After generation is done, return to warm state
    if (state is InferenceGenerating) {
      emit(InferenceWarm((state as InferenceGenerating).currentText));
    }
  }
}
