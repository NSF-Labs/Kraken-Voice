import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {}

class AuthPassphraseSubmitted extends AuthEvent {
  final String passphrase;
  final bool enableBiometrics;

  const AuthPassphraseSubmitted({
    required this.passphrase,
    this.enableBiometrics = false,
  });

  @override
  List<Object?> get props => [passphrase, enableBiometrics];
}

class AuthBiometricUnlockRequested extends AuthEvent {}

class AuthLockRequested extends AuthEvent {}
