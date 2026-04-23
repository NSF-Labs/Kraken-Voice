import 'package:flutter/material.dart';
import '../../shell/inference/model_manager.dart';

class ModelDownloaderScreen extends StatefulWidget {
  final VoidCallback onDownloadComplete;

  const ModelDownloaderScreen({super.key, required this.onDownloadComplete});

  @override
  State<ModelDownloaderScreen> createState() => _ModelDownloaderScreenState();
}

class _ModelDownloaderScreenState extends State<ModelDownloaderScreen> {
  final _modelManager = ModelManager();

  bool _isDownloading = false;
  bool _isError = false;
  String _errorMessage = '';
  double _progress = 0.0;
  String _sizeStr = '0.0 MB / 0.0 MB';

  // Direct download URL for Gemma 4 E2B LiteRT-LM from Hugging Face
  final String _modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _isError = false;
      _progress = 0.0;
      _errorMessage = '';
    });

    try {
      await _modelManager.downloadModel(
        _modelUrl,
        onProgress: (progress, sizeStr) {
          setState(() {
            _progress = progress;
            _sizeStr = sizeStr;
          });
        },
      );

      // Complete!
      widget.onDownloadComplete();
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _isError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.memory, size: 80, color: Colors.blueAccent),
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
                'To keep the app size small, we need to download the Gemma 4 E2B model (approx. 1.5GB) directly to your device.\n\nThis is a one-time download.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[400],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              if (_isDownloading) ...[
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.blueAccent,
                  ),
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 16),
                Text(
                  'Downloading...\n$_sizeStr',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else if (_isError) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Download failed',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red[300],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Download'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Model Now'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
    );
  }
}
