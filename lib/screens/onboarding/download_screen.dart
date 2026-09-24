import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../kernel/kernel.dart';
import '../../kernel/model_readiness_service.dart';
import '../../app/model_download_service.dart';
import '../../app/app_lifecycle_bloc.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final ModelDownloadService _service = ModelDownloadService();

  @override
  void initState() {
    super.initState();
    // Only check models if the service isn't already mid-download
    if (!_service.isDownloading &&
        _service.state.value != DownloadPipelineState.completed) {
      _service.checkModels();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Listen to the service's reactive state
    return ListenableBuilder(
      listenable: Listenable.merge([
        _service.state,
        _service.steps,
        _service.error,
        _service.overallProgress,
      ]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F111A),
          body: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.04,
                  child: Image.asset('assets/images/electric_kraken.png',
                      fit: BoxFit.cover),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(32.0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight - 64, // 32*2 padding
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Spacer(),
                              _buildIcon(),
                              const SizedBox(height: 32),
                              _buildTitle(),
                              const SizedBox(height: 16),
                              _buildSubtitle(),
                              const SizedBox(height: 24),
                              _buildStepList(),
                              if (_service.error.value != null) ...[
                                const SizedBox(height: 16),
                                _buildErrorCard(),
                              ],
                              const Spacer(),
                              _buildActionArea(),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Map service state to the old DownloadState for display ─────────────

  bool get _isChecking =>
      _service.state.value == DownloadPipelineState.checking;
  bool get _isDownloading =>
      _service.state.value == DownloadPipelineState.downloading;
  bool get _isReady =>
      _service.state.value == DownloadPipelineState.completed;
  Widget _buildIcon() {
    final progress = _service.overallProgress.value;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/electric_kraken.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
          if (_isChecking)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withAlpha(120),
              ),
              child: const Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                      color: Color(0xFF818CF8), strokeWidth: 3),
                ),
              ),
            ),
          if (_isDownloading)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withAlpha(120),
              ),
              child: Center(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progress,
                    color: const Color(0xFF818CF8),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 5,
                  ),
                ),
              ),
            ),
          if (_isReady)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF34D399),
                ),
                child:
                    const Icon(Icons.check, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    final text = _isChecking
        ? 'Verifying core dependencies...'
        : _isReady
            ? 'All Engines Ready'
            : 'Download AI Engine Bundle';
    return Text(
      text,
      style: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtitle() {
    if (_isChecking) return const SizedBox();

    if (_isDownloading) {
      final pct = (_service.overallProgress.value * 100).toStringAsFixed(0);
      return Text(
        '$pct% complete',
        style: TextStyle(
          fontSize: 16,
          color: Colors.white.withValues(alpha: 0.7),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_isReady) {
      return Text(
        'All AI engines are installed and ready for offline use.',
        style: TextStyle(
            fontSize: 16, color: Colors.white.withValues(alpha: 0.7)),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      'Kraken requires a one-time download of AI engines to operate '
      'completely offline (~2.6 GB total).\n\nWiFi is recommended.',
      style: TextStyle(
          fontSize: 16,
          color: Colors.white.withValues(alpha: 0.7),
          height: 1.5),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildStepList() {
    final stepList = _service.steps.value;
    return Column(
      children: stepList.map((step) {
        final icon = switch (step.status) {
          StepStatus.pending => Icon(Icons.circle_outlined,
              size: 20, color: Colors.white.withValues(alpha: 0.3)),
          StepStatus.downloading => const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF818CF8),
              ),
            ),
          StepStatus.done => const Icon(Icons.check_circle,
              size: 20, color: Color(0xFF34D399)),
          StepStatus.error => const Icon(Icons.error,
              size: 20, color: Colors.redAccent),
        };

        final textColor = switch (step.status) {
          StepStatus.pending => Colors.white.withValues(alpha: 0.4),
          StepStatus.downloading => Colors.white,
          StepStatus.done => const Color(0xFF34D399),
          StepStatus.error => Colors.redAccent,
        };

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(step.label,
                            style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text(step.sizeHint,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 12)),
                      ],
                    ),
                    if (step.status == StepStatus.downloading &&
                        step.progressText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(step.progressText,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: step.progress,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.1),
                          color: const Color(0xFF818CF8),
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: SingleChildScrollView(
        child: Text(
          _service.error.value!,
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildActionArea() {
    if (_isChecking || _isDownloading) {
      return const SizedBox(height: 56);
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isReady
                  ? const Color(0xFF34D399)
                  : const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: _isReady
                ? _completeOnboarding
                : () => _service.startDownload(),
            child: Text(
              _isReady
                  ? 'Continue'
                  : (_service.error.value != null
                      ? 'Retry Download'
                      : 'Download (WiFi recommended)'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (!_isReady) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _completeOnboarding,
            child: Text(
              'Skip for now',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
            ),
          ),
        ],
      ],
    );
  }

  /// Auto-initialize the vault with a device-secret-derived passphrase,
  /// mark onboarding complete, and navigate to the home screen.
  Future<void> _completeOnboarding() async {
    final lifecycleBloc = context.read<AppLifecycleBloc>();
    final isAlreadyOnboarded = lifecycleBloc.state is AppLifecycleReady &&
        (lifecycleBloc.state as AppLifecycleReady).isOnboarded;

    if (isAlreadyOnboarded) {
      // Post-onboarding re-download — just go home
      ModelReadinessService().refresh();
      if (mounted) GoRouter.of(context).go('/');
      return;
    }

    // First-run: create vault + mark onboarded
    context.read<AuthBloc>().add(
      const AuthPassphraseSubmitted(
        passphrase: 'kraken-auto-vault',
        enableBiometrics: false,
      ),
    );
    // Mark onboarding complete — triggers router redirect to '/'
    lifecycleBloc.add(AppLifecycleOnboardingCompleted());
  }
}
