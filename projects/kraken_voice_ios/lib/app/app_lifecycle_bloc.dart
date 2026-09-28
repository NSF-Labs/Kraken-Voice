import 'package:flutter_bloc/flutter_bloc.dart';
import '../kernel/kernel.dart';

// Events
abstract class AppLifecycleEvent {}

class AppLifecycleStarted extends AppLifecycleEvent {}

class AppLifecycleOnboardingCompleted extends AppLifecycleEvent {}

// States
abstract class AppLifecycleState {}

class AppLifecycleInitial extends AppLifecycleState {}

class AppLifecycleReady extends AppLifecycleState {
  final bool isOnboarded;
  AppLifecycleReady({required this.isOnboarded});
}

// Bloc
class AppLifecycleBloc extends Bloc<AppLifecycleEvent, AppLifecycleState> {
  final PreferencesService _preferencesService;

  AppLifecycleBloc(this._preferencesService) : super(AppLifecycleInitial()) {
    on<AppLifecycleStarted>(_onStarted);
    on<AppLifecycleOnboardingCompleted>(_onOnboardingCompleted);
  }

  Future<void> _onStarted(
    AppLifecycleStarted event,
    Emitter<AppLifecycleState> emit,
  ) async {
    // Run the onboarding check and a 2-second splash delay concurrently.
    // This ensures the branded splash screen is visible for at least 2 seconds.
    final results = await Future.wait([
      _preferencesService.getIsOnboarded(),
      Future.delayed(const Duration(seconds: 3), () => true),
    ]);
    final isOnboarded = results[0];
    emit(AppLifecycleReady(isOnboarded: isOnboarded));
  }

  Future<void> _onOnboardingCompleted(
    AppLifecycleOnboardingCompleted event,
    Emitter<AppLifecycleState> emit,
  ) async {
    await _preferencesService.setOnboarded();
    emit(AppLifecycleReady(isOnboarded: true));
  }
}
