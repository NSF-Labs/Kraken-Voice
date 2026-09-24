// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../kernel/kernel.dart';
import '../app/permission_helper.dart';
import '../kernel/audio/transcription_engine.dart';
import '../kernel/model_readiness_service.dart';
import '../kernel/audio/audio_device_service.dart';
import '../design/tokens.dart';
import '../data/recording_repository.dart';
import '../data/whisper_languages.dart';
import '../widgets/amplitude_visualizer.dart';
import '../widgets/ai_chat_bar.dart';
import '../widgets/upgrade_modal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  bool _hasWhisperModel = false;
  String _selectedLanguage = 'en';
  double _micSensitivity = 1.0;

  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  StreamSubscription<double>? _amplitudeSubscription;
  double _currentAmplitude = 0.0;
  double _smoothedAmplitude = 0.0;
  final List<double> _waveformLevels = List.filled(160, 0.0, growable: true);
  VoidCallback? _whisperReadyListener;

  late bool _isFreeTier;

  @override
  void initState() {
    super.initState();

    // Breathe animation — 1.4s per brief
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _breatheAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    final entitlements = RepositoryProvider.of<EntitlementService>(context, listen: false);
    _isFreeTier = !entitlements.isUnlocked('com.kraken.meeting_notes');

    _checkModelStatus();
    _loadLanguagePreference();
    _loadMicSensitivity();
    _setupAmplitudeListener();
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _amplitudeSubscription?.cancel();
    // Clean up whisper readiness listener
    if (_whisperReadyListener != null) {
      ModelReadinessService().whisperReady.removeListener(_whisperReadyListener!);
    }
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    audioEngine.recordingDuration.removeListener(_onDurationChanged);
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    // Use the centralized service — it refreshes on vault unlock,
    // but we also listen for changes reactively
    final readiness = ModelReadinessService();

    // If the initial value is false, it may just be stale from before
    // vault unlock. Await a fresh check so we don't flash a false banner.
    if (!readiness.whisperReady.value) {
      await readiness.refresh();
    }

    _whisperReadyListener?.call; // remove previous if any
    void onWhisperChanged() {
      if (mounted) setState(() => _hasWhisperModel = readiness.whisperReady.value);
    }
    _whisperReadyListener = onWhisperChanged;
    readiness.whisperReady.addListener(onWhisperChanged);
    _hasWhisperModel = readiness.whisperReady.value;
    if (mounted) setState(() {});
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = RepositoryProvider.of<PreferencesService>(context, listen: false);
    final lang = await prefs.getString('default_language', defaultValue: 'en');
    if (mounted) setState(() => _selectedLanguage = lang);
  }

  Future<void> _loadMicSensitivity() async {
    final prefs = RepositoryProvider.of<PreferencesService>(context, listen: false);
    final val = await prefs.getMicSensitivity();
    if (mounted) setState(() => _micSensitivity = val);
  }

  void _setupAmplitudeListener() {
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    audioEngine.recordingDuration.addListener(_onDurationChanged);

    _amplitudeSubscription = audioEngine.amplitudeStream.listen((amplitude) {
      if (!mounted) return;
      setState(() {
        // dBFS calibration
        double dbfs = -60.0;
        if (amplitude > 0) {
          dbfs = 20.0 * (log(amplitude / 32767.0) / ln10);
        }
        final scaled = (((dbfs + 30.0) / 27.0) * _micSensitivity).clamp(0.0, 1.0);

        // Asymmetric smoothing
        final alpha = scaled > _smoothedAmplitude ? 0.55 : 0.28;
        _smoothedAmplitude = (_smoothedAmplitude * (1.0 - alpha)) + (scaled * alpha);
        _currentAmplitude = _smoothedAmplitude;

        _waveformLevels.removeAt(0);
        _waveformLevels.add(
          audioEngine.recordingState.value == AudioRecordingState.recording
              ? _smoothedAmplitude
              : 0.0,
        );
      });
    });
  }

  void _onDurationChanged() {
    if (!mounted) return;
    setState(() {});
    _checkLimits();
  }

  // ─── Recording controls ───────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final hasPermission = await PermissionHelper.ensureMicrophonePermission(context);
    if (!hasPermission) return;

    _upgradeShown = false; // Reset for this recording session

    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    try {
      final path = await audioEngine.startRecording();
      // Write a breadcrumb so crash recovery knows a recording was in progress
      if (path != null) {
        try {
          final breadcrumb = File('$path.recording');
          await breadcrumb.writeAsString(DateTime.now().toIso8601String());
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording({String? limitMsg}) async {
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    try {
      final path = await audioEngine.stopRecording();
      final durationMs = audioEngine.recordingDuration.value.inMilliseconds;

      if (limitMsg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(limitMsg)),
        );
      }

      final vault = RepositoryProvider.of<VaultService>(context, listen: false);
      if (!vault.isOpen) {
        // Vault hasn't finished opening — wait briefly then retry
        await Future.delayed(const Duration(milliseconds: 500));
        if (!vault.isOpen) {
          audioEngine.recordingState.value = AudioRecordingState.idle;
          audioEngine.recordingDuration.value = Duration.zero;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recording stopped. Vault is still initializing — file saved locally.')),
            );
          }
          return;
        }
      }
      final folderRepo = FolderRepository(vault);

      // Generate title from timestamp
      final now = DateTime.now();
      final title = 'Recording ${now.month}/${now.day} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      // Create Recording entry in vault (critical — this was previously missing)
      await folderRepo.createRecording(
        title: title,
        audioPath: path,
        durationMs: durationMs > 0 ? durationMs : 1000,
      );

      // Clean up breadcrumb file — recording is now safely persisted
      try {
        final breadcrumb = File('$path.recording');
        if (await breadcrumb.exists()) await breadcrumb.delete();
      } catch (_) {}

      // Reset engine state
      audioEngine.recordingState.value = AudioRecordingState.idle;
      audioEngine.recordingDuration.value = Duration.zero;

      // Reset waveform visualizer to flat
      setState(() {
        _currentAmplitude = 0.0;
        _smoothedAmplitude = 0.0;
        _waveformLevels.fillRange(0, _waveformLevels.length, 0.0);
      });

      // Check transcription preference
      final prefs = RepositoryProvider.of<PreferencesService>(context, listen: false);
      final txPref = await prefs.getString('transcription_preference', defaultValue: 'ask');

      if (txPref == 'auto') {
        // Queue immediately
        final engine = TranscriptionEngine();
        await engine.queueJobWithDefaultLanguage(vault, path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved and queued for transcription.')),
          );
        }
      } else if (txPref == 'ask' && mounted) {
        final shouldTranscribe = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: KrakenColors.surfaceElevated,
            title: Text('Transcribe now?', style: KrakenText.displayMd()),
            content: Text(
              'Would you like to transcribe this recording now?',
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Later', style: KrakenText.bodySm(color: KrakenColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KrakenColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Transcribe'),
              ),
            ],
          ),
        );
        if (shouldTranscribe == true) {
          final engine = TranscriptionEngine();
          await engine.queueJobWithDefaultLanguage(vault, path);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Queued for transcription.')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved. You can transcribe it later.')),
          );
        }
      } else {
        // Manual — just save
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop: $e')),
        );
      }
    }
  }

  Future<void> _pauseResume() async {
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    if (audioEngine.recordingState.value == AudioRecordingState.paused) {
      await audioEngine.resumeRecording();
    } else {
      await audioEngine.pauseRecording();
    }
  }

  bool _upgradeShown = false;

  void _checkLimits() {
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    if (audioEngine.recordingState.value != AudioRecordingState.recording) return;
    final secs = audioEngine.recordingDuration.value.inSeconds;

    // 5-hour safety cap
    if (secs >= 5 * 3600) {
      _stopRecording(limitMsg: 'Recording stopped at the 5-hour safety limit. Your audio has been preserved.');
      return;
    }
    if (secs == 4 * 3600 + 59 * 60) {
      _showLimitModal('Recording will stop in 1 minute at the 5-hour safety limit.');
    }

    // Free-tier 20-min limit
    if (!_isFreeTier) return;
    if (secs >= 20 * 60) {
      _stopRecording();
      // Show upgrade paywall after auto-stop
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showUpgradeModal(reachedLimit: true);
      });
    } else if (secs == 19 * 60 + 45 && !_upgradeShown) {
      _upgradeShown = true;
      _showUpgradeModal();
    }
  }

  void _showLimitModal(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Safety Limit', style: KrakenText.displayMd()),
        content: Text(message, style: KrakenText.bodyMd()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showUpgradeModal({bool reachedLimit = false}) {
    showUpgradeModal(
      context,
      reachedLimit: reachedLimit,
      onPurchaseStateChanged: () {
        if (mounted) {
          setState(() {
            final entitlements = RepositoryProvider.of<EntitlementService>(context, listen: false);
            _isFreeTier = !entitlements.isUnlocked('com.kraken.meeting_notes');
          });
        }
      },
    );
  }

  // ─── Time formatting ──────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    }
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    // The parent Shell Scaffold consumes viewInsets via resizeToAvoidBottomInset,
    // so MediaQuery.of(context).viewInsets.bottom is always 0 inside the body.
    // Use the raw platform insets to detect the keyboard reliably.
    final rawBottomInset = View.of(context).viewInsets.bottom / View.of(context).devicePixelRatio;
    final isKeyboardOpen = rawBottomInset > 50;

    return Container(
      color: KrakenColors.bg,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // ─── Background Kraken (50% idle → 100% recording, pulse w/ audio) ──
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 340,
                    height: 340,
                    child: ValueListenableBuilder<AudioRecordingState>(
                      valueListenable: audioEngine.recordingState,
                      builder: (context, recState, child) {
                        final isRecording = recState == AudioRecordingState.recording;
                        final isPaused = recState == AudioRecordingState.paused;

                        if (isRecording) {
                          // Pulse with audio amplitude: base 0.55 → peak 1.0
                          return AnimatedBuilder(
                            animation: _breatheAnimation,
                            builder: (context, child) {
                              final opacity = (0.55 + _currentAmplitude * 0.45)
                                  .clamp(0.55, 1.0);
                              return Opacity(
                                opacity: opacity,
                                child: child,
                              );
                            },
                            child: child,
                          );
                        }

                        if (isPaused) {
                          // Paused: subtle breathe at 40%
                          return AnimatedBuilder(
                            animation: _breatheAnimation,
                            builder: (context, _) {
                              return Opacity(
                                opacity: 0.35 + (_breatheAnimation.value * 0.10),
                                child: child,
                              );
                            },
                          );
                        }

                        // Idle: 50% brightness
                        return Opacity(
                          opacity: 0.50,
                          child: child,
                        );
                      },
                      child: Image.asset(
                        'assets/images/electric_kraken.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ─── Foreground content column ────────────────────────────
            Column(
              children: [
                // ─── Scrollable main content ──────────────────────────
                Expanded(
                  child: ValueListenableBuilder<AudioRecordingState>(
                    valueListenable: audioEngine.recordingState,
                    builder: (context, recState, _) {
                      final isIdle = recState == AudioRecordingState.idle;
                      final isRecording = recState == AudioRecordingState.recording;
                      final isPaused = recState == AudioRecordingState.paused;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),

                            // ─── App bar ──────────────────────────────────
                            _buildAppBar(),

                            // ─── Model status banner ──────────────────────
                            if (!_hasWhisperModel) ...[
                              const SizedBox(height: 12),
                              _buildModelBanner(),
                            ],

                            const SizedBox(height: 16),

                            // ─── Hero record button + flanking controls ────
                            _buildRecordButtonRow(isIdle, isRecording, isPaused),

                            // ─── Timer (just below mic) ────────────────────
                            const SizedBox(height: 12),
                            ValueListenableBuilder<Duration>(
                              valueListenable: RepositoryProvider.of<AudioEngine>(
                                      context, listen: false)
                                  .recordingDuration,
                              builder: (context, elapsed, _) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildTimer(elapsed, isIdle, isRecording),
                                    // Free-tier countdown pill (invisible for paid users)
                                    const SizedBox(height: 8),
                                    _buildFreeCountdown(elapsed, isIdle, isRecording),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

            // ─── Visualizer (pinned, hidden when keyboard is open) ──
            if (!isKeyboardOpen)
              ValueListenableBuilder<AudioRecordingState>(
                valueListenable: RepositoryProvider.of<AudioEngine>(context, listen: false).recordingState,
                builder: (context, recState, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),

                      // ─── Amplitude visualizer ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: AmplitudeVisualizer(levels: _waveformLevels),
                      ),

                      const SizedBox(height: 4),
                    ],
                  );
                },
              ),

            // ─── Language + mic row (hidden when keyboard is open) ──────
            if (!isKeyboardOpen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: _buildLanguageMicRow(),
              ),

            // ─── AI Chat Bar (pinned at bottom, above bottom nav) ──────
            const AiChatBar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── App bar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Row(
      children: [
        Text(
          'Krak-EN Voice',
          style: KrakenText.displayMd(),
        ),
        const Spacer(),
      ],
    );
  }

  // ─── Model banner ────────────────────────────────────────────────────────

  Widget _buildModelBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Transcription model missing. Recording will work, but transcription is deferred.',
              style: KrakenText.bodySm(color: Colors.orange),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              context.push('/onboarding/download');
            },
            child: Text('Set up', style: KrakenText.bodySm(color: KrakenColors.accent)),
          ),
        ],
      ),
    );
  }

  // ─── Record button row (pause | mic | stop) ────────────────────────────────

  Widget _buildRecordButtonRow(bool isIdle, bool isRecording, bool isPaused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ─── Left: Pause/Resume ─────────────────────────────────────
        AnimatedOpacity(
          opacity: isIdle ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: isIdle,
            child: _buildFlankButton(
              icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: isPaused ? 'Resume' : 'Pause',
              color: KrakenColors.accent,
              onTap: _pauseResume,
            ),
          ),
        ),

        const SizedBox(width: 20),

        // ─── Center: Mic / Stop ─────────────────────────────────────
        _buildMicButton(isIdle, isRecording, isPaused),

        const SizedBox(width: 20),

        // ─── Right: Stop ────────────────────────────────────────────
        AnimatedOpacity(
          opacity: isIdle ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: isIdle,
            child: _buildFlankButton(
              icon: Icons.stop_rounded,
              label: 'Stop',
              color: KrakenColors.danger,
              onTap: _stopRecording,
            ),
          ),
        ),
      ],
    );
  }

  /// Compact circular button for pause/stop that flanks the mic.
  Widget _buildFlankButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(20),
              border: Border.all(color: color.withAlpha(80), width: 1.5),
            ),
            child: Center(
              child: Icon(icon, color: color, size: 26),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: KrakenText.caption(color: color),
          ),
        ],
      ),
    );
  }

  /// The center mic button — tap to start or stop recording.
  Widget _buildMicButton(bool isIdle, bool isRecording, bool isPaused) {
    return AnimatedBuilder(
      animation: _breatheAnimation,
      builder: (context, child) {
        double glowIntensity;
        double scale;
        Color glowColor;

        if (isRecording) {
          glowIntensity = 0.3 + (_currentAmplitude * 0.7);
          scale = 1.0 + (_currentAmplitude * 0.08);
          glowColor = Colors.red;
        } else if (isPaused) {
          glowIntensity = 0.4;
          scale = 1.0;
          glowColor = Colors.orange;
        } else {
          glowIntensity = 0.12;
          scale = 1.0;
          glowColor = KrakenColors.accent;
        }

        return GestureDetector(
          onTap: () {
            if (isIdle) {
              _startRecording();
            } else {
              _stopRecording();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withAlpha((glowIntensity * 255).toInt()),
                        blurRadius: 28 + (glowIntensity * 20),
                        spreadRadius: glowIntensity * 10,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          glowColor.withAlpha(40),
                          glowColor.withAlpha(15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                      border: Border.all(
                        color: glowColor.withAlpha((glowIntensity * 180).toInt()),
                        width: 2.0,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KrakenColors.surface.withAlpha(200),
                          border: Border.all(
                            color: glowColor.withAlpha((glowIntensity * 120).toInt()),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isIdle
                                ? const Icon(Icons.mic, color: Colors.red, size: 31, key: ValueKey('mic'))
                                : const Icon(Icons.mic, color: Colors.red, size: 31, key: ValueKey('mic-active')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // "Press to Record" label when idle
              if (isIdle) ...[
                const SizedBox(height: 12),
                Text(
                  'Press to Record',
                  style: KrakenText.bodySm(color: KrakenColors.textMuted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ─── Timer ────────────────────────────────────────────────────────────────

  Widget _buildTimer(Duration elapsed, bool isIdle, bool isRecording) {
    final display = isIdle ? '00:00' : _formatDuration(elapsed);

    return Text(
      display,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 36,
        fontWeight: FontWeight.w300,
        color: Colors.white,
        letterSpacing: 2,
      ),
    );
  }

  // ─── Free-tier countdown (separate from main timer) ───────────────────────

  Widget _buildFreeCountdown(Duration elapsed, bool isIdle, bool isRecording) {
    if (!_isFreeTier) return const SizedBox.shrink();
    if (isIdle) return const SizedBox.shrink();

    const freeLimit = Duration(minutes: 20);
    final remaining = freeLimit - elapsed;
    final clamped = remaining.isNegative ? Duration.zero : remaining;
    final totalSecs = clamped.inSeconds;
    final display = _formatDuration(clamped);

    // Color urgency: white → amber at 2 min → red at 30 sec
    Color color;
    if (totalSecs <= 30) {
      color = Colors.redAccent;
    } else if (totalSecs <= 120) {
      color = Colors.amberAccent;
    } else {
      color = Colors.white70;
    }

    return GestureDetector(
      onTap: () => _showUpgradeModal(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              '$display remaining',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.lock_open, size: 12, color: color),
          ],
        ),
      ),
    );
  }



  // ─── Language + microphone row ─────────────────────────────────────────────

  Widget _buildLanguageMicRow() {
    return Row(
      children: [
        // Language pill
        Expanded(
          child: _buildPill(
            icon: Icons.language,
            label: whisperLanguageLabel(_selectedLanguage),
            onTap: _showLanguagePicker,
          ),
        ),
        const SizedBox(width: 12),
        // Microphone pill — opens device picker + sensitivity
        Expanded(
          child: ValueListenableBuilder<List<AudioInputDevice>>(
            valueListenable: AudioDeviceService().devices,
            builder: (context, deviceList, child) {
              return _buildPill(
                icon: Icons.mic_external_on,
                label: AudioDeviceService().selectedDeviceLabel,
                onTap: _showMicrophoneSheet,
              );
            },
          ),
        ),
      ],
    );
  }

  void _showMicrophoneSheet() {
    final service = AudioDeviceService();
    double tempSensitivity = _micSensitivity;

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final deviceList = service.devices.value;
          final currentId = service.selectedDeviceId.value;

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.65,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).viewPadding.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Microphone Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: KrakenColors.textPrimary,
                        )),
                    const SizedBox(height: 16),

                    // ─── Device Selection ────────────────────────
                    Text('Input Device',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: KrakenColors.textSecondary,
                        )),
                    const SizedBox(height: 8),

                    // System Default
                    _buildMicOption(
                      icon: Icons.settings_suggest,
                      label: 'System Default',
                      subtitle: 'Let the OS choose',
                      isSelected: currentId == null,
                      onTap: () async {
                        await service.selectDevice(null);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),

                    // Listed devices
                    ...deviceList.map((device) {
                      final isSelected = currentId == device.id;
                      return _buildMicOption(
                        icon: _deviceTypeIcon(device.type),
                        label: device.name,
                        subtitle: _deviceTypeLabel(device.type),
                        isSelected: isSelected,
                        onTap: () async {
                          await service.selectDevice(device.id);
                          setSheetState(() {});
                          setState(() {});
                        },
                      );
                    }),

                    const SizedBox(height: 20),
                    Divider(color: Colors.white10),
                    const SizedBox(height: 12),

                    // ─── Sensitivity Slider ─────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sensitivity',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: KrakenColors.textSecondary,
                            )),
                        Text(
                          '${(tempSensitivity * 100).round()}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: KrakenColors.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.volume_mute, size: 16, color: KrakenColors.textMuted),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: KrakenColors.accent,
                              inactiveTrackColor: KrakenColors.surface,
                              thumbColor: KrakenColors.accent,
                              overlayColor: KrakenColors.accent.withAlpha(40),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: tempSensitivity,
                              min: 0.25,
                              max: 2.0,
                              divisions: 7,
                              onChanged: (val) {
                                setSheetState(() => tempSensitivity = val);
                              },
                              onChangeEnd: (val) async {
                                setState(() => _micSensitivity = val);
                                final prefs = RepositoryProvider.of<PreferencesService>(
                                    context, listen: false);
                                await prefs.setMicSensitivity(val);
                              },
                            ),
                          ),
                        ),
                        Icon(Icons.volume_up, size: 16, color: KrakenColors.textMuted),
                      ],
                    ),
                    Text(
                      'Adjusts how responsive the visualizer and recording level display are to audio input.',
                      style: TextStyle(
                        fontSize: 11,
                        color: KrakenColors.textMuted,
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMicOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected
                      ? KrakenColors.accent
                      : KrakenColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? KrakenColors.accent
                              : KrakenColors.textPrimary,
                        )),
                    Text(subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: KrakenColors.textSecondary,
                        )),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check, size: 18, color: KrakenColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  IconData _deviceTypeIcon(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.bluetooth:
        return Icons.bluetooth_audio;
      case AudioDeviceType.usb:
        return Icons.usb;
      case AudioDeviceType.wired:
        return Icons.headset_mic;
      case AudioDeviceType.builtin:
        return Icons.mic;
    }
  }

  String _deviceTypeLabel(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.bluetooth:
        return 'Bluetooth';
      case AudioDeviceType.usb:
        return 'USB';
      case AudioDeviceType.wired:
        return 'Wired';
      case AudioDeviceType.builtin:
        return 'Built-in';
    }
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: KrakenColors.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: KrakenColors.textSecondary, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: KrakenText.bodySm(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, color: KrakenColors.textMuted, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Transcription Language', style: KrakenText.displayMd()),
                  const SizedBox(height: 4),
                  Text(
                    'Whisper will use this language for all new recordings.',
                    style: KrakenText.bodySm(color: KrakenColors.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: whisperLanguageOptions.entries.map((entry) {
                  final isSelected = entry.key == _selectedLanguage;
                  return ListTile(
                    leading: isSelected
                        ? const Icon(Icons.check_circle, color: KrakenColors.accent, size: 20)
                        : const Icon(Icons.circle_outlined, color: Colors.white24, size: 20),
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        color: isSelected ? KrakenColors.accent : Colors.white,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final prefs = RepositoryProvider.of<PreferencesService>(context, listen: false);
                      await prefs.setString('default_language', entry.key);
                      setState(() => _selectedLanguage = entry.key);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
