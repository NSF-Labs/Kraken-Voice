import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:kraken_hub/kernel/audio/transcription_engine.dart';

/// Benchmarks Whisper transcription across language configurations.
/// Measures wall-clock time and output quality for: en, auto, es, ja.
///
/// Decision context: Addendum §9 — multilingual support evaluation.
/// This screen exists to generate real performance data for the
/// English-only vs multilingual product decision.
class LanguageBenchmarkScreen extends StatefulWidget {
  const LanguageBenchmarkScreen({super.key});

  @override
  State<LanguageBenchmarkScreen> createState() => _LanguageBenchmarkScreenState();
}

class _LanguageBenchmarkScreenState extends State<LanguageBenchmarkScreen> {
  String? _audioPath;
  String? _audioName;
  bool _isRunning = false;
  int _currentLangIndex = -1;

  static const _langConfigs = [
    {'code': 'en', 'label': 'English (explicit)'},
    {'code': 'auto', 'label': 'Auto-detect'},
    {'code': 'es', 'label': 'Spanish (explicit)'},
    {'code': 'ja', 'label': 'Japanese (explicit)'},
  ];

  final List<_BenchmarkResult> _results = [];

  static const _bg = Color(0xFF0A0A0C);
  static const _surface = Color(0xFF121216);
  static const _surfaceElevated = Color(0xFF17171D);
  static const _border = Color(0x0FFFFFFF);
  static const _accent = Color(0xFF8B7DFF);
  static const _textMuted = Color(0xFF6B6966);
  static const _textPrimary = Color(0xFFF2EFE8);
  static const _green = Color(0xFF6EE7B7);

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _audioPath = result.files.single.path!;
        _audioName = p.basename(_audioPath!);
        _results.clear();
      });
    }
  }

  Future<void> _runAllBenchmarks() async {
    if (_audioPath == null || !File(_audioPath!).existsSync()) return;

    setState(() {
      _isRunning = true;
      _results.clear();
    });

    final engine = TranscriptionEngine();

    for (int i = 0; i < _langConfigs.length; i++) {
      if (!mounted) return;
      setState(() => _currentLangIndex = i);

      final config = _langConfigs[i];
      final langCode = config['code']!;
      final label = config['label']!;

      final stopwatch = Stopwatch()..start();
      String output;
      try {
        output = await engine.transcribeFile(_audioPath!, lang: langCode);
      } catch (e) {
        output = 'ERROR: $e';
      }
      stopwatch.stop();

      if (mounted) {
        setState(() {
          _results.add(_BenchmarkResult(
            langCode: langCode,
            label: label,
            durationMs: stopwatch.elapsedMilliseconds,
            outputText: output,
            charCount: output.length,
          ));
        });
      }
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
        _currentLangIndex = -1;
      });
    }
  }

  Future<void> _runSingle(int index) async {
    if (_audioPath == null || !File(_audioPath!).existsSync()) return;

    setState(() {
      _isRunning = true;
      _currentLangIndex = index;
    });

    final engine = TranscriptionEngine();
    final config = _langConfigs[index];
    final langCode = config['code']!;
    final label = config['label']!;

    final stopwatch = Stopwatch()..start();
    String output;
    try {
      output = await engine.transcribeFile(_audioPath!, lang: langCode);
    } catch (e) {
      output = 'ERROR: $e';
    }
    stopwatch.stop();

    if (mounted) {
      // Remove any previous result for this lang
      _results.removeWhere((r) => r.langCode == langCode);
      setState(() {
        _results.add(_BenchmarkResult(
          langCode: langCode,
          label: label,
          durationMs: stopwatch.elapsedMilliseconds,
          outputText: output,
          charCount: output.length,
        ));
        _isRunning = false;
        _currentLangIndex = -1;
      });
    }
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    final secs = ms / 1000;
    if (secs < 60) return '${secs.toStringAsFixed(1)}s';
    final mins = (secs / 60).floor();
    final remSecs = (secs % 60).toStringAsFixed(1);
    return '${mins}m ${remSecs}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Language Benchmark',
          style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Context
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Addendum §9 — Multilingual Decision',
                  style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Tests Whisper transcription with en, auto-detect, es, and ja on the same audio file. '
                  'Reports wall-clock time and output text for product review.',
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Audio file selector
          InkWell(
            onTap: _isRunning ? null : _pickAudio,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.audio_file, color: _accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _audioName ?? 'Tap to select audio file',
                      style: TextStyle(
                        color: _audioName != null ? _textPrimary : _textMuted,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_audioName != null)
                    const Icon(Icons.check_circle, color: _green, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Run all button
          if (_audioPath != null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _runAllBenchmarks,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run All 4 Benchmarks'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Individual lang buttons
          ...List.generate(_langConfigs.length, (i) {
            final config = _langConfigs[i];
            final isActive = _currentLangIndex == i && _isRunning;
            final result = _results.where((r) => r.langCode == config['code']).firstOrNull;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: (_isRunning || _audioPath == null) ? null : () => _runSingle(i),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isActive ? _accent.withValues(alpha: 0.15) : _surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? _accent : (result != null ? _green.withValues(alpha: 0.3) : _border),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isActive)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                            )
                          else if (result != null)
                            const Icon(Icons.check_circle, color: _green, size: 16)
                          else
                            const Icon(Icons.play_circle_outline, color: _textMuted, size: 16),
                          const SizedBox(width: 10),
                          Text(config['label']!,
                            style: const TextStyle(color: _textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Text('lang: "${config['code']}"',
                            style: const TextStyle(color: _textMuted, fontFamily: 'monospace', fontSize: 11),
                          ),
                        ],
                      ),
                      if (result != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(result.durationMs),
                                style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${result.charCount} chars output',
                              style: const TextStyle(color: _textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),

          // Results comparison
          if (_results.length >= 2) ...[
            const SizedBox(height: 20),
            const Text('⏱ Timing Comparison',
              style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: _results.map((r) {
                  final enResult = _results.where((x) => x.langCode == 'en').firstOrNull;
                  final delta = enResult != null && r.langCode != 'en'
                      ? ' (${r.durationMs > enResult.durationMs ? '+' : ''}${((r.durationMs - enResult.durationMs) / 1000).toStringAsFixed(1)}s vs en)'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(r.label,
                            style: const TextStyle(color: _textPrimary, fontSize: 12),
                          ),
                        ),
                        Text(_formatDuration(r.durationMs),
                          style: const TextStyle(color: _green, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(delta,
                          style: TextStyle(
                            color: delta.contains('+') ? Colors.orange : _green,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Output text for each result
          ..._results.map((r) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.label} output:',
                  style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  child: SelectableText(
                    r.outputText,
                    style: const TextStyle(color: _textPrimary, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          )),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _BenchmarkResult {
  final String langCode;
  final String label;
  final int durationMs;
  final String outputText;
  final int charCount;

  _BenchmarkResult({
    required this.langCode,
    required this.label,
    required this.durationMs,
    required this.outputText,
    required this.charCount,
  });
}
