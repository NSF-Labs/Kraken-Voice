import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shell/inference/model_manager.dart';

enum DownloadState { checking, required, downloading, ready }

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final ModelManager _modelManager = ModelManager();
  DownloadState _state = DownloadState.checking;
  double _progress = 0.0;
  String _sizeStr = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    try {
      final hasModel = await _modelManager.hasModel();
      if (!mounted) return;
      if (hasModel) {
        setState(() => _state = DownloadState.ready);
      } else {
        setState(() => _state = DownloadState.required);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = DownloadState.downloading;
      _error = null;
      _progress = 0;
    });

    try {
      // In a real scenario, use actual model URL. For this demo we simulate or use a small file
      // if no URL is provided in the brief. We will simulate download to avoid blocking the demo flow.
      await _simulateDownload();

      if (!mounted) return;
      setState(() => _state = DownloadState.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = DownloadState.required;
        _error = e.toString();
      });
    }
  }

  Future<void> _simulateDownload() async {
    // Simulate a 1.5GB download over a few seconds for the UX demo
    for (int i = 0; i <= 100; i += 2) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() {
        _progress = i / 100.0;
        final downloadedMb = (1500 * _progress).toStringAsFixed(1);
        _sizeStr = '$downloadedMb MB / 1500.0 MB';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              _buildIcon(),
              const SizedBox(height: 32),
              _buildTitle(),
              const SizedBox(height: 16),
              _buildSubtitle(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              _buildActionArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    IconData iconData;
    Color color;

    switch (_state) {
      case DownloadState.checking:
        return const CircularProgressIndicator(color: Color(0xFF818CF8));
      case DownloadState.required:
        iconData = Icons.cloud_download_outlined;
        color = const Color(0xFF818CF8);
        break;
      case DownloadState.downloading:
        return SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            value: _progress,
            color: const Color(0xFF818CF8),
            backgroundColor: Colors.white.withOpacity(0.1),
            strokeWidth: 8,
          ),
        );
      case DownloadState.ready:
        iconData = Icons.check_circle_outline;
        color = const Color(0xFF34D399);
        break;
    }

    return Icon(iconData, size: 80, color: color);
  }

  Widget _buildTitle() {
    String text;
    switch (_state) {
      case DownloadState.checking:
        text = 'Verifying core dependencies...';
        break;
      case DownloadState.required:
      case DownloadState.downloading:
        text = 'Download Core AI Engine';
        break;
      case DownloadState.ready:
        text = 'Engine Ready';
        break;
    }
    return Text(
      text,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtitle() {
    if (_state == DownloadState.checking) return const SizedBox();

    if (_state == DownloadState.downloading) {
      return Text(
        _sizeStr,
        style: TextStyle(
          fontSize: 16,
          color: Colors.white.withOpacity(0.7),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_state == DownloadState.ready) {
      return Text(
        'Gemma 4 is installed and ready for offline inference.',
        style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      'Kraken requires a 1.5GB initial download of the Gemma language model to operate completely offline.',
      style: TextStyle(
        fontSize: 16,
        color: Colors.white.withOpacity(0.7),
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildActionArea() {
    if (_state == DownloadState.checking ||
        _state == DownloadState.downloading) {
      return const SizedBox(height: 56);
    }

    final isReady = _state == DownloadState.ready;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isReady
              ? const Color(0xFF34D399)
              : const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: isReady
            ? () => context.go('/onboarding/secure')
            : _startDownload,
        child: Text(
          isReady ? 'Continue' : 'Download (WiFi recommended)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
