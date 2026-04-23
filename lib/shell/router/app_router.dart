import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../kernel/kernel.dart';
import '../../spokes/mock/mock_spoke.dart';
import '../../spokes/meeting_notes/meeting_notes_spoke.dart';
import '../ui/dashboard_screen.dart';
import '../ui/workspace_detail_screen.dart';
import '../ui/shell_layout.dart';
import '../ui/settings_screen.dart';
import '../ui/activity_screen.dart';
import 'spoke_context_impl.dart';

import '../home/unlock_screen.dart';
import '../app/app_lifecycle_bloc.dart';
import '../onboarding/welcome_screen.dart';
import '../onboarding/overview_screen.dart';
import '../onboarding/download_screen.dart';
import '../onboarding/secure_screen.dart';
import '../onboarding/demo_screen.dart';
import '../ui/splash_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _dashboardNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'dashboardNav',
);
final _activityNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'activityNav',
);

GoRouter createRouter(
  AuthBloc authBloc,
  AppLifecycleBloc appLifecycleBloc,
  VaultService vaultService,
  KernelContext kernelContext,
) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final lifecycleState = appLifecycleBloc.state;
      final authState = authBloc.state;

      // Handle Splash state
      if (lifecycleState is AppLifecycleInitial) {
        if (state.matchedLocation != '/splash') return '/splash';
        return null;
      }

      final isGoingToSplash = state.matchedLocation == '/splash';
      final isGoingToOnboarding = state.matchedLocation.startsWith(
        '/onboarding',
      );
      final isGoingToUnlock = state.matchedLocation == '/unlock';

      if (lifecycleState is AppLifecycleReady) {
        if (!lifecycleState.isOnboarded) {
          if (!isGoingToOnboarding) return '/onboarding/welcome';
          return null; // Let them navigate onboarding
        }

        // They are onboarded. Prevent onboarding access
        if (isGoingToOnboarding || isGoingToSplash) {
          if (authState is! AuthUnlocked) return '/unlock';
          return '/';
        }

        // Vault is locked
        if (authState is! AuthUnlocked) {
          if (!isGoingToUnlock) return '/unlock';
        } else {
          // Vault is unlocked
          if (isGoingToUnlock) return '/';
        }
      }

      return null;
    },
    refreshListenable: _MultiStreamListenable([
      authBloc.stream,
      appLifecycleBloc.stream,
    ]),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding/overview',
        builder: (context, state) => const OverviewScreen(),
      ),
      GoRoute(
        path: '/onboarding/download',
        builder: (context, state) => const DownloadScreen(),
      ),
      GoRoute(
        path: '/onboarding/secure',
        builder: (context, state) => const SecureScreen(),
      ),
      GoRoute(
        path: '/onboarding/demo',
        builder: (context, state) => const DemoScreen(),
      ),
      GoRoute(
        path: '/unlock',
        builder: (context, state) => const UnlockScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellLayout(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _dashboardNavigatorKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen(),
              ),
              GoRoute(
                path: '/workspace/:id',
                builder: (context, state) {
                  final workspaceId = state.pathParameters['id']!;
                  return WorkspaceDetailScreen(workspaceId: workspaceId);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _activityNavigatorKey,
            routes: [
              GoRoute(
                path: '/activity',
                builder: (context, state) => const ActivityScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/mock_spoke',
        builder: (context, state) {
          final mockSpoke = MockSpoke();
          final spokeContext = HubSpokeContext(
            spokeId: mockSpoke.spokeId,
            vault: vaultService,
            kernel: kernelContext,
          );
          return mockSpoke.buildUi(spokeContext);
        },
      ),
      GoRoute(
        path: '/meeting_notes',
        builder: (context, state) {
          final spoke = MeetingNotesSpoke();
          final spokeContext = HubSpokeContext(
            spokeId: spoke.spokeId,
            vault: vaultService,
            kernel: kernelContext,
          );
          return spoke.buildUi(spokeContext);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

class _MultiStreamListenable extends ChangeNotifier {
  _MultiStreamListenable(List<Stream<dynamic>> streams) {
    notifyListeners();
    for (final stream in streams) {
      _subscriptions.add(
        stream.asBroadcastStream().listen((dynamic _) => notifyListeners()),
      );
    }
  }

  final List<dynamic> _subscriptions = [];

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
