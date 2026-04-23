import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';

import 'package:kraken_hub/kernel/vault/vault_service.dart';
import 'package:kraken_hub/kernel/audio/transcription_engine.dart';
import 'package:kraken_hub/kernel/retention/retention_service.dart';
import 'package:kraken_hub/kernel/auth/auth_event.dart';
import 'package:kraken_hub/kernel/auth/auth_state.dart';
import 'package:kraken_hub/kernel/auth/key_derivation.dart';
import 'package:kraken_hub/kernel/auth/secure_keystore.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final VaultService _vaultService;
  final SecureKeyStore _secureKeyStore;
  final LocalAuthentication _localAuth;
  final RetentionService? _retentionService;

  AuthBloc({
    required VaultService vaultService,
    required SecureKeyStore secureKeyStore,
    required LocalAuthentication localAuth,
    RetentionService? retentionService,
  }) : _vaultService = vaultService,
       _secureKeyStore = secureKeyStore,
       _localAuth = localAuth,
       _retentionService = retentionService,
       super(AuthInitial()) {
    on<AuthStarted>(_onAuthStarted);
    on<AuthPassphraseSubmitted>(_onAuthPassphraseSubmitted);
    on<AuthBiometricUnlockRequested>(_onAuthBiometricUnlockRequested);
    on<AuthLockRequested>(_onAuthLockRequested);
  }

  Future<void> _onAuthStarted(
    AuthStarted event,
    Emitter<AuthState> emit,
  ) async {
    try {
      if (!await _vaultService.vaultExists) {
        emit(AuthSetupRequired());
        return;
      }

      final cachedKey = await _secureKeyStore.getCachedDerivedKey();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      final canUnlockWithBiometrics =
          cachedKey != null && (canCheckBiometrics || isDeviceSupported);

      emit(AuthLocked(canUnlockWithBiometrics: canUnlockWithBiometrics));
    } catch (e) {
      emit(AuthError('Initialization error: $e'));
      emit(const AuthLocked(canUnlockWithBiometrics: false));
    }
  }

  Future<void> _onAuthPassphraseSubmitted(
    AuthPassphraseSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final deviceSecret = await _secureKeyStore.getOrCreateDeviceSecret();
      final derivedKey = KeyDerivation.deriveVaultKey(
        passphrase: event.passphrase,
        deviceSecret: deviceSecret,
      );

      await _vaultService.openVault(derivedKey);

      if (event.enableBiometrics) {
        await _secureKeyStore.cacheDerivedKey(derivedKey);
      }

      TranscriptionEngine().startWorker(_vaultService);
      // Fire retention sweep (non-blocking)
      _retentionService?.runSweep();
      emit(AuthUnlocked());
    } catch (e) {
      emit(AuthError('Failed to unlock vault. Incorrect passphrase?'));

      // Re-emit locked state
      final cachedKey = await _secureKeyStore.getCachedDerivedKey();
      final canBiometric = cachedKey != null;
      emit(AuthLocked(canUnlockWithBiometrics: canBiometric));
    }
  }

  Future<void> _onAuthBiometricUnlockRequested(
    AuthBiometricUnlockRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock Kraken Hub',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!didAuthenticate) {
        emit(const AuthError('Biometric authentication failed.'));
        emit(const AuthLocked(canUnlockWithBiometrics: true));
        return;
      }

      final derivedKey = await _secureKeyStore.getCachedDerivedKey();
      if (derivedKey == null) {
        emit(
          const AuthError('Biometric key expired or removed. Use passphrase.'),
        );
        emit(const AuthLocked(canUnlockWithBiometrics: false));
        return;
      }

      await _vaultService.openVault(derivedKey);
      TranscriptionEngine().startWorker(_vaultService);
      // Fire retention sweep (non-blocking)
      _retentionService?.runSweep();
      emit(AuthUnlocked());
    } catch (e) {
      emit(AuthError('Failed to unlock vault using biometrics.'));
      emit(const AuthLocked(canUnlockWithBiometrics: true));
    }
  }

  Future<void> _onAuthLockRequested(
    AuthLockRequested event,
    Emitter<AuthState> emit,
  ) async {
    TranscriptionEngine().stopWorker();
    await _vaultService.closeVault();

    final cachedKey = await _secureKeyStore.getCachedDerivedKey();
    final canBiometric = cachedKey != null;

    emit(AuthLocked(canUnlockWithBiometrics: canBiometric));
  }
}
