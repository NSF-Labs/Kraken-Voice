import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../spoke_contract.dart';

// --- Events ---
abstract class SpokeRegistryEvent extends Equatable {
  const SpokeRegistryEvent();
  @override
  List<Object> get props => [];
}

class RegisterSpoke extends SpokeRegistryEvent {
  final SpokeModule spoke;
  const RegisterSpoke(this.spoke);
  @override
  List<Object> get props => [spoke.spokeId];
}

class DeregisterSpoke extends SpokeRegistryEvent {
  final String spokeId;
  const DeregisterSpoke(this.spokeId);
  @override
  List<Object> get props => [spokeId];
}

// --- State ---
class SpokeRegistryState extends Equatable {
  final List<SpokeModule> activeSpokes;

  const SpokeRegistryState({this.activeSpokes = const []});

  SpokeRegistryState copyWith({List<SpokeModule>? activeSpokes}) {
    return SpokeRegistryState(activeSpokes: activeSpokes ?? this.activeSpokes);
  }

  @override
  List<Object> get props => [activeSpokes];
}

// --- BLoC ---
class SpokeRegistryBloc extends Bloc<SpokeRegistryEvent, SpokeRegistryState> {
  SpokeRegistryBloc() : super(const SpokeRegistryState()) {
    on<RegisterSpoke>((event, emit) {
      if (!state.activeSpokes.any((s) => s.spokeId == event.spoke.spokeId)) {
        emit(
          state.copyWith(
            activeSpokes: List.from(state.activeSpokes)..add(event.spoke),
          ),
        );
      }
    });

    on<DeregisterSpoke>((event, emit) {
      emit(
        state.copyWith(
          activeSpokes: state.activeSpokes
              .where((s) => s.spokeId != event.spokeId)
              .toList(),
        ),
      );
    });
  }
}
