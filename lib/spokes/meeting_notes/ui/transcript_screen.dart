import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/kernel/audio/transcription_engine.dart';
import 'package:kraken_hub/shell/design/tokens.dart';
import 'package:kraken_hub/shell/inference/model_manager.dart';
import '../data/folder_repository.dart';
import '../data/kraken_export_service.dart';

class TranscriptScreen extends StatefulWidget {
  final Recording recording;

  const TranscriptScreen({super.key, required this.recording});

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> with SingleTickerProviderStateMixin {
  late final FolderRepository _folderRepo;
  String? _transcriptText;
  String? _summaryJson;
  bool _isLoading = true;
  
  bool _isGeneratingSummary = false;
  String _streamingSummary = "";
  late String _currentTitle;

  // Summary version history
  List<Map<String, dynamic>> _summaryVersions = [];
  int _viewingVersionIndex = -1; // -1 = current, 0..n = history

  // Audio player
  final AudioPlayer _player = AudioPlayer();
  bool _isPlayerReady = false;
  Duration _playerPosition = Duration.zero;
  Duration _playerDuration = Duration.zero;
  bool _isPlaying = false;

  // Active transcription tracking
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isActivelyTranscribing = false;
  Timer? _transcriptionPollTimer;
  late DateTime _meetingDate;
  bool _userManuallyRenamed = false;

  @override
  void initState() {
    super.initState();
    _folderRepo = FolderRepository(context.read<VaultService>());
    _currentTitle = widget.recording.title;
    _meetingDate = widget.recording.meetingDate;
    
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadTranscript();
    _initPlayer();
    _startTranscriptionPolling();
  }

  void _startTranscriptionPolling() {
    _checkTranscriptionStatus();
    _transcriptionPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkTranscriptionStatus());
  }

