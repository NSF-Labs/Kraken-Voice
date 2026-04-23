import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/kernel/voice_input/faster_whisper_voice_input.dart';
import 'package:kraken_hub/kernel/notifications/kraken_notification_service.dart';
import 'package:kraken_hub/shell/app/app.dart';
import 'package:kraken_hub/shell/app/app_lifecycle_bloc.dart';
import 'package:kraken_hub/spokes/mock/mock_spoke.dart';
import 'package:kraken_hub/spokes/meeting_notes/meeting_notes_spoke.dart';
import 'package:kraken_hub/spokes/meeting_notes/data/kraken_export_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean up stale export temp files from previous session
  KrakenExportService.cleanupTempExports();

  final secureKeyStore = FlutterSecureKeyStore();
  final vaultService = VaultService();
  final workspaceService = WorkspaceService(vaultService);
  final localAuth = LocalAuthentication();
  final inferenceService = LocalInferenceService();
  final audioEngine = AudioEngine();
  final voiceInputService = FasterWhisperVoiceInput(audioEngine);
  final entitlementService = EntitlementServiceImpl();
  final kernelContext = KernelContext(
    audio: audioEngine,
    inference: inferenceService,
    vault: vaultService,
    workspace: workspaceService,
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

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: secureKeyStore),
        RepositoryProvider.value(value: vaultService),
        RepositoryProvider.value(value: workspaceService),
        RepositoryProvider.value(value: localAuth),
        RepositoryProvider.value(value: inferenceService),
        RepositoryProvider.value(value: audioEngine),
        RepositoryProvider.value(value: kernelContext),
        RepositoryProvider.value(value: preferencesService),
        RepositoryProvider.value(value: retentionService),
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
          BlocProvider(
            create: (context) {
              final bloc = SpokeRegistryBloc();
              if (kDebugMode) {
                bloc.add(RegisterSpoke(MeetingNotesSpoke()));
              }
              return bloc;
            },
          ),
          BlocProvider(create: (context) => InferenceBloc(inferenceService)),
          BlocProvider(create: (context) => VoiceInputBloc(voiceInputService)),
          BlocProvider(
            create: (context) =>
                AppLifecycleBloc(preferencesService)
                  ..add(AppLifecycleStarted()),
          ),
        ],
        child: const KrakenHubApp(),
      ),
    ),
  );
}
