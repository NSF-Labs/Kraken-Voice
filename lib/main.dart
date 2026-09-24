import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/kernel/voice_input/faster_whisper_voice_input.dart';
import 'package:krak_en_voice/kernel/notifications/kraken_notification_service.dart';
import 'package:krak_en_voice/app/app.dart';
import 'package:krak_en_voice/app/app_lifecycle_bloc.dart';
import 'package:krak_en_voice/data/export_service.dart';

import 'package:krak_en_voice/kernel/audio/audio_device_service.dart';
import 'package:krak_en_voice/kernel/device_support.dart';
import 'package:krak_en_voice/app/unsupported_device_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!await DeviceSupport.isSupported()) {
    runApp(const UnsupportedDeviceApp());
    return;
  }

  // Clean up stale export temp files from previous session
  KrakenExportService.cleanupTempExports();

  final secureKeyStore = FlutterSecureKeyStore();
  final vaultService = VaultService();
  final localAuth = LocalAuthentication();
  final inferenceService = LocalInferenceService();
  final audioEngine = AudioEngine();
  final voiceInputService = FasterWhisperVoiceInput(audioEngine);
  final entitlementService = EntitlementServiceImpl();
  final kernelContext = KernelContext(
    audio: audioEngine,
    inference: inferenceService,
    vault: vaultService,
    export: ExportService(),
    search: SearchIndex(),
    voiceInput: voiceInputService,
    entitlement: entitlementService,
    audit: AuditLog(),
  );
  final preferencesService = PreferencesService();
  final retentionService = RetentionService(vaultService);

  // Initialize system notifications
  await KrakenNotificationService().initialize();

  // Kill any orphaned recording service from a previous session
  await audioEngine.cleanupStaleState();

  // Initialize audio device enumeration (mic selection)
  await AudioDeviceService().initialize();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: secureKeyStore),
        RepositoryProvider.value(value: vaultService),
        RepositoryProvider.value(value: localAuth),
        RepositoryProvider.value(value: inferenceService),
        RepositoryProvider.value(value: audioEngine),
        RepositoryProvider.value(value: kernelContext),
        RepositoryProvider.value(value: preferencesService),
        RepositoryProvider.value(value: retentionService),
        RepositoryProvider<EntitlementService>.value(value: entitlementService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(
              secureKeyStore: secureKeyStore,
              vaultService: vaultService,
              localAuth: localAuth,
              retentionService: retentionService,
            )..add(AuthStarted()),
          ),
          BlocProvider(create: (context) => InferenceBloc(inferenceService)),
          BlocProvider(create: (context) => VoiceInputBloc(voiceInputService)),
          BlocProvider(
            create: (context) =>
                AppLifecycleBloc(preferencesService)
                  ..add(AppLifecycleStarted()),
          ),
        ],
        child: const KrakEnVoiceApp(),
      ),
    ),
  );
}
