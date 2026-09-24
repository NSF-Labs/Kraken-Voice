import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../kernel/kernel.dart';
import 'share_intent_handler.dart';
import '../kernel/audio/recording_recovery_service.dart';
import '../kernel/model_readiness_service.dart';
import '../kernel/model_storage_helper.dart';
import '../data/recording_repository.dart';
import '../router/app_router.dart';
import 'app_lifecycle_bloc.dart';

class KrakEnVoiceApp extends StatefulWidget {
  const KrakEnVoiceApp({super.key});

  @override
  State<KrakEnVoiceApp> createState() => _KrakEnVoiceAppState();
}

class _KrakEnVoiceAppState extends State<KrakEnVoiceApp> {
  late final GoRouter _router;
  final ShareIntentHandler _shareHandler = ShareIntentHandler();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    final authBloc = context.read<AuthBloc>();
    final vaultService = context.read<VaultService>();
    final kernelContext = context.read<KernelContext>();
    final appLifecycleBloc = context.read<AppLifecycleBloc>();
    _router = createRouter(
      authBloc,
      appLifecycleBloc,
      vaultService,
      kernelContext,
    );

    // Auto-unlock vault transparently on startup
    _autoUnlockVault(authBloc);
  }

  void _autoUnlockVault(AuthBloc authBloc) {
    // Listen for auth states that need automatic handling
    void handleState(AuthState state) {
      if (state is AuthSetupRequired) {
        // First launch — create vault silently (no biometrics)
        authBloc.add(const AuthPassphraseSubmitted(
          passphrase: 'kraken-auto-vault',
          enableBiometrics: false,
        ));
      } else if (state is AuthLocked) {
        // Always use passphrase — never trigger system biometric prompt
        authBloc.add(const AuthPassphraseSubmitted(
          passphrase: 'kraken-auto-vault',
          enableBiometrics: false,
        ));
      }
    }

    // Check current state immediately
    handleState(authBloc.state);

    // Also listen for future state changes (splash → auth flow)
    _authSubscription = authBloc.stream.listen(handleState);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _shareHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) => curr is AuthUnlocked,
      listener: (context, state) {
        // Initialize share handler once vault is unlocked
        _shareHandler.init(() => _router.routerDelegate.navigatorKey.currentContext);
        // Auto-clean expired trash items (>30 days)
        final vault = context.read<VaultService>();
        FolderRepository(vault).autoCleanTrash();
        // Recover orphaned recordings (crash recovery)
        RecordingRecoveryService(vault).recoverOrphanedRecordings();
        // Migrate models from old internal storage to external (survives reinstalls)
        ModelStorageHelper().migrateIfNeeded();
        // Refresh model readiness state for all screens
        ModelReadinessService().refresh();
      },
      child: MaterialApp.router(
        title: 'Krak-EN Voice',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        routerConfig: _router,
      ),
    );
  }
}
