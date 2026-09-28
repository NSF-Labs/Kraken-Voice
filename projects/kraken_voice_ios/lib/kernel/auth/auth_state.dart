import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthSetupRequired extends AuthState {}

class AuthLocked extends AuthState {
  final bool canUnlockWithBiometrics;

  const AuthLocked({this.canUnlockWithBiometrics = false});

  @override
  List<Object?> get props => [canUnlockWithBiometrics];
}

class AuthUnlocked extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}
