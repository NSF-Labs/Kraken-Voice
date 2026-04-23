import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../kernel/audio/audio_channel.dart';
import '../../../kernel/audio/transcription_engine.dart';
import '../../../kernel/kernel.dart';
import '../../../kernel/vault/vault_service.dart';
import '../models/recording_session.dart';
import '../data/folder_repository.dart';

class RecordingScreen extends StatefulWidget {
  final SpokeContext spokeContext;

  const RecordingScreen({super.key, required this.spokeContext});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  // Hardcoded for Handoff 1 per user instructions
  final bool _isFreeTier = true;
  
  List<TranscriptSegment> _transcript = [];
  
  String? _pendingAudioPath;
  Duration? _pendingAudioDuration;

  // Waveform visualization data driven by EventChannel
  List<double> _waveformLevels = List.filled(100, 0.0, growable: true);
  double _smoothedAmplitude = 0.0;
  final Random _random = Random();
  
  StreamSubscription<double>? _amplitudeSubscription;
  late AudioEngine _audioEngine;

  @override
  void initState() {
    super.initState();
    _audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    _audioEngine.recordingDuration.addListener(_onDurationChanged);
    _audioEngine.recordingState.addListener(_onStateChanged);
    
    _setupWaveform();
    
    // Only check for recovery if we are currently idle
    if (_audioEngine.recordingState.value == AudioRecordingState.idle) {
      _checkRecovery();
    }
  }

