import '../../widgets/ios_gemma_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_lifecycle_bloc.dart';
import '../../app/ios_whisper_download.dart';
import '../../kernel/model_readiness_service.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key, this.download});
  final IOSWhisperDownload? download;

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  late final IOSWhisperDownload _download;

  @override
  void initState() {
    super.initState();
    _download = widget.download ?? IOSWhisperDownload.instance;
    _download.check();
  }

  Future<void> _startDownload() async {
    await _download.download();
    await ModelReadinessService().refresh();
  }

  Future<void> _leave() async {
    final bloc = context.read<AppLifecycleBloc>();
    final state = bloc.state;
    if (state is AppLifecycleReady && state.isOnboarded) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } else {
      final completed = bloc.stream.firstWhere(
        (state) => state is AppLifecycleReady && state.isOnboarded,
      );
      bloc.add(AppLifecycleOnboardingCompleted());
      await completed;
      if (mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F111A),
    appBar: AppBar(title: const Text('AI Models')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListenableBuilder(
              listenable: _download,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Offline AI Models',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Whisper is included with this app for offline transcription. Gemma adds offline summaries on supported devices. Your audio stays on this device.',
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Whisper · Transcription',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Multilingual base model · 148 MB'),
                          const SizedBox(height: 16),
                          if (_download.checking)
                            const LinearProgressIndicator()
                          else if (_download.ready)
                            const Text(
                              'Installed · Ready for offline transcription',
                              style: TextStyle(color: Colors.greenAccent),
                            )
                          else if (_download.downloading) ...[
                            LinearProgressIndicator(
                              value: _download.verifying
                                  ? null
                                  : _download.progress,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _download.verifying
                                  ? 'Verifying download…'
                                  : '${(_download.received / 1000000).toStringAsFixed(1)} / 148 MB',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Keep Kraken open until the download finishes.',
                            ),
                            TextButton(
                              onPressed: _download.cancel,
                              child: const Text('Cancel download'),
                            ),
                          ] else
                            FilledButton.icon(
                              onPressed: _startDownload,
                              icon: const Icon(Icons.download),
                              label: const Text('Download Whisper'),
                            ),
                          if (_download.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _download.error!,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const IOSGemmaCard(),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _leave,
                    child: Text(
                      _download.ready
                          ? 'Done'
                          : 'Continue without transcription',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