  void _checkTranscriptionStatus() {
    final jobs = TranscriptionEngine().activeJobs.value;
    final isActive = jobs.any((j) =>
      j.audioPath == widget.recording.audioPath &&
      (j.status == TranscriptionStatus.processing || j.status == TranscriptionStatus.pending)
    );
    if (mounted && isActive != _isActivelyTranscribing) {
      setState(() => _isActivelyTranscribing = isActive);
      // If it just finished, reload the transcript
      if (!isActive && _transcriptText == null) {
        _loadTranscript();
      }
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setFilePath(widget.recording.audioPath);
      _isPlayerReady = true;
      
      _player.positionStream.listen((pos) {
        if (mounted) setState(() => _playerPosition = pos);
      });
      _player.durationStream.listen((dur) {
        if (mounted && dur != null) setState(() => _playerDuration = dur);
      });
      _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() => _isPlaying = state.playing);
          if (state.processingState == ProcessingState.completed) {
            _player.seek(Duration.zero);
            _player.pause();
          }
        }
      });
    } catch (e) {
      // File may not exist or be corrupt
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _pulseController.dispose();
    _transcriptionPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTranscript() async {
    setState(() => _isLoading = true);
    final text = await _folderRepo.getTranscriptionText(widget.recording.audioPath);
    final summary = await _folderRepo.getSummaryJson(widget.recording.audioPath);
    final versions = await _folderRepo.getSummaryVersions(widget.recording.audioPath);
    if (mounted) {
      setState(() {
        _transcriptText = text;
        _summaryJson = summary;
        _summaryVersions = versions;
        _viewingVersionIndex = -1; // Reset to current
        _isLoading = false;
      });
    }
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: _currentTitle);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Rename Recording', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyLg(),
          decoration: InputDecoration(
            hintText: 'Enter recording title',
            hintStyle: KrakenText.bodyMd(color: KrakenColors.textSecondary),
            filled: true,
            fillColor: KrakenColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: BorderSide(color: KrakenColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: const BorderSide(color: KrakenColors.accent),
            ),
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KrakenColors.accent),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (newName != null && newName.isNotEmpty && newName != _currentTitle) {
      await _folderRepo.renameRecording(widget.recording.id, newName);
      if (mounted) {
        setState(() {
          _currentTitle = newName;
          _userManuallyRenamed = true;
        });
      }
    }
  }

  /// AI-suggested name (N1): generates a short descriptive title from the summary.
  /// Only applies if user hasn't manually renamed and title is still the default.
  void _generateAIName(String summaryJson) async {
    // Skip if user already chose their own name
    if (_userManuallyRenamed) return;
    // Skip if title doesn't look like the auto-generated default (Recording M/D H:MM)
    if (!_currentTitle.startsWith('Recording ')) return;

    try {
      final inference = context.read<LocalInferenceService>();
      await inference.loadModel();

      // Parse summary for naming context
      String summaryContext = summaryJson;
      try {
        final parsed = jsonDecode(summaryJson) as Map<String, dynamic>;
        final tldr = parsed['tldr'] ?? '';
        final keyPoints = (parsed['key_points'] as List<dynamic>?)?.take(3).join(', ') ?? '';
        summaryContext = '$tldr\nKey topics: $keyPoints';
      } catch (_) {}

      if (summaryContext.length > 500) {
        summaryContext = summaryContext.substring(0, 500);
      }

      final prompt = '''You are naming a meeting recording. Based on this summary, produce a SHORT, specific title (3-8 words). Include key topic and context.

Good examples: "Q2 Budget Review with Finance", "Sprint 14 Retro", "Client Onboarding - Acme Corp", "Weekly 1:1 with Sarah"
Bad examples: "Meeting", "Recording 4/23", "Important Discussion", "Meeting about various topics"

Summary:
$summaryContext

Title:''';

      final buffer = StringBuffer();
      await for (final token in inference.generateStream(prompt, maxTokens: 32)) {
        buffer.write(token.text);
      }

      String suggestedName = buffer.toString().trim();
      // Clean up: remove quotes, newlines, trailing periods
      suggestedName = suggestedName
          .replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll('\n', ' ')
          .replaceAll(RegExp(r'\.$'), '')
          .trim();

      // Validate: must be 3-80 chars and not just generic garbage
      if (suggestedName.length < 3 || suggestedName.length > 80) return;
      if (suggestedName.toLowerCase() == 'meeting' || 
          suggestedName.toLowerCase() == 'recording') return;

      // Apply the AI name
      await _folderRepo.renameRecording(widget.recording.id, suggestedName);
      if (mounted) {
        setState(() => _currentTitle = suggestedName);
        debugPrint('[AI Name] Applied: "$suggestedName"');
      }
    } catch (e) {
      debugPrint('[AI Name] Failed: $e');
      // Non-fatal — recording keeps its default name
    }
  }

  /// Checks if the Gemma model file exists on device.
  /// Returns true if available, false if not (and shows download prompt).
  Future<bool> _checkModelAvailable() async {
    final modelManager = ModelManager();
    final hasModel = await modelManager.hasModel();
    if (hasModel) return true;

    if (!mounted) return false;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('AI Model Required', style: KrakenText.displayMd()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The Gemma AI model (~1.5 GB) needs to be downloaded before generating summaries.',
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
            ),
            const SizedBox(height: KrakenSpacing.s3),
            Text(
              'Go to Settings → AI Engine to download it.',
              style: KrakenText.bodyMd(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KrakenColors.accent),
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/settings');
            },
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _generateSummary() async {
    // Gate on model availability — show download prompt if missing
    if (!await _checkModelAvailable()) return;

    setState(() {
      _isGeneratingSummary = true;
      _streamingSummary = "";
    });

    // Truncate transcript to ~3000 chars to keep inference fast on-device
    String transcript = _transcriptText ?? '';
    if (transcript.length > 3000) {
      transcript = '${transcript.substring(0, 3000)}\n\n[...transcript truncated for summarization...]';
    }

    final prompt = '''You are a professional meeting assistant. Summarize the transcript below.

You must return ONLY a JSON object. Do not include any explanation, commentary, or formatting outside the JSON.

Use this exact structure:
{"tldr": "...", "key_points": ["..."], "decisions": ["..."], "action_items": ["..."], "open_questions": ["..."]}

Rules for writing the values:
- Write in plain conversational English, as if speaking to a colleague.
- Never use programming syntax: no backslashes, no escape sequences, no \n, no \t, no \".
- Never use markdown: no **, no `, no ```, no #, no bullet characters.
- Never use HTML tags or any markup language.
- Use normal punctuation: periods, commas, question marks.
- If a category has no items, use an empty array [].
- Keep each bullet to one clear sentence.

Transcript:
$transcript''';

    final inference = context.read<LocalInferenceService>();

    try {
      await inference.loadModel();
      
      final stream = inference.generateStream(prompt, maxTokens: 512);
      stream.listen(
        (token) {
          if (mounted) setState(() => _streamingSummary += token.text);
        },
        onDone: () async {
          if (mounted) {
            // Post-process: strip markdown code fences, extract JSON, and clean values
            String cleaned = _streamingSummary.trim();
            // Strip code fences
            if (cleaned.startsWith('```')) {
              final lines = cleaned.split('\n');
              if (lines.length > 2) {
                cleaned = lines.sublist(1, lines.length - (lines.last.trim().startsWith('```') ? 1 : 0)).join('\n').trim();
              }
            }
            // Extract JSON object if surrounded by text
            final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
            if (jsonMatch != null) {
              cleaned = jsonMatch.group(0)!;
            }
            // Deep-clean: parse JSON, sanitize each value, re-encode
            try {
              final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
              final sanitized = <String, dynamic>{};
              for (final entry in parsed.entries) {
                if (entry.value is String) {
                  sanitized[entry.key] = _cleanSummaryText(entry.value as String);
                } else if (entry.value is List) {
                  sanitized[entry.key] = (entry.value as List).map((e) => _cleanSummaryText(e.toString())).toList();
                } else {
                  sanitized[entry.key] = entry.value;
                }
              }
              cleaned = jsonEncode(sanitized);
            } catch (_) {
              // If JSON parsing fails, keep the string as-is for the fallback renderer
            }
            
            setState(() {
              _summaryJson = cleaned;
              _isGeneratingSummary = false;
              _viewingVersionIndex = -1;
            });
            await _folderRepo.saveSummaryJson(widget.recording.audioPath, cleaned);
            // Sync action items from new summary
            await _folderRepo.syncActionItemsFromSummary(widget.recording.id, cleaned);
            // Reload version history
            final versions = await _folderRepo.getSummaryVersions(widget.recording.audioPath);
            if (mounted) setState(() => _summaryVersions = versions);
            // AI-suggested name (N1) — runs after summary is saved
            _generateAIName(cleaned);
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() => _isGeneratingSummary = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingSummary = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showRefineDialog() async {
    final controller = TextEditingController();
    final instruction = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Refine Summary', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: KrakenText.bodyMd(),
          decoration: InputDecoration(
            hintText: 'e.g. "Focus more on action items" or "Add participant names"',
            hintStyle: KrakenText.bodySm(color: KrakenColors.textMuted),
            filled: true,
            fillColor: KrakenColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: BorderSide(color: KrakenColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: const BorderSide(color: KrakenColors.accent),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: KrakenText.bodySm())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KrakenColors.accent),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Refine'),
          ),
        ],
      ),
    );

    if (instruction != null && instruction.isNotEmpty) {
      await _refineSummary(instruction);
    }
  }

  Future<void> _refineSummary(String instruction) async {
    // Gate on model availability
    if (!await _checkModelAvailable()) return;

    setState(() {
      _isGeneratingSummary = true;
      _streamingSummary = "";
    });

    String transcript = _transcriptText ?? '';
    if (transcript.length > 3000) {
      transcript = '${transcript.substring(0, 3000)}\n\n[...transcript truncated...]';
    }

    final existingSummary = _summaryJson ?? '';

    final prompt = '''You previously summarized a meeting transcript and produced this summary:
$existingSummary

The user wants you to refine it with this instruction: "$instruction"

Return ONLY a JSON object with the refined summary. No explanation, no commentary outside the JSON.

Use this exact structure:
{"tldr": "...", "key_points": ["..."], "decisions": ["..."], "action_items": ["..."], "open_questions": ["..."]}

Rules for writing the values:
- Write in plain conversational English, as if speaking to a colleague.
- Never use programming syntax: no backslashes, no escape sequences, no \n, no \t.
- Never use markdown: no **, no `, no ```, no #, no bullet characters.
- Never use HTML tags or any markup language.
- Use normal punctuation only.
- If a category has no items, use an empty array [].
- Keep each bullet to one clear sentence.

Original transcript for reference:
$transcript''';

    final inference = context.read<LocalInferenceService>();

    try {
      await inference.loadModel();
      
      final stream = inference.generateStream(prompt, maxTokens: 512);
      stream.listen(
        (token) {
          if (mounted) setState(() => _streamingSummary += token.text);
        },
        onDone: () async {
          if (mounted) {
            String cleaned = _streamingSummary.trim();
            // Strip code fences
            if (cleaned.startsWith('```')) {
              final lines = cleaned.split('\n');
              if (lines.length > 2) {
                cleaned = lines.sublist(1, lines.length - (lines.last.trim().startsWith('```') ? 1 : 0)).join('\n').trim();
              }
            }
            // Extract JSON object if surrounded by text
            final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
            if (jsonMatch != null) {
              cleaned = jsonMatch.group(0)!;
            }
            // Deep-clean: parse JSON, sanitize each value, re-encode
            try {
              final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
              final sanitized = <String, dynamic>{};
              for (final entry in parsed.entries) {
                if (entry.value is String) {
                  sanitized[entry.key] = _cleanSummaryText(entry.value as String);
                } else if (entry.value is List) {
                  sanitized[entry.key] = (entry.value as List).map((e) => _cleanSummaryText(e.toString())).toList();
                } else {
                  sanitized[entry.key] = entry.value;
                }
              }
              cleaned = jsonEncode(sanitized);
            } catch (_) {}
            setState(() {
              _summaryJson = cleaned;
              _isGeneratingSummary = false;
              _viewingVersionIndex = -1;
            });
            await _folderRepo.saveSummaryJson(widget.recording.audioPath, cleaned);
            // Sync action items from refined summary
            await _folderRepo.syncActionItemsFromSummary(widget.recording.id, cleaned);
            final versions = await _folderRepo.getSummaryVersions(widget.recording.audioPath);
            if (mounted) setState(() => _summaryVersions = versions);
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() => _isGeneratingSummary = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refine failed: $e')));
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingSummary = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Strips code-like artifacts that small LLMs sometimes leak into summary text.
  String _cleanSummaryText(String text) {
    return text
        .replaceAll(RegExp(r'```\w*\n?'), '')         // code fences
        .replaceAll('\\n', ' ')                       // literal \n (escaped newline)
        .replaceAll('\\t', ' ')                       // literal \t (escaped tab)
        .replaceAll('\\"', '"')                       // escaped double quotes
        .replaceAll("\\\'" , "'")                     // escaped single quotes
        .replaceAll('\\\\', '')                       // double backslashes
        .replaceAll(RegExp(r'\*\*'), '')              // bold markdown **
        .replaceAll(RegExp(r'__'), '')                // bold markdown __
        .replaceAll(RegExp(r'`([^`]*)`'), r'\1')     // inline code `text`
        .replaceAll(RegExp(r'#{1,6}\s*'), '')         // heading markers
        .replaceAll(RegExp(r'^\s*[-*•]\s*', multiLine: true), '') // leading bullets
        .replaceAll(RegExp(r'^\s*\d+\.\s*', multiLine: true), '') // numbered lists
        .replaceAll(RegExp(r'<[^>]+>'), '')           // HTML tags
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'\1') // markdown links
        .replaceAll(RegExp(r'\s{2,}'), ' ')           // collapse whitespace
        .trim();
  }

  String _formatPos(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = d.inHours;
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (hours > 0) return "$hours:$minutes:$seconds";
    return "$minutes:$seconds";
  }

  // ─── Export helpers ──────────────────────────────────────────────────────────

  String _safeFileName(String title) => title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');

  Future<void> _exportAudio() async {
    final audioFile = File(widget.recording.audioPath);
    if (!await audioFile.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio file not found.')));
      return;
    }
    // Copy audio to temp with the current title so the shared file has the right name
    final ext = widget.recording.audioPath.split('.').last;
    final dir = await getTemporaryDirectory();
    final namedFile = await audioFile.copy('${dir.path}/${_safeFileName(_currentTitle)}.$ext');
    await Share.shareXFiles(
      [XFile(namedFile.path)],
      subject: '$_currentTitle — Audio',
    );
  }

  Future<void> _exportTranscript() async {
    if (_transcriptText == null || _transcriptText!.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No transcript to export.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeFileName(_currentTitle)}_transcript.txt');
    await file.writeAsString('Transcript: $_currentTitle\n${'=' * 40}\n\n$_transcriptText');
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$_currentTitle — Transcript',
    );
  }

  Future<void> _exportSummary() async {
    if (_summaryJson == null || _summaryJson!.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No summary to export.')));
      return;
    }

    // Try to produce a human-readable summary
    String exportContent;
    try {
      String raw = _summaryJson!.trim();
      if (raw.startsWith('```')) {
        final lines = raw.split('\n');
        if (lines.length > 2) raw = lines.sublist(1, lines.length - 1).join('\n');
      }
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final sb = StringBuffer();
      sb.writeln('AI Summary: ${widget.recording.title}');
      sb.writeln('${'=' * 40}\n');
      sb.writeln('EXECUTIVE SUMMARY');
      sb.writeln('-' * 20);
      sb.writeln(parsed['summary'] ?? 'N/A');
      final actions = parsed['action_items'] as List<dynamic>? ?? [];
      if (actions.isNotEmpty) {
        sb.writeln('\nACTION ITEMS');
        sb.writeln('-' * 20);
        for (int i = 0; i < actions.length; i++) {
          sb.writeln('${i + 1}. ${actions[i]}');
        }
      }
      exportContent = sb.toString();
    } catch (_) {
      exportContent = 'AI Summary: ${widget.recording.title}\n${'=' * 40}\n\n$_summaryJson';
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeFileName(_currentTitle)}_summary.txt');
    await file.writeAsString(exportContent);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$_currentTitle — AI Summary',
    );
  }

  Future<void> _exportAll() async {
    final files = <XFile>[];

    // Audio — copy with current title
    final audioFile = File(widget.recording.audioPath);
    if (await audioFile.exists()) {
      final ext = widget.recording.audioPath.split('.').last;
      final dir = await getTemporaryDirectory();
      final namedAudio = await audioFile.copy('${dir.path}/${_safeFileName(_currentTitle)}.$ext');
      files.add(XFile(namedAudio.path));
    }

    // Transcript
    if (_transcriptText != null && _transcriptText!.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      final txtFile = File('${dir.path}/${_safeFileName(_currentTitle)}_transcript.txt');
      await txtFile.writeAsString('Transcript: $_currentTitle\n${'=' * 40}\n\n$_transcriptText');
      files.add(XFile(txtFile.path));
    }

    // Summary
    if (_summaryJson != null && _summaryJson!.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      String exportContent;
      try {
        String raw = _summaryJson!.trim();
        if (raw.startsWith('```')) {
          final lines = raw.split('\n');
          if (lines.length > 2) raw = lines.sublist(1, lines.length - 1).join('\n');
        }
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final sb = StringBuffer();
        sb.writeln('AI Summary: $_currentTitle');
        sb.writeln('${'=' * 40}\n');
        sb.writeln('EXECUTIVE SUMMARY');
        sb.writeln('-' * 20);
        sb.writeln(parsed['summary'] ?? 'N/A');
        final actions = parsed['action_items'] as List<dynamic>? ?? [];
        if (actions.isNotEmpty) {
          sb.writeln('\nACTION ITEMS');
          sb.writeln('-' * 20);
          for (int i = 0; i < actions.length; i++) {
            sb.writeln('${i + 1}. ${actions[i]}');
          }
        }
        exportContent = sb.toString();
      } catch (_) {
        exportContent = _summaryJson!;
      }
      final sumFile = File('${dir.path}/${_safeFileName(_currentTitle)}_summary.txt');
      await sumFile.writeAsString(exportContent);
      files.add(XFile(sumFile.path));
    }

    if (files.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to export.')));
      return;
    }

    await Share.shareXFiles(
      files,
      subject: '$_currentTitle — Full Export',
    );
  }

  Future<void> _exportMarkdown() async {
    final sb = StringBuffer();
    sb.writeln('# $_currentTitle');
    sb.writeln();
    sb.writeln('**Date:** ${_formatDate(_meetingDate)}  ');
    sb.writeln('**Duration:** ${_formatPos(Duration(milliseconds: widget.recording.durationMs))}  ');
    sb.writeln();

    // Summary section
    if (_summaryJson != null && _summaryJson!.isNotEmpty) {
      try {
        String raw = _summaryJson!.trim();
        if (raw.startsWith('```')) {
          final lines = raw.split('\n');
          if (lines.length > 2) raw = lines.sublist(1, lines.length - 1).join('\n');
        }
        final parsed = jsonDecode(raw) as Map<String, dynamic>;

        if (parsed['tldr'] != null) {
          sb.writeln('## Summary');
          sb.writeln(parsed['tldr']);
          sb.writeln();
        }
        if (parsed['summary'] != null) {
          sb.writeln('## Summary');
          sb.writeln(parsed['summary']);
          sb.writeln();
        }
        final keyPoints = parsed['key_points'] as List<dynamic>? ?? [];
        if (keyPoints.isNotEmpty) {
          sb.writeln('## Key Points');
          for (final p in keyPoints) {
            sb.writeln('- $p');
          }
          sb.writeln();
        }
        final decisions = parsed['decisions'] as List<dynamic>? ?? [];
        if (decisions.isNotEmpty) {
          sb.writeln('## Decisions');
          for (final d in decisions) {
            sb.writeln('- $d');
          }
          sb.writeln();
        }
        final actions = parsed['action_items'] as List<dynamic>? ?? [];
        if (actions.isNotEmpty) {
          sb.writeln('## Action Items');
          for (final a in actions) {
            sb.writeln('- [ ] $a');
          }
          sb.writeln();
        }
        final questions = parsed['open_questions'] as List<dynamic>? ?? [];
        if (questions.isNotEmpty) {
          sb.writeln('## Open Questions');
          for (final q in questions) {
            sb.writeln('- $q');
          }
          sb.writeln();
        }
      } catch (_) {
        sb.writeln('## AI Summary');
        sb.writeln(_summaryJson);
        sb.writeln();
      }
    }

    // Transcript section
    if (_transcriptText != null && _transcriptText!.isNotEmpty) {
      sb.writeln('---');
      sb.writeln();
      sb.writeln('## Full Transcript');
      sb.writeln();
      sb.writeln(_transcriptText);
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeFileName(_currentTitle)}.md');
    await file.writeAsString(sb.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$_currentTitle — Markdown Export',
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _showMeetingDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _meetingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: KrakenColors.accent,
              surface: KrakenColors.surfaceElevated,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _meetingDate = picked);
      await _folderRepo.setMeetingDate(widget.recording.id, picked);
    }
  }

  void _showExportSheet() {
    final hasTranscript = _transcriptText != null && _transcriptText!.isNotEmpty;
    final hasSummary = _summaryJson != null && _summaryJson!.isNotEmpty;
    final hasAudio = !widget.recording.isAudioDeleted;

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // Checkbox state for each format
        final selected = <String, bool>{
          'pdf': false,
          'docx': false,
          'audio': false,
          'transcript': false,
        };

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: KrakenSpacing.s4, horizontal: KrakenSpacing.s4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: KrakenColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: KrakenSpacing.s4),
                      Text('Export', style: KrakenText.displayMd()),
                      const SizedBox(height: 4),
                      Text(
                        'Select one or more formats',
                        style: KrakenText.bodySm(color: KrakenColors.textMuted),
                      ),
                      const SizedBox(height: KrakenSpacing.s3),

                      // Professional formats
                      _exportCheckbox(
                        setSheetState, selected, 'pdf',
                        Icons.picture_as_pdf, 'PDF Document',
                        'Summary + transcript in one report',
                        enabled: hasTranscript || hasSummary,
                      ),
                      _exportCheckbox(
                        setSheetState, selected, 'docx',
                        Icons.description_outlined, 'Word Document',
                        'Editable .docx with summary + transcript',
                        enabled: hasTranscript || hasSummary,
                      ),

                      const Divider(color: KrakenColors.border, height: 24),

                      // Raw formats
                      _exportCheckbox(
                        setSheetState, selected, 'audio',
                        Icons.audio_file, 'Audio File',
                        hasAudio ? '.wav recording' : 'Audio unavailable',
                        enabled: hasAudio,
                      ),
                      _exportCheckbox(
                        setSheetState, selected, 'transcript',
                        Icons.text_snippet, 'Transcript Only',
                        '.txt plain text',
                        enabled: hasTranscript,
                      ),

                      const SizedBox(height: KrakenSpacing.s4),

                      // Export button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.ios_share, size: 18),
                          label: Text(
                            'Export ${_countSelected(selected)} format${_countSelected(selected) != 1 ? 's' : ''}',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: KrakenColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _countSelected(selected) > 0
                              ? () {
                                  Navigator.pop(context);
                                  _executeMultiFormatExport(selected);
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(height: KrakenSpacing.s2),
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

  Widget _exportCheckbox(
    StateSetter setSheetState,
    Map<String, bool> selected,
    String key,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
  }) {
    return CheckboxListTile(
      value: enabled ? (selected[key] ?? false) : false,
      onChanged: enabled
          ? (val) => setSheetState(() => selected[key] = val ?? false)
          : null,
      activeColor: KrakenColors.accent,
      secondary: Icon(icon, color: enabled ? KrakenColors.accent : KrakenColors.textMuted),
      title: Text(title, style: KrakenText.bodyMd(
        color: enabled ? KrakenColors.textPrimary : KrakenColors.textMuted,
      )),
      subtitle: Text(subtitle, style: KrakenText.bodySm(color: KrakenColors.textMuted)),
      controlAffinity: ListTileControlAffinity.trailing,
      dense: true,
    );
  }

  int _countSelected(Map<String, bool> selected) =>
      selected.values.where((v) => v).length;

  Future<void> _executeMultiFormatExport(Map<String, bool> selected) async {
    final exportService = KrakenExportService();
    final files = <XFile>[];
    final safeName = KrakenExportService.safeFileName(_currentTitle);
    final errors = <String>[];

    // Clean up stale exports ONCE before generating new files
    await KrakenExportService.cleanupTempExports();

    // PDF (auto-includes summary when available)
    if (selected['pdf'] == true) {
      try {
        final pdfFile = await exportService.exportPdf(
          recording: widget.recording,
          title: _currentTitle,
          transcriptText: _transcriptText,
          summaryJson: _summaryJson,
        );
        if (await pdfFile.exists()) files.add(XFile(pdfFile.path));
      } catch (e) {
        errors.add('PDF: $e');
      }
    }

    // DOCX (auto-includes summary when available)
    if (selected['docx'] == true) {
      try {
        final docxFile = await exportService.exportDocx(
          recording: widget.recording,
          title: _currentTitle,
          transcriptText: _transcriptText,
          summaryJson: _summaryJson,
        );
        if (await docxFile.exists()) files.add(XFile(docxFile.path));
      } catch (e) {
        errors.add('DOCX: $e');
      }
    }

    // Audio
    if (selected['audio'] == true) {
      try {
        final audioFile = File(widget.recording.audioPath);
        if (await audioFile.exists()) {
          final ext = widget.recording.audioPath.split('.').last;
          final dir = await getTemporaryDirectory();
          final namedFile = await audioFile.copy('${dir.path}/kraken_$safeName.$ext');
          files.add(XFile(namedFile.path));
        }
      } catch (e) {
        errors.add('Audio: $e');
      }
    }

    // Transcript (.txt)
    if (selected['transcript'] == true && _transcriptText != null) {
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/kraken_${safeName}_transcript.txt');
        await file.writeAsString('Transcript: $_currentTitle\n${'=' * 40}\n\n$_transcriptText');
        files.add(XFile(file.path));
      } catch (e) {
        errors.add('Transcript: $e');
      }
    }


    if (files.isEmpty) {
      if (mounted) {
        final msg = errors.isNotEmpty
            ? 'Export failed: ${errors.join('; ')}'
            : 'Nothing to export.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return;
    }

    try {
      await Share.shareXFiles(
        files,
        subject: '$_currentTitle — Kraken Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }

    // Show partial success if some formats failed
    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Some formats failed: ${errors.join('; ')}')),
      );
    }
  }

  String _buildSummaryExportContent() {
    try {
      String raw = _summaryJson!.trim();
      if (raw.startsWith('```')) {
        final lines = raw.split('\n');
        if (lines.length > 2) raw = lines.sublist(1, lines.length - 1).join('\n');
      }
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final sb = StringBuffer();
      sb.writeln('AI Summary: $_currentTitle');
      sb.writeln('Date: ${_formatDate(_meetingDate)}');
      sb.writeln('Duration: ${_formatPos(Duration(milliseconds: widget.recording.durationMs))}');
      sb.writeln('${'=' * 50}\n');

      if (parsed['tldr'] != null) {
        sb.writeln('SUMMARY');
        sb.writeln('-' * 30);
        sb.writeln(parsed['tldr']);
        sb.writeln();
      }

      if (parsed['summary'] != null) {
        sb.writeln('EXECUTIVE SUMMARY');
        sb.writeln('-' * 30);
        sb.writeln(parsed['summary']);
        sb.writeln();
      }

      for (final entry in {
        'key_points': 'KEY POINTS',
        'decisions': 'DECISIONS',
      }.entries) {
        final items = parsed[entry.key] as List<dynamic>? ?? [];
        if (items.isNotEmpty) {
          sb.writeln(entry.value);
          sb.writeln('-' * 30);
          for (int i = 0; i < items.length; i++) {
            sb.writeln('  ${i + 1}. ${items[i]}');
          }
          sb.writeln();
        }
      }

      final actions = parsed['action_items'] as List<dynamic>? ?? [];
      if (actions.isNotEmpty) {
        sb.writeln('ACTION ITEMS');
        sb.writeln('-' * 30);
        for (int i = 0; i < actions.length; i++) {
          sb.writeln('  [ ] ${i + 1}. ${actions[i]}');
        }
        sb.writeln();
      }

      final questions = parsed['open_questions'] as List<dynamic>? ?? [];
      if (questions.isNotEmpty) {
        sb.writeln('OPEN QUESTIONS');
        sb.writeln('-' * 30);
        for (int i = 0; i < questions.length; i++) {
          sb.writeln('  ${i + 1}. ${questions[i]}');
        }
        sb.writeln();
      }

      sb.writeln('${'=' * 50}');
      sb.writeln('Generated by The Kraken');

      return sb.toString();
    } catch (_) {
      return 'AI Summary: $_currentTitle\n${'=' * 50}\n\n$_summaryJson';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: _showRenameDialog,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(_currentTitle, style: KrakenText.displayMd(), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 14, color: KrakenColors.textSecondary),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, color: KrakenColors.textSecondary),
            tooltip: 'Export',
            onPressed: _showExportSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transcriptText == null || _transcriptText!.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(KrakenSpacing.s6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isActivelyTranscribing) ...[
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) => Icon(
                              Icons.hearing,
                              size: 64,
                              color: KrakenColors.accent.withValues(alpha: _pulseAnimation.value),
                            ),
                          ),
                          const SizedBox(height: KrakenSpacing.s4),
                          Text('Transcribing on device...', style: KrakenText.displayMd()),
                          const SizedBox(height: KrakenSpacing.s3),
                          // Real progress bar with percentage
                          ValueListenableBuilder<Map<String, double>>(
                            valueListenable: TranscriptionEngine().transcriptionProgress,
                            builder: (context, progressMap, _) {
                              final progress = progressMap[widget.recording.audioPath];
                              if (progress == null) {
                                return const LinearProgressIndicator(
                                  value: null,
                                  backgroundColor: KrakenColors.surface,
                                  valueColor: AlwaysStoppedAnimation<Color>(KrakenColors.accent),
                                );
                              }
                              return Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: KrakenColors.border,
                                      valueColor: const AlwaysStoppedAnimation<Color>(KrakenColors.accent),
                                      minHeight: 8,
                                    ),
                                  ),
                                  const SizedBox(height: KrakenSpacing.s2),
                                  Text(
                                    '${(progress * 100).toInt()}% complete',
                                    style: KrakenText.bodySm(color: KrakenColors.accent).copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: KrakenSpacing.s6),
                          // Flowing shimmer banner
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, _) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: KrakenSpacing.s4, vertical: KrakenSpacing.s2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    KrakenColors.accent.withValues(alpha: 0.05),
                                    KrakenColors.accent.withValues(alpha: 0.15 * _pulseAnimation.value),
                                    KrakenColors.accent.withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(KrakenRadius.md),
                                border: Border.all(color: KrakenColors.accent.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 14, color: KrakenColors.accent.withValues(alpha: 0.7)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Processing locally on your device',
                                    style: KrakenText.bodySm(color: KrakenColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          Icon(
                            widget.recording.transcriptionStatus == 'failed'
                              ? Icons.error_outline
                              : Icons.pending_actions,
                            size: 64,
                            color: widget.recording.transcriptionStatus == 'failed'
                              ? Colors.orangeAccent
                              : KrakenColors.textMuted,
                          ),
                          const SizedBox(height: KrakenSpacing.s4),
                          Text(
                            widget.recording.transcriptionStatus == 'failed'
                              ? 'Transcription failed'
                              : 'No transcript available yet.',
                            style: KrakenText.displayMd(),
                          ),
                          const SizedBox(height: KrakenSpacing.s2),
                          Text(
                            'Status: ${widget.recording.transcriptionStatus ?? 'Unknown'}',
                            style: KrakenText.bodyMd(color: KrakenColors.textMuted),
                          ),
                          if (widget.recording.transcriptionStatus == 'failed' ||
                              widget.recording.transcriptionStatus == null) ...[
                            const SizedBox(height: KrakenSpacing.s6),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final engine = TranscriptionEngine();
                                final vault = RepositoryProvider.of<VaultService>(context, listen: false);
                                
                                // Clear any old failed job
                                await vault.db.delete(
                                  'transcription_jobs',
                                  where: 'audio_path = ?',
                                  whereArgs: [widget.recording.audioPath],
                                );
                                
                                await engine.queueJob(vault, widget.recording.audioPath);
                                _startTranscriptionPolling(); // resume polling
                                if (mounted) {
                                  setState(() => _isActivelyTranscribing = true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Transcription re-queued.')),
                                  );
                                }
                              },
                              icon: Icon(
                                widget.recording.transcriptionStatus == 'failed'
                                  ? Icons.refresh
                                  : Icons.record_voice_over,
                              ),
                              label: Text(
                                widget.recording.transcriptionStatus == 'failed'
                                  ? 'Retry Transcription'
                                  : 'Start Transcription',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: KrakenColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: KrakenSpacing.s6,
                                  vertical: KrakenSpacing.s3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(KrakenSpacing.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Audio Player Card
                      Container(
                        padding: const EdgeInsets.all(KrakenSpacing.s4),
                        decoration: BoxDecoration(
                          color: KrakenColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(KrakenRadius.lg),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _isPlayerReady
                                    ? () => _isPlaying ? _player.pause() : _player.play()
                                    : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(KrakenSpacing.s3),
                                    decoration: const BoxDecoration(
                                      color: KrakenColors.accentDim,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: KrakenColors.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: KrakenSpacing.s4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(widget.recording.title, style: KrakenText.bodyLg()),
                                      Text(
                                        '${_formatPos(_playerPosition)} / ${_formatPos(_playerDuration)}',
                                        style: KrakenText.bodySm(color: KrakenColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: KrakenSpacing.s2),
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                activeTrackColor: KrakenColors.accent,
                                inactiveTrackColor: KrakenColors.border,
                                thumbColor: KrakenColors.accent,
                              ),
                              child: Slider(
                                min: 0,
                                max: _playerDuration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                value: _playerPosition.inMilliseconds.toDouble().clamp(0, _playerDuration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                                onChanged: (val) {
                                  _player.seek(Duration(milliseconds: val.toInt()));
                                },
                              ),
                            ),
                            // Retention policy (tappable, lives on the MP3 card)
                            const SizedBox(height: KrakenSpacing.s2),
                            Divider(color: KrakenColors.border.withValues(alpha: 0.3), height: 1),
                            const SizedBox(height: KrakenSpacing.s2),
                            GestureDetector(
                              onTap: _showRetentionPolicySheet,
                              child: Row(
                                children: [
                                  Icon(
                                    _retentionPolicyIcon(widget.recording.retentionPolicy),
                                    size: 13,
                                    color: KrakenColors.textMuted.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _retentionPolicyLabel(widget.recording.retentionPolicy),
                                    style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                      decorationColor: KrakenColors.textMuted.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: KrakenColors.textMuted.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                            // Meeting date (tappable to edit)
                            const SizedBox(height: KrakenSpacing.s2),
                            GestureDetector(
                              onTap: _showMeetingDatePicker,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 13,
                                    color: KrakenColors.textMuted.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Meeting: ${_formatDate(_meetingDate)}',
                                    style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                      decorationColor: KrakenColors.textMuted.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  if (_meetingDate.year != widget.recording.createdAt.year ||
                                      _meetingDate.month != widget.recording.createdAt.month ||
                                      _meetingDate.day != widget.recording.createdAt.day) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '(Recorded ${_formatDate(widget.recording.createdAt)})',
                                      style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(fontSize: 10),
                                    ),
                                  ],
                                  const Spacer(),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: KrakenColors.textMuted.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: KrakenSpacing.s6),
                      if (_summaryJson == null && !_isGeneratingSummary)
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _generateSummary,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Generate AI Summary'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: KrakenColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: KrakenSpacing.s6, vertical: KrakenSpacing.s3),
                            ),
                          ),
                        )
                      else if (_isGeneratingSummary || _summaryJson != null)
                        _buildSummaryBlock(),

                      const SizedBox(height: KrakenSpacing.s6),
                      Text('Transcript', style: KrakenText.displayMd()),
                      const SizedBox(height: KrakenSpacing.s3),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(KrakenSpacing.s4),
                        decoration: BoxDecoration(
                          color: KrakenColors.surface,
                          borderRadius: BorderRadius.circular(KrakenRadius.lg),
                          border: Border.all(color: KrakenColors.border),
                        ),
                        child: SelectableText(
                          _transcriptText!,
                          style: KrakenText.bodyLg().copyWith(height: 1.6),
                        ),
                      ),
                      const SizedBox(height: KrakenSpacing.s8),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryBlock() {
    if (_isGeneratingSummary) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        decoration: BoxDecoration(
          color: KrakenColors.surfaceElevated,
          borderRadius: BorderRadius.circular(KrakenRadius.lg),
          border: Border.all(color: KrakenColors.accent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: KrakenColors.accent),
                ),
                const SizedBox(width: KrakenSpacing.s3),
                Text('Gemma is thinking...', style: KrakenText.bodyMd(color: KrakenColors.accent)),
              ],
            ),
            const SizedBox(height: KrakenSpacing.s4),
            // Show a pulsing placeholder instead of raw JSON
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Opacity(
                opacity: _pulseAnimation.value,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12, width: double.infinity,
                      decoration: BoxDecoration(
                        color: KrakenColors.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12, width: 200,
                      decoration: BoxDecoration(
                        color: KrakenColors.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12, width: 260,
                      decoration: BoxDecoration(
                        color: KrakenColors.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Try to parse the saved summary JSON
    Map<String, dynamic>? parsed;
    try {
      String raw = _summaryJson!.trim();
      // Strip markdown code blocks if the LLM leaked them
      if (raw.startsWith('```')) {
        final lines = raw.split('\n');
        if (lines.length > 2) {
          raw = lines.sublist(1, lines.length - (lines.last.trim().startsWith('```') ? 1 : 0)).join('\n').trim();
        }
      }
      // Try to extract JSON object from mixed text output
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (jsonMatch != null) {
        parsed = jsonDecode(jsonMatch.group(0)!);
      } else {
        parsed = jsonDecode(raw);
      }
    } catch (e) {
      // Fallback if parsing fails
    }

    if (parsed == null) {
      // Fallback: display as clean plain text, stripping code artifacts
      String cleanText = _summaryJson!
        .replaceAll(RegExp(r'```\w*\n?'), '')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .trim();
      
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        decoration: BoxDecoration(
          color: KrakenColors.surfaceElevated,
          borderRadius: BorderRadius.circular(KrakenRadius.lg),
          border: Border.all(color: KrakenColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: KrakenColors.accent),
                const SizedBox(width: KrakenSpacing.s3),
                Text('AI Summary', style: KrakenText.displayMd()),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: KrakenColors.accent, size: 20),
                  tooltip: 'Regenerate',
                  onPressed: () {
                    setState(() => _summaryJson = null);
                    _generateSummary();
                  },
                ),
              ],
            ),
            const SizedBox(height: KrakenSpacing.s3),
            SelectableText(cleanText, style: KrakenText.bodyLg().copyWith(height: 1.6)),
          ],
        ),
      );
    }

    // Support both old format ("summary") and new format ("tldr")
    final tldr = _cleanSummaryText((parsed['tldr'] ?? parsed['summary'] ?? 'No summary available.') as String);
    final keyPoints = ((parsed['key_points'] as List<dynamic>?) ?? []).map((e) => _cleanSummaryText(e.toString())).toList();
    final decisions = ((parsed['decisions'] as List<dynamic>?) ?? []).map((e) => _cleanSummaryText(e.toString())).toList();
    final actions = ((parsed['action_items'] as List<dynamic>?) ?? []).map((e) => _cleanSummaryText(e.toString())).toList();
    final openQuestions = ((parsed['open_questions'] as List<dynamic>?) ?? []).map((e) => _cleanSummaryText(e.toString())).toList();

    Widget buildSection(String title, IconData icon, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: KrakenSpacing.s6),
          Row(
            children: [
              Icon(icon, size: 16, color: KrakenColors.accent),
              const SizedBox(width: 6),
              Text(title, style: KrakenText.displayMd()),
            ],
          ),
          const SizedBox(height: KrakenSpacing.s2),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: KrakenSpacing.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 8),
                  child: Icon(Icons.circle, size: 6, color: KrakenColors.accent),
                ),
                Expanded(child: SelectableText(item.toString(), style: KrakenText.bodyLg().copyWith(height: 1.6))),
              ],
            ),
          )),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KrakenSpacing.s4),
      decoration: BoxDecoration(
        color: KrakenColors.surfaceElevated,
        borderRadius: BorderRadius.circular(KrakenRadius.lg),
        border: Border.all(color: KrakenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with action buttons
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: KrakenColors.accent),
              const SizedBox(width: KrakenSpacing.s3),
              Expanded(child: Text('AI Summary', style: KrakenText.displayMd())),
              IconButton(
                icon: const Icon(Icons.tune, color: KrakenColors.accent, size: 20),
                tooltip: 'Refine Summary',
                onPressed: _showRefineDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: KrakenColors.accent, size: 20),
                tooltip: 'Regenerate Summary',
                onPressed: () {
                  setState(() => _summaryJson = null);
                  _generateSummary();
                },
              ),
            ],
          ),
          // Version indicator
          if (_viewingVersionIndex >= 0)
            Padding(
              padding: const EdgeInsets.only(bottom: KrakenSpacing.s2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KrakenColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(KrakenRadius.sm),
                ),
                child: Text(
                  'Viewing previous version',
                  style: KrakenText.bodySm(color: KrakenColors.accent).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          const SizedBox(height: KrakenSpacing.s3),
          // Summary
          Text('Summary', style: KrakenText.displayMd().copyWith(fontSize: 13, color: KrakenColors.accent)),
          const SizedBox(height: KrakenSpacing.s2),
          SelectableText(tldr, style: KrakenText.bodyLg().copyWith(height: 1.6)),
          // Sections
          buildSection('Key Points', Icons.lightbulb_outline, keyPoints),
          buildSection('Decisions', Icons.gavel, decisions),
          buildSection('Action Items', Icons.check_circle_outline, actions),
          buildSection('Open Questions', Icons.help_outline, openQuestions),
          // Version history navigation
          if (_summaryVersions.isNotEmpty) ...[
            const SizedBox(height: KrakenSpacing.s6),
            const Divider(color: KrakenColors.border),
            const SizedBox(height: KrakenSpacing.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: KrakenColors.textMuted),
                  onPressed: _viewingVersionIndex < _summaryVersions.length - 1
                    ? () {
                        final newIdx = _viewingVersionIndex + 1;
                        setState(() {
                          _viewingVersionIndex = newIdx;
                          _summaryJson = _summaryVersions[newIdx]['summary_json'] as String;
                        });
                      }
                    : null,
                ),
                Text(
                  _viewingVersionIndex == -1
                    ? 'Current (${_summaryVersions.length} previous)'
                    : 'Version ${_summaryVersions.length - _viewingVersionIndex} of ${_summaryVersions.length}',
                  style: KrakenText.bodySm(color: KrakenColors.textMuted),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: KrakenColors.textMuted),
                  onPressed: _viewingVersionIndex > -1
                    ? () async {
                        final newIdx = _viewingVersionIndex - 1;
                        if (newIdx == -1) {
                          // Go back to current
                          final current = await _folderRepo.getSummaryJson(widget.recording.audioPath);
                          if (mounted) {
                            setState(() {
                              _viewingVersionIndex = -1;
                              _summaryJson = current;
                            });
                          }
                        } else {
                          setState(() {
                            _viewingVersionIndex = newIdx;
                            _summaryJson = _summaryVersions[newIdx]['summary_json'] as String;
                          });
                        }
                      }
                    : null,
                ),
              ],
            ),
            if (_viewingVersionIndex >= 0)
              Center(
                child: TextButton(
                  onPressed: () async {
                    final versionJson = _summaryVersions[_viewingVersionIndex]['summary_json'] as String;
                    await _folderRepo.restoreSummaryVersion(widget.recording.audioPath, versionJson);
                    await _loadTranscript();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Previous version restored as current.')),
                      );
                    }
                  },
                  child: Text('Restore This Version', style: KrakenText.bodySm(color: KrakenColors.accent)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ─── Retention Policy helpers ────────────────────────────────────────────

  IconData _retentionPolicyIcon(String policy) {
    switch (policy) {
      case 'delete_after_transcription':
        return Icons.auto_delete_outlined;
      case 'keep_forever':
        return Icons.all_inclusive;
      case '90_day':
      default:
        return Icons.timer_outlined;
    }
  }

  String _retentionPolicyLabel(String policy) {
    switch (policy) {
      case 'delete_after_transcription':
        return 'Delete after transcription';
      case 'keep_forever':
        return 'Keep forever';
      case '90_day':
      default:
        return '90-day retention';
    }
  }

  void _showRetentionPolicySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(KrakenSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audio Retention', style: KrakenText.displayMd()),
              const SizedBox(height: 4),
              Text(
                'Choose how long to keep this audio file. Transcripts and summaries are always preserved.',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
              ),
              const SizedBox(height: KrakenSpacing.s4),
              _retentionOption(
                ctx,
                policy: 'delete_after_transcription',
                icon: Icons.auto_delete,
                label: 'Delete after transcription',
                description: 'Audio removed once transcription completes. Saves the most space.',
              ),
              _retentionOption(
                ctx,
                policy: '90_day',
                icon: Icons.event,
                label: '90-day retention',
                description: 'Audio kept for 90 days, then automatically removed.',
              ),
              _retentionOption(
                ctx,
                policy: 'keep_forever',
                icon: Icons.all_inclusive,
                label: 'Keep until I delete',
                description: 'Audio preserved indefinitely. Still subject to storage cap.',
              ),
              const SizedBox(height: KrakenSpacing.s4),
            ],
          ),
        );
      },
    );
  }

  Widget _retentionOption(
    BuildContext ctx, {
    required String policy,
    required IconData icon,
    required String label,
    required String description,
  }) {
    final isActive = widget.recording.retentionPolicy == policy;
    return ListTile(
      leading: Icon(icon, color: isActive ? KrakenColors.accent : KrakenColors.textMuted),
      title: Text(label, style: KrakenText.bodyMd(
        color: isActive ? KrakenColors.accent : KrakenColors.textPrimary,
      )),
      subtitle: Text(description, style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(fontSize: 11)),
      trailing: isActive ? const Icon(Icons.check, color: KrakenColors.accent, size: 18) : null,
      onTap: () async {
        Navigator.pop(ctx);
        await _folderRepo.setRetentionPolicy(widget.recording.id, policy);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Retention set to: $label')),
          );
          setState(() {}); // Refresh UI
        }
      },
    );
  }
}
