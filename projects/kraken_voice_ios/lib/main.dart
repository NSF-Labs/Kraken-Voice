import 'dart:io';
import 'kernel/audio/whisper_model_file.dart';
import 'kernel/model_readiness_service.dart';
import 'data/recording_repository.dart';
import 'kernel/audio/transcription_engine.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    try {
      await WhisperModelFile.installBundled();
    } catch (error) {
      // Keep recording available; AI Models offers a verified download retry.
      debugPrint('[Models] Bundled Whisper setup failed: $error');
    }
  }

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
  audioEngine.recordingLimitSeconds = () async {
    await entitlementService.ready;
    return entitlementService.isUnlocked('com.kraken.meeting_notes') ? 0 : 1200;
  };
  entitlementService.changes.listen((_) {
    audioEngine.updateRecordingLimit(
      entitlementService.isUnlocked('com.kraken.meeting_notes') ? 0 : 1200,
    );
  });
  audioEngine.onBackgroundRecordingStopped = (path, durationMs) async {
    if (!vaultService.isOpen)
      return; // Breadcrumb recovery runs on next unlock.
    final rows = await vaultService.db.query(
      'recordings',
      where: 'audio_path = ?',
      whereArgs: [path],
    );
    if (rows.isEmpty) {
      await FolderRepository(vaultService).createRecording(
        title:
            'Recording ${DateTime.now().toLocal().toString().substring(0, 16)}',
        audioPath: path,
        durationMs: durationMs,
      );
    }
    final breadcrumb = File('$path.recording');
    if (await breadcrumb.exists()) await breadcrumb.delete();
    if ((!Platform.isIOS || ModelReadinessService().canTranscribe) && await PreferencesService().getString(
          'transcription_preference',
          defaultValue: 'ask',
        ) ==
        'auto') {
      await TranscriptionEngine().queueJobWithDefaultLanguage(
        vaultService,
        path,
      );
    }
  };
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
  final retentionService = RetentionService(
    vaultService,
    isUnlimited: () async {
      await entitlementService.ready;
      return entitlementService.isUnlocked('com.kraken.meeting_notes');
    },
  );

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
