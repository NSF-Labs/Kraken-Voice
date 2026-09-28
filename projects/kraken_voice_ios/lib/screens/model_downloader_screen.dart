import 'package:flutter/material.dart';
import 'package:krak_en_voice/app/model_download_service.dart';

class ModelDownloaderScreen extends StatefulWidget {
  final VoidCallback onDownloadComplete;

  const ModelDownloaderScreen({super.key, required this.onDownloadComplete});

  @override
  State<ModelDownloaderScreen> createState() => _ModelDownloaderScreenState();
}

class _ModelDownloaderScreenState extends State<ModelDownloaderScreen> {
  final _service = ModelDownloadService();

  @override
  void initState() {
    super.initState();
    // Listen for completion to fire the callback
    _service.state.addListener(_onStateChanged);
    // If not already downloading, check + auto-start
    if (!_service.isDownloading) {
      _service.checkModels().then((allReady) {
        if (allReady) {
          widget.onDownloadComplete();
        }
      });
    }
  }

  @override
  void dispose() {
    _service.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (_service.state.value == DownloadPipelineState.completed) {
      widget.onDownloadComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        _service.state,
        _service.steps,
        _service.error,
        _service.overallProgress,
      ]),
      builder: (context, _) {
        final isDownloading = _service.isDownloading;
        final hasError = _service.state.value == DownloadPipelineState.error;
        final progress = _service.overallProgress.value;

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom -
                        64,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.memory,
                          size: 80, color: Colors.blueAccent),
                      const SizedBox(height: 32),
                      Text(
                        'AI Engine Setup Required',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'To keep the app size small, we need to download the AI models directly to your device.\n\nThis is a one-time download.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[400],
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      if (isDownloading) ...[
                        LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          backgroundColor: Colors.grey[800],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.blueAccent,
                          ),
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Downloading...\n${(progress * 100).toStringAsFixed(0)}% complete',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else if (hasError) ...[
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 32),
                                const SizedBox(height: 8),
                                Text(
                                  'Download failed',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _service.error.value ?? 'Unknown error',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.red[300],
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _service.startDownload(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Download'),
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          onPressed: () => _service.startDownload(),
                          icon: const Icon(Icons.download),
                          label: const Text('Download Models Now'),
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
