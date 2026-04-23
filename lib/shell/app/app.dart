import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../kernel/kernel.dart';
import '../../kernel/audio/share_intent_handler.dart';
import '../router/app_router.dart';
import 'app_lifecycle_bloc.dart';

class KrakenHubApp extends StatefulWidget {
  const KrakenHubApp({super.key});

  @override
  State<KrakenHubApp> createState() => _KrakenHubAppState();
}

class _KrakenHubAppState extends State<KrakenHubApp> {
  late final GoRouter _router;
  final ShareIntentHandler _shareHandler = ShareIntentHandler();

  @override
  void initState() {
    super.initState();
    // Initialize the router once, grabbing dependencies from context
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
  }

  @override
  void dispose() {
    _shareHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) => curr is AuthUnlocked,
      listener: (context, state) {
        // Initialize share handler once vault is unlocked
        _shareHandler.init(context);
      },
      child: MaterialApp.router(
        title: 'Kraken Secure Hub',
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
