import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../kernel/kernel.dart';
import '../kernel/audio/transcription_engine.dart';

import '../screens/dashboard_screen.dart';
import '../screens/files_tab_screen.dart';
import '../screens/calendar_tab_screen.dart';
import '../screens/trash_screen.dart';
import '../screens/settings_screen.dart';


import '../app/app_lifecycle_bloc.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/onboarding/overview_screen.dart';
import '../screens/onboarding/download_screen.dart';
import '../screens/splash_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _recordNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'recordNav');
final _filesNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'filesNav');
final _trashNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'trashNav');
final _calendarNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'calendarNav');
final _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settingsNav');

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

      // Handle Splash state
      if (lifecycleState is AppLifecycleInitial) {
        if (state.matchedLocation != '/splash') return '/splash';
        return null;
      }

      final isGoingToSplash = state.matchedLocation == '/splash';
      final isGoingToOnboarding = state.matchedLocation.startsWith('/onboarding');
      final isGoingToDownload = state.matchedLocation == '/onboarding/download';

      if (lifecycleState is AppLifecycleReady) {
        if (!lifecycleState.isOnboarded) {
          if (!isGoingToOnboarding) return '/onboarding/welcome';
          return null;
        }

        // Post-onboarding: allow /onboarding/download (for model re-downloads)
        // but block all other onboarding routes and splash
        if (isGoingToOnboarding && !isGoingToDownload) return '/';
        if (isGoingToSplash) return '/';
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
      // ─── 4-tab bottom navigation (IndexedStack to preserve state) ────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _ShellLayout(navigationShell: navigationShell);
        },
        branches: [
          // 🎙 Record — the dashboard
          StatefulShellBranch(
            navigatorKey: _recordNavigatorKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // 📁 Files
          StatefulShellBranch(
            navigatorKey: _filesNavigatorKey,
            routes: [
              GoRoute(
                path: '/files',
                builder: (context, state) => const FilesTabScreen(),
              ),
            ],
          ),
          // 📅 Calendar
          StatefulShellBranch(
            navigatorKey: _calendarNavigatorKey,
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarTabScreen(),
              ),
            ],
          ),
          // 🗑 Trash
          StatefulShellBranch(
            navigatorKey: _trashNavigatorKey,
            routes: [
              GoRoute(
                path: '/trash',
                builder: (context, state) => const TrashScreen(),
              ),
            ],
          ),
          // ⚙️ Settings
          StatefulShellBranch(
            navigatorKey: _settingsNavigatorKey,
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

// ─── Shell layout with bottom navigation ──────────────────────────────────────

class _ShellLayout extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _ShellLayout({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: LocalInferenceService().isBusy,
        builder: (context, gemmaBusy, _) {
          return ValueListenableBuilder<Map<String, double>>(
            valueListenable: TranscriptionEngine().transcriptionProgress,
            builder: (context, progressMap, _) {
              final isTranscribing = progressMap.isNotEmpty;
              return NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: (index) {
                  navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  );
                },
                backgroundColor: const Color(0xFF0F111A),
                surfaceTintColor: Colors.transparent,
                indicatorColor: const Color(0xFF818CF8).withAlpha(30),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home, color: Color(0xFF818CF8)),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: _GlowIcon(
                      icon: Icons.folder_outlined,
                      isGlowing: gemmaBusy || isTranscribing,
                    ),
                    selectedIcon: _GlowIcon(
                      icon: Icons.folder,
                      isGlowing: gemmaBusy || isTranscribing,
                      isSelected: true,
                    ),
                    label: 'Files',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month, color: Color(0xFF818CF8)),
                    label: 'Calendar',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.delete_outline),
                    selectedIcon: Icon(Icons.delete, color: Color(0xFF818CF8)),
                    label: 'Trash',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings, color: Color(0xFF818CF8)),
                    label: 'Settings',
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Animated glow wrapper for a nav bar icon.
class _GlowIcon extends StatefulWidget {
  final IconData icon;
  final bool isGlowing;
  final bool isSelected;

  const _GlowIcon({
    required this.icon,
    required this.isGlowing,
    this.isSelected = false,
  });

  @override
  State<_GlowIcon> createState() => _GlowIconState();
}

class _GlowIconState extends State<_GlowIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isGlowing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _GlowIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isGlowing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isGlowing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isGlowing) {
      return Icon(
        widget.icon,
        color: widget.isSelected ? const Color(0xFF818CF8) : null,
      );
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF818CF8).withValues(alpha: _animation.value * 0.6),
                blurRadius: 8 + (_animation.value * 6),
                spreadRadius: _animation.value * 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Icon(
        widget.icon,
        color: widget.isSelected ? const Color(0xFF818CF8) : const Color(0xFF818CF8).withValues(alpha: 0.8),
      ),
    );
  }
}

// ─── Multi-stream listenable ──────────────────────────────────────────────────

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
