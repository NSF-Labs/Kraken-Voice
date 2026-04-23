import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../kernel/kernel.dart';
import '../../kernel/audio/transcription_engine.dart';
import '../design/tokens.dart';
import 'library_picker_sheet.dart';

class ShellLayout extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellLayout({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthLocked || state is AuthSetupRequired) {
          context.go('/unlock');
        }
      },
      child: Scaffold(
        backgroundColor: KrakenColors.bg,
        extendBody: true,
        body: Stack(
          children: [
            navigationShell,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActiveRecordingBanner(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _KrakenBottomNav(
          selectedIndex: navigationShell.currentIndex == 0 ? 0 : 2,
          onTap: (index) {
            if (index == 1) {
              LibraryPickerSheet.show(context);
            } else if (index == 3) {
              context.push('/settings');
            } else {
              final branchIndex = index == 0 ? 0 : 1;
              navigationShell.goBranch(
                branchIndex,
                initialLocation: branchIndex == navigationShell.currentIndex,
              );
            }
          },
        ),
      ),
    );
  }
}

class _KrakenBottomNav extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;

  const _KrakenBottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 60 + bottomPadding,
          decoration: const BoxDecoration(
            color: Color(0xD90A0A0C),
            border: Border(top: BorderSide(color: KrakenColors.border)),
          ),
          padding: EdgeInsets.only(top: 8, bottom: bottomPadding),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.grid_view_rounded,
                label: 'Home',
                active: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.folder_copy_outlined,
                label: 'Library',
                active: false,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.format_list_bulleted,
                label: 'Activity',
                active: selectedIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                active: false,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? KrakenColors.textPrimary : KrakenColors.textMuted;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: KrakenText.label(
                color: color,
              ).copyWith(fontSize: 10.5, letterSpacing: 0.1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveRecordingBanner extends StatelessWidget {
  const _ActiveRecordingBanner();

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final audioEngine = RepositoryProvider.of<AudioEngine>(context);
    
    return ValueListenableBuilder<AudioRecordingState>(
      valueListenable: audioEngine.recordingState,
      builder: (context, state, child) {
        if (state != AudioRecordingState.recording && state != AudioRecordingState.paused) {
          return const SizedBox.shrink();
        }

        // Do not show banner if we are already on the meeting notes page
        final location = GoRouterState.of(context).matchedLocation;
        if (location == '/meeting_notes') {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<Duration>(
          valueListenable: audioEngine.recordingDuration,
          builder: (context, duration, child) {
            return GestureDetector(
              onTap: () {
                context.go('/meeting_notes');
              },
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  color: Colors.red.withOpacity(0.9),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mic, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Recording — ${_formatDuration(duration)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ActiveTranscriptionBanner extends StatelessWidget {
  const _ActiveTranscriptionBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<TranscriptionJob>>(
      valueListenable: TranscriptionEngine().activeJobs,
      builder: (context, jobs, child) {
        final processingJobs = jobs.where((j) => j.status == TranscriptionStatus.processing).toList();
        final pendingJobs = jobs.where((j) => j.status == TranscriptionStatus.pending).toList();

        if (processingJobs.isEmpty && pendingJobs.isEmpty) {
          return const SizedBox.shrink();
        }

        final totalActive = processingJobs.length + pendingJobs.length;
        final statusText = processingJobs.isNotEmpty 
            ? 'Transcribing...' 
            : 'Queued ($totalActive)';

        return SafeArea(
          bottom: false,
          child: Container(
            width: double.infinity,
            color: KrakenColors.accent.withValues(alpha: 0.9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (processingJobs.isNotEmpty)
                  const LinearProgressIndicator(
                    value: null, // Indeterminate
                    backgroundColor: Colors.black26,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 3,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