  void _onDurationChanged() {
    if (mounted) setState(() {});
    
    final duration = _audioEngine.recordingDuration.value;
    _checkLimits(duration);
    
    if (duration.inSeconds > 0 && duration.inSeconds % 3 == 0) {
      _updateSessionMarker();
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _setupWaveform() {
    _amplitudeSubscription = _audioEngine.amplitudeStream.listen((amplitude) {
      if (mounted) {
        setState(() {
          _waveformLevels.removeAt(0);
          final rawScaled = ((amplitude / 32767.0) * 5.0).clamp(0.0, 1.0);
          _smoothedAmplitude = (_smoothedAmplitude * 0.5) + (rawScaled * 0.5);
          _waveformLevels.add(_audioEngine.recordingState.value == AudioRecordingState.recording ? _smoothedAmplitude : 0.0);
        });
      }
    });
  }

  Future<void> _checkRecovery() async {
    final sessionData = await widget.spokeContext.readData('active_session');
    if (sessionData != null && sessionData.isNotEmpty) {
      try {
        final session = RecordingSession.fromJson(jsonDecode(sessionData));
        if (mounted) {
          _showRecoveryDialog(session);
        }
      } catch (e) {
        await widget.spokeContext.writeData('active_session', '');
      }
    }
  }

  void _showRecoveryDialog(RecordingSession session) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('You were recording earlier.'),
        content: const Text('Kraken captured some audio before the app was closed. Would you like to keep it?'),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.spokeContext.writeData('active_session', '');
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.spokeContext.writeData('active_session', '');
              Navigator.pop(context);
              _finishRecordingAndTranscribe(session.outputFilePath);
            },
            child: const Text('Keep and transcribe'),
          ),
        ],
      ),
    );
  }

  void _startRecording() async {
    try {
      final path = await _audioEngine.startRecording();
      if (path != null) {
        final session = RecordingSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          startTime: DateTime.now(),
          outputFilePath: path,
          lastFlushed: DateTime.now(),
        );
        await widget.spokeContext.writeData('active_session', jsonEncode(session.toJson()));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start: $e')));
    }
  }

  Future<void> _updateSessionMarker() async {
    final path = _audioEngine.currentFilePath;
    if (path == null) return;
    
    final sessionData = await widget.spokeContext.readData('active_session');
    if (sessionData != null && sessionData.isNotEmpty) {
      try {
        final session = RecordingSession.fromJson(jsonDecode(sessionData));
        final updated = session.copyWith(lastFlushed: DateTime.now());
        await widget.spokeContext.writeData('active_session', jsonEncode(updated.toJson()));
      } catch (e) {}
    }
  }

  void _checkLimits(Duration duration) {
    if (_audioEngine.recordingState.value != AudioRecordingState.recording) return;

    if (duration.inSeconds == 5 * 3600) {
      _stopRecording(limitReachedMsg: "Recording stopped at the 5-hour safety limit. You can start a new recording if needed.");
      return;
    } else if (duration.inSeconds == 5 * 3600 - 60) {
      _showLimitModal("Recording will stop in 1 minute.");
    }

    if (!_isFreeTier) return;

    if (duration.inSeconds == 20 * 60) {
      _stopRecording(limitReachedMsg: "Recording stopped at the 20-minute free limit. You can review what was captured.");
    } else if (duration.inSeconds == 19 * 60 + 45) {
      _showUpgradeModal();
    }
  }

  void _showLimitModal(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Safety Limit'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _isUpgradeModalShowing = false;

  void _showUpgradeModal() {
    if (_isUpgradeModalShowing) return;
    _isUpgradeModalShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Free Limit Approaching'),
        content: const Text('Upgrade to continue or stop recording now. Whatever\'s captured will be saved either way.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _isUpgradeModalShowing = false;
              _stopRecording();
            },
            child: const Text('Stop recording'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _isUpgradeModalShowing = false;
              // TODO: Trigger upgrade flow
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopRecording({String? limitReachedMsg}) async {
    try {
      final path = await _audioEngine.stopRecording();
      await widget.spokeContext.writeData('active_session', ''); // Clear marker

      if (limitReachedMsg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(limitReachedMsg)));
      }

      _finishRecordingAndTranscribe(path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to stop: $e')));
    }
  }

  void _finishRecordingAndTranscribe(String path) async {
    try {
      final duration = await _audioEngine.getDuration(path);
      
      // Reset engine state for fresh recordings
      _audioEngine.recordingState.value = AudioRecordingState.idle;
      _audioEngine.recordingDuration.value = Duration.zero;
      
      if (mounted) {
        setState(() {
          _pendingAudioPath = path;
          _pendingAudioDuration = duration;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to process recording: $e')));
      }
    }
  }

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
  void dispose() {
    _audioEngine.recordingDuration.removeListener(_onDurationChanged);
    _audioEngine.recordingState.removeListener(_onStateChanged);
    _amplitudeSubscription?.cancel();
    super.dispose();
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 120,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(
          levels: _waveformLevels,
          gradient: const LinearGradient(
            colors: [
              Color(0xFFE0F7FA), // bright cyan-white at bottom
              Color(0xFF2196F3), // blue in the middle
              Color(0xFF8B0000), // dark crimson at top
            ],
            stops: [0.0, 0.5, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        size: Size.infinite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _audioEngine.recordingState.value;
    final elapsed = _audioEngine.recordingDuration.value;

    if (state == AudioRecordingState.transcribing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meeting Notes')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Transcribing on device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }
    
    if (state == AudioRecordingState.idle && _pendingAudioPath != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Needs Transcription')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.audio_file, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              Text('Audio Recorded', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Duration: ${_formatDuration(_pendingAudioDuration ?? Duration.zero)}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.text_snippet),
                label: const Text('Transcribe Now'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                onPressed: () async {
                  final engine = TranscriptionEngine();
                  final vault = RepositoryProvider.of<VaultService>(context);
                  final folderRepo = FolderRepository(vault);
                  
                  // Create a timestamped title for the recording
                  final now = DateTime.now();
                  final title = 'Recording ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
                  
                  await folderRepo.createRecording(
                    title: title,
                    audioPath: _pendingAudioPath!,
                    durationMs: _pendingAudioDuration?.inMilliseconds ?? 0,
                  );
                  
                  final retention = RepositoryProvider.of<RetentionService>(context);
                  await retention.enforceStorageCap();

                  await engine.queueJob(vault, _pendingAudioPath!);
                  setState(() {
                    _pendingAudioPath = null;
                    _pendingAudioDuration = null;
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transcription started. Check the folder for progress.')),
                    );
                    Navigator.pop(context);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final savedPath = _pendingAudioPath!;
                  final vault = RepositoryProvider.of<VaultService>(context);
                  final folderRepo = FolderRepository(vault);
                  
                  final now = DateTime.now();
                  final title = 'Recording ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
                  
                  await folderRepo.createRecording(
                    title: title,
                    audioPath: savedPath,
                    durationMs: _pendingAudioDuration?.inMilliseconds ?? 0,
                  );
                  
                  final retention = RepositoryProvider.of<RetentionService>(context);
                  await retention.enforceStorageCap();

                  setState(() {
                    _pendingAudioPath = null;
                    _pendingAudioDuration = null;
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Audio saved. Transcription deferred — you can start it anytime from the folder.')),
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text('Ask me later'),
              ),
            ],
          ),
        ),
      );
    }

    if (state == AudioRecordingState.idle && _transcript.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meeting Notes')),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _transcript.length,
          itemBuilder: (context, index) {
            final seg = _transcript[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        onTap: () async {
                          final newName = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              final controller = TextEditingController(text: seg.speakerLabel);
                              return AlertDialog(
                                title: const Text('Rename Speaker'),
                                content: TextField(controller: controller, autofocus: true),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
                                ],
                              );
                            },
                          );
                          if (newName != null && newName.isNotEmpty) {
                            setState(() {
                              _transcript[index] = seg.copyWith(speakerLabel: newName);
                            });
                          }
                        },
                        child: Text(seg.speakerLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatDuration(seg.timestamp), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final newText = await showDialog<String>(
                        context: context,
                        builder: (context) {
                          final controller = TextEditingController(text: seg.text);
                          return AlertDialog(
                            title: const Text('Edit Transcript'),
                            content: TextField(controller: controller, autofocus: true, maxLines: null),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
                            ],
                          );
                        },
                      );
                      if (newText != null && newText.isNotEmpty) {
                        setState(() {
                          _transcript[index] = seg.copyWith(text: newText);
                        });
                      }
                    },
                    child: Text(seg.text),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    String statusText = 'Ready to record';
    if (state == AudioRecordingState.recording) statusText = 'Recording';
    else if (state == AudioRecordingState.paused) statusText = 'Paused';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Notes'),
        actions: [
          if (state == AudioRecordingState.idle && _transcript.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                setState(() {
                  _transcript.clear();
                });
              },
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isFreeTier && state == AudioRecordingState.recording && elapsed.inSeconds >= 19 * 60 + 30)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange.withOpacity(0.2),
                  child: const Text('30 seconds remaining. Tap Stop to save, or upgrade to continue.', style: TextStyle(color: Colors.orange)),
                ),
              const SizedBox(height: 20),
              Text(statusText, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 20),
              Text(_formatDuration(elapsed), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              if (_isFreeTier && elapsed.inSeconds >= 15 * 60 && elapsed.inSeconds < 18 * 60)
                const Text('5 minutes remaining on free-tier recording', style: TextStyle(color: Colors.grey)),
              if (_isFreeTier && elapsed.inSeconds >= 18 * 60 && elapsed.inSeconds < 19 * 60 + 30)
                const Text('2 minutes remaining', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              _buildWaveform(),
              const SizedBox(height: 40),
              if (state == AudioRecordingState.idle)
                ElevatedButton.icon(
                  icon: const Icon(Icons.mic, size: 32),
                  label: const Text('Record', style: TextStyle(fontSize: 24)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                  onPressed: _startRecording,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 48,
                      icon: Icon(state == AudioRecordingState.paused ? Icons.play_arrow : Icons.pause),
                      onPressed: () async {
                        if (state == AudioRecordingState.paused) {
                          await _audioEngine.resumeRecording();
                        } else {
                          await _audioEngine.pauseRecording();
                        }
                      },
                    ),
                    const SizedBox(width: 40),
                    IconButton(
                      iconSize: 64,
                      icon: const Icon(Icons.stop_circle, color: Colors.red),
                      onPressed: () => _stopRecording(),
                    ),
                  ],
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the waveform as a continuous surface with a single uniform vertical gradient.
/// Every pixel at the same height gets exactly the same color, regardless of which bar it's in.
class _WaveformPainter extends CustomPainter {
  final List<double> levels;
  final LinearGradient gradient;

  _WaveformPainter({required this.levels, required this.gradient});

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final barCount = levels.length;
    final barWidth = size.width / barCount;
    final minHeight = 2.0;

    // Build a path that outlines all the bars
    final path = Path();
    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth;
      final barHeight = max(minHeight, levels[i] * size.height);
      final y = size.height - barHeight;
      path.addRect(Rect.fromLTWH(x, y, barWidth, barHeight));
    }

    // Paint the gradient, clipped to the bar outlines
    final gradientShader = gradient.createShader(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    final paint = Paint()..shader = gradientShader;

    canvas.clipPath(path);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}
