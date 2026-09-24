import 'package:krak_en_voice/inference/model_file_downloader.dart';
// ignore_for_file: unused_element, use_build_context_synchronously
import 'dart:convert';
import 'dart:async';
import '../widgets/summary_draft_card.dart';
import '../widgets/summary_progress_panel.dart';
import '../kernel/inference/summary_progress.dart';
import '../kernel/inference/drafted_summary_stream.dart';
import '../kernel/inference/summary_context.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/design/tokens.dart';
import 'package:krak_en_voice/inference/model_manager.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/data/export_service.dart';
import 'package:krak_en_voice/data/whisper_languages.dart';
import 'package:krak_en_voice/data/summary_prompt.dart';
import 'package:krak_en_voice/kernel/inference/summary_generation_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:krak_en_voice/app/feature_flags.dart';

class TranscriptScreen extends StatefulWidget {
  final Recording recording;

  const TranscriptScreen({super.key, required this.recording});

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

/// Simple data holder for a chunk of transcript text attributed to a speaker.
class _SpeakerChunk {
  final int speaker;
  final String text;
  final double startSeconds;
  const _SpeakerChunk({
    required this.speaker,
    required this.text,
    required this.startSeconds,
  });
}

/// Mutable version of [_SpeakerChunk] that supports per-instance label
/// overrides and structural editing (moving words across speaker boundaries).
class _EditableSpeakerChunk {
  int speaker;

  /// Per-instance label override. `null` means use the global speaker label.
  String? labelOverride;
  String text;
  double startSeconds;

  _EditableSpeakerChunk({
    required this.speaker,
    required this.text,
    required this.startSeconds,
    this.labelOverride,
  });

  _EditableSpeakerChunk.fromChunk(_SpeakerChunk c)
    : speaker = c.speaker,
      text = c.text,
      startSeconds = c.startSeconds,
      labelOverride = null;
}

class _TranscriptScreenState extends State<TranscriptScreen>
    with SingleTickerProviderStateMixin {
  late final FolderRepository _folderRepo;
  String? _transcriptText;
  String? _summaryJson;
  bool _isLoading = true;

  bool _isGeneratingSummary = false;
  String _summaryPhase = ''; // Current phase label for progress UI
  DateTime? _summaryStartedAt;
  double _summaryProgress = 0.0; // 0.0 to 1.0
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
  late String _retentionPolicy;
  String _summaryStyle = 'concise';
  bool _userManuallyRenamed = false;

  // H3-55: Inline title editing
  bool _isEditingTitle = false;
  late TextEditingController _titleEditController;
  final FocusNode _titleFocusNode = FocusNode();

  // H1-30: Inline transcript editing
  bool _isEditingTranscript = false;
  late TextEditingController _transcriptEditController;
  bool _isUserCorrected = false;

  // H1-32: Search within transcript
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Break sensitivity slider (inline in transcript view)
  bool _showBreakSlider = false;
  double _breakThreshold = 1.5;

  // 2A-07: Language chip display
  String _transcriptionLanguage = '';

  // ─── Speaker diarization state ─────────────────────────────────────────────
  List<DiarizationSegment>? _diarizationSegments;
  List<WhisperSegment>? _transcriptSegments;
  Map<int, String> _speakerLabels = {};
  DiarizationConfig? _currentDiarizationConfig;
  bool _isReclustering = false;
  bool _isDiarizing = false;

  /// Diarization clustering threshold — synced with Settings.
  /// Higher = fewer speakers (merge), lower = more speakers (split).
  double _diarizationThreshold = 0.75;

  /// User-specified expected speaker count (null = auto-detect).
  int? _expectedSpeakers;

  // ─── Editable speaker chunks (structural editing) ──────────────────────────
  /// Populated when the diarized transcript is first rendered, then mutated
  /// in-place by per-instance rename, move-up / move-down, and split/merge.
  List<_EditableSpeakerChunk>? _editableChunks;

  /// True while the user is in per-chunk structural editing mode.
  bool _isEditingDiarizedTranscript = false;

  /// Curated palette for speaker attribution chips.
  /// Ordered to maximise visual distinction across 2-4 speakers.
  static const List<Color> _speakerColors = [
    Color(0xFF8B7DFF), // indigo/accent
    Color(0xFF4ECDC4), // teal
    Color(0xFFFF6B6B), // coral
    Color(0xFFFFD93D), // amber
    Color(0xFF6BCB77), // green
    Color(0xFFFF9A3C), // orange
    Color(0xFF4D96FF), // blue
    Color(0xFFE78EA9), // rose
  ];

  // Dynamic transcription failure tracking
  bool _transcriptionFailed = false;

  // Entitlement tier — diarization is paid-only
  bool _isPaidUser = false;

  // Background summary generation service
  final SummaryGenerationService _summaryService = SummaryGenerationService();

  @override
  void initState() {
    super.initState();
    _folderRepo = FolderRepository(context.read<VaultService>());
    _isPaidUser = RepositoryProvider.of<EntitlementService>(
      context,
      listen: false,
    ).isUnlocked('com.kraken.meeting_notes');
    _currentTitle = widget.recording.title;
    _meetingDate = widget.recording.meetingDate;
    _retentionPolicy = widget.recording.retentionPolicy;

    // Load summary style preference
    _loadSummaryStyle();
    _loadDiarizationThreshold();
    _loadBreakThreshold();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadTranscript();
    _initPlayer();
    _startTranscriptionPolling();
    // H3-06: Track last access for LRU retention ordering
    _folderRepo.touchLastAccess(widget.recording.id);

    // H3-55: Inline title editing setup
    _titleEditController = TextEditingController(text: _currentTitle);
    _titleFocusNode.addListener(_onTitleFocusChanged);

    // H1-30: Transcript editing setup
    _transcriptEditController = TextEditingController();
    _folderRepo.isTranscriptUserCorrected(widget.recording.audioPath).then((v) {
      if (mounted) setState(() => _isUserCorrected = v);
    });

    // Sync with background summary service if it's already running for this recording
    _summaryService.isGenerating.addListener(_onSummaryServiceChanged);
    _summaryService.progress.addListener(_onSummaryServiceChanged);
    _summaryService.phase.addListener(_onSummaryServiceChanged);
    _summaryService.streamingText.addListener(_onSummaryServiceChanged);
    _syncFromSummaryService();
  }

  void _startTranscriptionPolling() {
    _checkTranscriptionStatus();
    _transcriptionPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkTranscriptionStatus(),
    );
  }

  void _checkTranscriptionStatus() {
    final jobs = TranscriptionEngine().activeJobs.value;
    final isActive = jobs.any(
      (j) =>
          j.audioPath == widget.recording.audioPath &&
          (j.status == TranscriptionStatus.processing ||
              j.status == TranscriptionStatus.pending),
    );
    // Detect if the job just failed
    final hasFailed = jobs.any(
      (j) =>
          j.audioPath == widget.recording.audioPath &&
          j.status == TranscriptionStatus.failed,
    );
    if (mounted) {
      if (isActive != _isActivelyTranscribing ||
          hasFailed != _transcriptionFailed) {
        setState(() {
          _isActivelyTranscribing = isActive;
          _transcriptionFailed = hasFailed;
        });
      }
      // If it just finished (and didn't fail), reload the transcript
      if (!isActive && !hasFailed && _transcriptText == null) {
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
    // Remove listeners but do NOT cancel the service — summary keeps generating
    _summaryService.isGenerating.removeListener(_onSummaryServiceChanged);
    _summaryService.progress.removeListener(_onSummaryServiceChanged);
    _summaryService.phase.removeListener(_onSummaryServiceChanged);
    _summaryService.streamingText.removeListener(_onSummaryServiceChanged);
    _player.dispose();
    _pulseController.dispose();
    _transcriptionPollTimer?.cancel();
    _titleEditController.dispose();
    _titleFocusNode.removeListener(_onTitleFocusChanged);
    _titleFocusNode.dispose();
    _transcriptEditController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Sync widget state from the background summary service.
  /// Called on initState and whenever service state changes.
  void _onSummaryServiceChanged() {
    if (!mounted) return;
    _syncFromSummaryService();
  }

  void _syncFromSummaryService() {
    if (_summaryService.activeAudioPath != widget.recording.audioPath) return;

    if (_summaryService.isGenerating.value) {
      setState(() {
        _isGeneratingSummary = true;
        _summaryProgress = _summaryService.progress.value;
        _summaryStartedAt = _summaryService.startedAt;
        _summaryPhase = _summaryService.phase.value;
      });
    } else if (_summaryService.completedSummaryJson != null) {
      // Service just finished — pick up the result
      final json = _summaryService.completedSummaryJson!;
      setState(() {
        _summaryJson = json;
        _isGeneratingSummary = false;
        _viewingVersionIndex = -1;
      });
      // Reload versions from DB
      _folderRepo.getSummaryVersions(widget.recording.audioPath).then((v) {
        if (mounted) setState(() => _summaryVersions = v);
      });
      _generateAIName(json);
      _suggestFolderAfterSummary();
    } else if (_summaryService.errorMessage != null && mounted) {
      setState(() {
        _isGeneratingSummary = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_summaryService.errorMessage!)));
    }
  }

  // H3-55: Commit inline title edit when focus is lost
  void _onTitleFocusChanged() {
    if (!_titleFocusNode.hasFocus && _isEditingTitle) {
      _commitInlineRename();
    }
  }

  void _startInlineRename() {
    setState(() {
      _isEditingTitle = true;
      _titleEditController.text = _currentTitle;
    });
    // Schedule focus request for next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNode.requestFocus();
      _titleEditController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleEditController.text.length,
      );
    });
  }

  void _commitInlineRename() {
    final newName = _titleEditController.text
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    setState(() => _isEditingTitle = false);

    if (newName.isNotEmpty && newName != _currentTitle) {
      _folderRepo.renameRecording(widget.recording.id, newName);
      setState(() {
        _currentTitle = newName;
        _userManuallyRenamed = true;
      });
    }
  }

  void _cancelInlineRename() {
    setState(() {
      _isEditingTitle = false;
      _titleEditController.text = _currentTitle;
    });
  }

  // ─── H1-30: Inline transcript editing ──────────────────────────────────────

  void _startEditingTranscript() {
    _transcriptEditController.text = _transcriptText ?? '';
    setState(() => _isEditingTranscript = true);
  }

  Future<void> _saveTranscriptEdits() async {
    final newText = _transcriptEditController.text.trim();
    if (newText.isEmpty) return;

    await _folderRepo.updateTranscriptionText(
      widget.recording.audioPath,
      newText,
    );
    setState(() {
      _transcriptText = newText;
      _isEditingTranscript = false;
      _isUserCorrected = true;
      // Invalidate cached Whisper segments so the diarized view
      // re-renders from the edited raw text instead of stale segments.
      _transcriptSegments = null;
      _editableChunks = null;
    });

    // 2B-49: Suggest summary regeneration after transcript edits
    if (mounted && _summaryJson != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Transcript updated. Regenerate summary to reflect changes?',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Regenerate',
            textColor: KrakenColors.accent,
            onPressed: () => _generateSummary(),
          ),
        ),
      );
    }
  }

  void _cancelTranscriptEdits() {
    setState(() => _isEditingTranscript = false);
  }

  // ─── Re-format transcript breaks ────────────────────────────────────────────

  Future<void> _reformatTranscriptBreaks() async {
    // Load stored segments
    final segments = await _folderRepo.getTranscriptionSegments(
      widget.recording.audioPath,
    );
    if (segments == null || segments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No segment data available — cannot re-format.'),
          ),
        );
      }
      return;
    }

    // Read current break threshold
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    final threshold = await prefs.getBreakThreshold();

    // Re-format
    final newText = TranscriptionEngine.reformatSegments(
      segments,
      breakThreshold: threshold,
    );
    if (newText == null) return;

    // Save to DB
    await _folderRepo.updateTranscriptionText(
      widget.recording.audioPath,
      newText,
    );

    if (mounted) {
      setState(() {
        _transcriptText = newText;
        // Invalidate cached segments so diarized view re-renders
        _transcriptSegments = null;
        _editableChunks = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transcript re-formatted with ${threshold.toStringAsFixed(1)}s break threshold.',
          ),
        ),
      );
    }
  }

  // ─── H1-32: Search within transcript ───────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  // H1-33: Parse timestamp from transcript line and seek audio
  void _seekToTimestamp(String timestampStr) {
    // Parse formats: [00:05], [01:23], [1:23:45], etc.
    final parts = timestampStr.replaceAll(RegExp(r'[\[\]]'), '').split(':');
    int totalSeconds = 0;
    if (parts.length == 2) {
      totalSeconds =
          (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      totalSeconds =
          (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    if (_isPlayerReady && totalSeconds > 0) {
      _player.seek(Duration(seconds: totalSeconds));
      if (!_isPlaying) _player.play();
    }
  }

  Future<void> _loadTranscript() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final text = await _folderRepo.getTranscriptionText(
      widget.recording.audioPath,
    );
    final summary = await _folderRepo.getSummaryJson(
      widget.recording.audioPath,
    );
    final versions = await _folderRepo.getSummaryVersions(
      widget.recording.audioPath,
    );
    // 2A-07: Load transcription language
    String lang = '';
    try {
      if (!mounted) return;
      final vault = context.read<VaultService>();
      final jobResult = await vault.db.query(
        'transcription_jobs',
        columns: ['language'],
        where: 'audio_path = ?',
        whereArgs: [widget.recording.audioPath],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (jobResult.isNotEmpty) {
        lang = jobResult.first['language'] as String? ?? 'en';
      }
    } catch (_) {}

    // ── Load diarization data ──
    List<DiarizationSegment>? segments;
    Map<int, String> labels = {};
    DiarizationConfig? diarConfig;
    try {
      segments = await _folderRepo.getDiarizationSegments(widget.recording.id);
      if (segments != null && segments.isNotEmpty) {
        labels = await _folderRepo.getSpeakerLabels(widget.recording.id);
        diarConfig = await _folderRepo.getDiarizationConfig(
          widget.recording.id,
        );
      }
    } catch (_) {}

    // ── Load Whisper per-segment timestamps (for accurate speaker alignment) ──
    List<WhisperSegment>? transcriptSegments;
    try {
      transcriptSegments = await _folderRepo.getTranscriptionSegments(
        widget.recording.audioPath,
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _transcriptText = text;
        _summaryJson = summary;
        _summaryVersions = versions;
        _viewingVersionIndex = -1; // Reset to current
        _transcriptionLanguage = lang;
        _diarizationSegments = segments;
        _transcriptSegments = transcriptSegments;
        _speakerLabels = labels;
        _currentDiarizationConfig = diarConfig;
        _editableChunks = null; // Force rebuild from fresh alignment
        _isEditingDiarizedTranscript = false;
        _isLoading = false;
      });
    }
  }

  // ─── Manual speaker detection ─────────────────────────────────────────────

  /// Show upgrade prompt when free user tries to access speaker detection.
  void _showDiarizationUpgradePrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Row(
          children: [
            Icon(Icons.record_voice_over, color: KrakenColors.accent, size: 22),
            const SizedBox(width: 8),
            Text('Speaker Detection', style: KrakenText.displayMd()),
          ],
        ),
        content: Text(
          'Speaker diarization identifies who said what in your recordings using on-device AI.\n\nUpgrade to the full version to unlock this feature.',
          style: KrakenText.bodyMd(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Maybe Later',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final entitlements = RepositoryProvider.of<EntitlementService>(
                context,
                listen: false,
              );
              final success = await entitlements.purchaseFullUnlock();
              if (!success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Purchase could not be started. Please try again.',
                    ),
                  ),
                );
              }
              entitlements.changes.first.then((_) {
                if (mounted) {
                  setState(() {
                    _isPaidUser = entitlements.isUnlocked(
                      'com.kraken.meeting_notes',
                    );
                  });
                }
              });
            },
            child: const Text('Upgrade — \$19.95'),
          ),
        ],
      ),
    );
  }

  Future<void> _runManualDiarization() async {
    if (_isDiarizing) return;

    // Gate: diarization is a paid-only feature
    if (!_isPaidUser) {
      _showDiarizationUpgradePrompt();
      return;
    }

    // Capture everything we need from context BEFORE any async gap.
    // After an await, the widget may have been disposed and context is invalid.
    final vault = context.read<VaultService>();
    final recordingId = widget.recording.id;
    final audioPath = widget.recording.audioPath;
    final durationMin = widget.recording.durationMs / 60000;

    // For long recordings (>45 min), warn the user about memory usage.
    // The native pipeline allocates ~400MB+ and concurrent operations
    // can trigger the Android Low-Memory Killer.
    if (durationMin > 45 && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KrakenColors.surfaceElevated,
          title: Text('Large recording', style: KrakenText.displayMd()),
          content: Text(
            'Speaker detection for a ${durationMin.toStringAsFixed(0)}-minute '
            'recording uses significant memory. While it runs:\n\n'
            '• Stay on this screen\n'
            '• Avoid switching apps\n'
            '• Don\'t delete or import files\n\n'
            'This may take several minutes.',
            style: KrakenText.bodyMd(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: KrakenText.bodySm()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: KrakenColors.accent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isDiarizing = true);
    final engine = TranscriptionEngine();
    engine.isDiarizing.value = true;

    try {
      // Release the Whisper model to free GPU/CPU memory before the
      // diarization pipeline loads its own native models (~200MB).
      try {
        await TranscriptionEngine().releaseWhisper();
      } catch (_) {}

      final diarizer = NemoDiarizer(
        downloadFile: ModelFileDownloader().download,
      );

      // Ensure models are available
      if (!await diarizer.hasModels()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Downloading speaker detection models...'),
            ),
          );
        }
        await diarizer.ensureModelsDownloaded();
      }

      // Check if diarization already exists
      final existing = await vault.db.query(
        'diarization_results',
        where: 'recording_id = ?',
        whereArgs: [recordingId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        if (mounted) {
          await _loadTranscript();
          setState(() => _isDiarizing = false);
        }
        return;
      }

      // Construct embedding cache path
      final audioDir = audioPath.substring(0, audioPath.lastIndexOf('/'));
      final embeddingsPath = '$audioDir/$recordingId.embeddings';

      // This is the long-running call that can outlive the widget.
      final result = await diarizer.processRecording(
        audioPath,
        config: DiarizationConfig(
          threshold: _diarizationThreshold,
          numSpeakers: _expectedSpeakers,
        ),
        embeddingsCachePath: embeddingsPath,
      );

      // Persist result — do this even if the widget is disposed,
      // so the data is available when the user comes back.
      final segmentsJson = result.segments
          .map(
            (s) => {
              'speaker': s.speaker,
              'start_s': s.startSeconds,
              'end_s': s.endSeconds,
            },
          )
          .toList();
      final now = DateTime.now().millisecondsSinceEpoch;

      await vault.db.insert('diarization_results', {
        'recording_id': recordingId,
        'threshold': result.config.threshold,
        'min_duration': result.config.minDuration,
        'speaker_count': result.speakerCount,
        'segments_json': jsonEncode(segmentsJson),
        'embeddings_path': result.embeddingsPath,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Generate default speaker labels
      final speakerIndices = result.segments.map((s) => s.speaker).toSet();
      for (final idx in speakerIndices) {
        await vault.db.insert('speaker_labels', {
          'id': '${recordingId}_$idx',
          'recording_id': recordingId,
          'speaker_index': idx,
          'display_name': 'Speaker ${idx + 1}',
          'is_user_renamed': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      debugPrint(
        '[ManualDiarize] ✅ $recordingId: ${result.speakerCount} speakers',
      );

      // Only update UI if still on screen
      if (mounted) {
        await _loadTranscript();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Detected ${result.speakerCount} speakers.')),
        );
      }
    } catch (e) {
      debugPrint('[ManualDiarize] ❌ Failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Speaker detection failed: ${e.toString().split('\n').first}',
            ),
          ),
        );
      }
    } finally {
      engine.isDiarizing.value = false;
      if (mounted) setState(() => _isDiarizing = false);
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
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.accent,
            ),
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
        final keyPoints =
            (parsed['key_points'] as List<dynamic>?)?.take(3).join(', ') ?? '';
        summaryContext = '$tldr\nKey topics: $keyPoints';
      } catch (_) {}

      if (summaryContext.length > 500) {
        summaryContext = summaryContext.substring(0, 500);
      }

      final prompt =
          '''You are naming a meeting recording. Based on this summary, produce a SHORT, specific title (3-8 words). Include key topic and context.

Good examples: "Q2 Budget Review with Finance", "Sprint 14 Retro", "Client Onboarding - Acme Corp", "Weekly 1:1 with Sarah"
Bad examples: "Meeting", "Recording 4/23", "Important Discussion", "Meeting about various topics"

Summary:
$summaryContext

Title:''';

      final buffer = StringBuffer();
      await for (final token in inference.generateStream(
        prompt,
        maxTokens: 32,
      )) {
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
          suggestedName.toLowerCase() == 'recording') {
        return;
      }

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

  // H3-51, H3-52: Suggest folder based on transcript + summary content
  void _suggestFolderAfterSummary() async {
    try {
      final suggested = await _folderRepo.suggestFolder(
        _currentTitle,
        _transcriptText?.substring(
          0,
          (_transcriptText?.length ?? 0).clamp(0, 300),
        ),
      );
      if (suggested == null || !mounted) return;

      // Only suggest if the recording isn't already in the suggested folder
      if (suggested.id == widget.recording.folderId) return;

      // Clear any lingering snackbars before showing the suggestion
      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Move to "${suggested.name}"?'),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          closeIconColor: KrakenColors.textMuted,
          action: SnackBarAction(
            label: 'Move',
            textColor: KrakenColors.accent,
            onPressed: () async {
              await _folderRepo.moveRecording(
                widget.recording.id,
                suggested.id,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Moved to ${suggested.name}')),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Folder Suggest] Failed: $e');
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
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.accent,
            ),
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

  /// Detects garbled/repetitive output from a cold LLM that may technically
  /// parse as sections but is nonsensical. Returns true if the output fails
  /// quality checks.
  bool _isGarbledOutput(String text) {
    if (text.trim().length < 50) return true;

    // Check for excessive word repetition — garbled output repeats phrases
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    if (words.length > 20) {
      final uniqueWords = words.toSet();
      final uniqueRatio = uniqueWords.length / words.length;
      // Healthy prose has >50% unique words; garbled output is much lower
      if (uniqueRatio < 0.35) {
        debugPrint(
          '[Kraken AI] Garbled: unique word ratio ${(uniqueRatio * 100).toInt()}% (need >35%)',
        );
        return true;
      }
    }

    // Check for words smashed together without spaces (e.g., "transcriptionDEC processISIONS")
    final smashedPattern = RegExp(r'[a-z][A-Z]{2,}');
    final smashedMatches = smashedPattern.allMatches(text).length;
    if (smashedMatches > 3) {
      debugPrint(
        '[Kraken AI] Garbled: $smashedMatches smashed-case patterns detected',
      );
      return true;
    }

    return false;
  }

  /// Parses plain-text section output from the LLM into our summary JSON format.
  /// Expects headers like "TLDR:", "KEY POINTS:", etc.
  String? _parseSectionsToJson(String text) {
    // Strip any preamble before the first actual section header.
    // The model sometimes echoes prompt instructions before starting.
    final firstHeader = RegExp(r'SUMMARY\s*:|TLDR\s*:', caseSensitive: false);
    final headerMatch = firstHeader.firstMatch(text);
    final effective = headerMatch != null
        ? text.substring(headerMatch.start)
        : text;

    final cleaned = _cleanSummaryText(
      effective.replaceAll(RegExp(r'\\[0-9]+'), ''), // strip \1 \2 artifacts
    );

    // First, try to parse as JSON directly (model may still produce JSON sometimes)
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      if (parsed.containsKey('tldr') ||
          parsed.containsKey('summary') ||
          parsed.containsKey('key_points')) {
        // Clean all values
        final sanitized = <String, dynamic>{};
        for (final entry in parsed.entries) {
          if (entry.value is String) {
            sanitized[entry.key] = _cleanSummaryText(entry.value as String);
          } else if (entry.value is List) {
            sanitized[entry.key] = (entry.value as List)
                .map((e) => _cleanSummaryText(e.toString()))
                .toList();
          } else {
            sanitized[entry.key] = entry.value;
          }
        }
        return jsonEncode(sanitized);
      }
    } catch (_) {}

    // Also try extracting JSON from mixed text
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
    if (jsonMatch != null) {
      try {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        if (parsed.containsKey('tldr') ||
            parsed.containsKey('summary') ||
            parsed.containsKey('key_points')) {
          final sanitized = <String, dynamic>{};
          for (final entry in parsed.entries) {
            if (entry.value is String) {
              sanitized[entry.key] = _cleanSummaryText(entry.value as String);
            } else if (entry.value is List) {
              sanitized[entry.key] = (entry.value as List)
                  .map((e) => _cleanSummaryText(e.toString()))
                  .toList();
            } else {
              sanitized[entry.key] = entry.value;
            }
          }
          return jsonEncode(sanitized);
        }
      } catch (_) {}
    }

    // Parse plain-text section format
    // Build flexible regex for a header — handles optional colon, markdown bold, etc.
    String flexHeader(String header) {
      // Strip trailing colon for the base name, e.g. "TLDR:" -> "TLDR"
      final base = header.replaceAll(':', '').trim();
      // Match optional markdown bold (**), the header text, optional colon, case-insensitive
      return r'(?:\*{0,2})' + RegExp.escape(base) + r'(?:\*{0,2})\s*:?';
    }

    String extractSection(
      String text,
      String header,
      List<String> nextHeaders,
    ) {
      final headerPattern = RegExp(flexHeader(header), caseSensitive: false);
      final match = headerPattern.firstMatch(text);
      if (match == null) return '';

      int start = match.end;
      int end = text.length;
      for (final next in nextHeaders) {
        final nextMatch = RegExp(
          flexHeader(next),
          caseSensitive: false,
        ).firstMatch(text.substring(start));
        if (nextMatch != null) {
          end = start + nextMatch.start;
          break;
        }
      }
      return text.substring(start, end).trim();
    }

    List<String> splitLines(String section) {
      return section
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^[\s\-\*\d\.]+'), '').trim())
          .where(
            (l) =>
                l.isNotEmpty &&
                l.toLowerCase() != 'none' &&
                l.toLowerCase() != 'n/a',
          )
          .map((l) => _cleanSummaryText(l))
          .toList();
    }

    final headers = [
      'SUMMARY:',
      'KEY POINTS:',
      'DECISIONS:',
      'ACTION ITEMS:',
      'OPEN QUESTIONS:',
    ];

    // Try 'SUMMARY:' first (new prompt), fall back to 'TLDR:' (old summaries)
    var tldr = extractSection(text, 'SUMMARY:', headers.sublist(1));
    if (tldr.isEmpty) {
      tldr = extractSection(text, 'TLDR:', headers.sublist(1));
    }
    final keyPoints = extractSection(text, 'KEY POINTS:', headers.sublist(2));
    final decisions = extractSection(text, 'DECISIONS:', headers.sublist(3));
    final actionItems = extractSection(
      text,
      'ACTION ITEMS:',
      headers.sublist(4),
    );
    final openQuestions = extractSection(text, 'OPEN QUESTIONS:', []);

    // Must have at least a summary to be considered valid
    if (tldr.isEmpty && keyPoints.isEmpty) return null;

    final result = {
      'tldr': _cleanSummaryText(tldr.replaceAll('\n', ' ').trim()),
      'key_points': splitLines(keyPoints),
      'decisions': splitLines(decisions),
      'action_items': splitLines(actionItems),
      'open_questions': splitLines(openQuestions),
    };
    return jsonEncode(result);
  }

  Future<void> _loadSummaryStyle() async {
    final prefs = RepositoryProvider.of<PreferencesService>(
      context,
      listen: false,
    );
    final style = await prefs.getString(
      'summary_style',
      defaultValue: 'concise',
    );
    if (mounted) {
      setState(() => _summaryStyle = style);
    }
  }

  Future<void> _saveSummaryStyle(String style) async {
    final prefs = RepositoryProvider.of<PreferencesService>(
      context,
      listen: false,
    );
    await prefs.setString('summary_style', style);
  }

  Future<void> _loadDiarizationThreshold() async {
    final prefs = RepositoryProvider.of<PreferencesService>(
      context,
      listen: false,
    );
    // Prefer the new settings-screen key; fall back to the old per-screen
    // key for users upgrading from an earlier build that only stored it
    // there.
    final stored =
        (await prefs.getInt('diarization_default_threshold')) ??
        (await prefs.getInt('diarization_threshold')) ??
        75;
    final storedCount = await prefs.getInt('diarization_default_num_speakers');
    if (mounted) {
      setState(() {
        _diarizationThreshold = stored / 100.0;
        _expectedSpeakers = (storedCount == null || storedCount == 0)
            ? null
            : storedCount;
      });
    }
  }

  Future<void> _saveDiarizationThreshold(double threshold) async {
    final prefs = RepositoryProvider.of<PreferencesService>(
      context,
      listen: false,
    );
    await prefs.setInt(
      'diarization_default_threshold',
      (threshold * 100).round(),
    );
  }

  Future<void> _loadBreakThreshold() async {
    final prefs = RepositoryProvider.of<PreferencesService>(
      context,
      listen: false,
    );
    final val = await prefs.getBreakThreshold();
    if (mounted) setState(() => _breakThreshold = val.clamp(0.1, 5.0));
  }

  Future<void> _removeSpeakerLabels() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Remove speaker labels?', style: KrakenText.displayMd()),
        content: Text(
          'This will strip all speaker labels (e.g. "Speaker 1:", "Speaker 2:") from the transcript. This cannot be undone.',
          style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Strip speaker labels from transcript
    final cleaned = (_transcriptText ?? '').replaceAll(
      RegExp(r'Speaker \d+:\s*'),
      '',
    );

    // Save cleaned transcript
    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    await repo.updateTranscriptionText(widget.recording.audioPath, cleaned);

    setState(() {
      _transcriptText = cleaned;
      _speakerLabels.clear();
      _diarizationSegments = null;
      _currentDiarizationConfig = null;
      _editableChunks = null;
      _isEditingDiarizedTranscript = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Speaker labels removed.')));
    }
  }

  Future<void> _generateSummary({int attempt = 1}) async {
    // Gate on model availability — show download prompt if missing
    if (attempt == 1 && !await _checkModelAvailable()) return;

    // Capture context-dependent values BEFORE any async work
    final inference = context.read<LocalInferenceService>();
    final transcript = _transcriptText ?? '';
    final audioPath = widget.recording.audioPath;
    final recordingId = widget.recording.id;
    final langLabel = _transcriptionLanguage;

    // Set initial UI state immediately so progress shows
    setState(() {
      _isGeneratingSummary = true;
      _summaryPhase = 'Loading AI model...';
      _summaryProgress = 0.0;
    });

    // Delegate to the background service — survives widget disposal
    _summaryService.generate(
      inference: inference,
      folderRepo: _folderRepo,
      audioPath: audioPath,
      recordingId: recordingId,
      transcript: transcript,
      style: _summaryStyle,
      language: langLabel,
      attempt: attempt,
      onCompleted: (jsonResult) {
        // If the user navigated back and the widget is still live,
        // the ValueNotifier listeners will handle UI sync.
        // This callback handles post-save actions that only run once.
        debugPrint('[_generateSummary] Background generation completed.');
      },
    );
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
            hintText:
                'e.g. "Focus more on action items" or "Add participant names"',
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.accent,
            ),
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
    if (!await _checkModelAvailable()) return;

    setState(() {
      _isGeneratingSummary = true;
      _summaryStartedAt = DateTime.now();
      _summaryProgress = 0.03;
      _summaryPhase = 'Preparing refinement...';
    });

    final transcript = _transcriptText ?? '';
    final existingSummary = _summaryJson ?? '';
    final inference = context.read<LocalInferenceService>();
    final draftKey = 'audio:${widget.recording.audioPath}';
    var sectionLabel = 'Preparing source sections...';
    try {
      await inference.loadModel();
      final prompt =
          await SummaryContext(
            countTokens: inference.countTokens,
            onProgress: (section) {
              sectionLabel = section.label;
              if (mounted) {
                setState(() {
                  _summaryProgress = section.estimate;
                  _summaryPhase = sectionLabel;
                });
              }
            },
            condense: (section) async {
              final notes = StringBuffer();
              await for (final token in inference.generateStream(
                section,
                maxTokens: 768,
                autoContinue: true,
              )) {
                notes.write(token.text);
                if (mounted) {
                  setState(
                    () => _summaryPhase =
                        '$sectionLabel · ${notes.length} characters of notes written',
                  );
                }
              }
              return notes.toString();
            },
          ).prepare(
            transcript,
            (text) => SummaryPrompt.refine(
              existingSummary: existingSummary,
              instruction: instruction,
              transcript: text,
            ),
          );
      if (mounted) {
        setState(() {
          _summaryProgress = 0.80;
          _summaryPhase = 'Writing refined summary...';
        });
      }
      final output = StringBuffer();
      await for (final token in draftedSummaryStream(
        inference,
        prompt,
        drafts: _folderRepo.summaryDrafts,
        key: draftKey,
      )) {
        output.write(token.text);
        if (mounted) {
          setState(() {
            _summaryProgress = summaryWritingProgress(output.length);
            _summaryPhase =
                'Writing summary · ${output.length} characters written';
          });
        }
      }
      final jsonResult = _parseSectionsToJson(output.toString());
      if (jsonResult == null) {
        throw StateError(
          'Refine produced invalid output. The draft was saved.',
        );
      }
      if (mounted) {
        setState(() {
          _summaryProgress = 0.99;
          _summaryPhase = 'Saving summary...';
        });
      }
      await _folderRepo.saveSummaryJson(widget.recording.audioPath, jsonResult);
      await _folderRepo.summaryDrafts.clear(draftKey);
      await _folderRepo.syncActionItemsFromSummary(
        widget.recording.id,
        jsonResult,
      );
      final versions = await _folderRepo.getSummaryVersions(
        widget.recording.audioPath,
      );
      if (mounted) {
        setState(() {
          _summaryJson = jsonResult;
          _viewingVersionIndex = -1;
          _summaryVersions = versions;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refine failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingSummary = false);
    }
  }

  /// Strips code-like artifacts that small LLMs sometimes leak into summary text.
  String _cleanSummaryText(String text) {
    return text
        .replaceAll(RegExp(r'```\w*\n?'), '') // code fences
        .replaceAll('\\n', ' ') // literal \n (escaped newline)
        .replaceAll('\\t', ' ') // literal \t (escaped tab)
        .replaceAll('\\"', '"') // escaped double quotes
        .replaceAll("\\'", "'") // escaped single quotes
        .replaceAll('\\\\', '') // double backslashes
        .replaceAll(RegExp(r'\*\*'), '') // bold markdown **
        .replaceAll(RegExp(r'__'), '') // bold markdown __
        .replaceAll(RegExp(r'`([^`]*)`'), r'\1') // inline code `text`
        .replaceAll(RegExp(r'#{1,6}\s*'), '') // heading markers
        .replaceAll(
          RegExp(r'^\s*[-*•]\s*', multiLine: true),
          '',
        ) // leading bullets
        .replaceAll(
          RegExp(r'^\s*\d+\.\s*', multiLine: true),
          '',
        ) // numbered lists
        .replaceAll(RegExp(r'<[^>]+>'), '') // HTML tags
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'\1') // markdown links
        .replaceAll(RegExp(r'\s{2,}'), ' ') // collapse whitespace
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

  String _safeFileName(String title) =>
      title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');

  /// Returns transcript text enriched with speaker labels when diarization
  /// data is available, suitable for all export formats.
  String? get _exportableTranscript {
    final text = _transcriptText;
    if (text == null || text.isEmpty) return text;
    if (_diarizationSegments != null && _diarizationSegments!.isNotEmpty) {
      return KrakenExportService.injectSpeakerLabels(
        text,
        _diarizationSegments!,
        _speakerLabels,
        totalDurationMs: widget.recording.durationMs,
        transcriptSegments: _transcriptSegments,
      );
    }
    return text;
  }

  Future<void> _exportAudio() async {
    final audioFile = File(widget.recording.audioPath);
    if (!await audioFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Audio file not found.')));
      }
      return;
    }
    // Copy audio to temp with the current title so the shared file has the right name
    final ext = widget.recording.audioPath.split('.').last;
    final dir = await getTemporaryDirectory();
    final namedFile = await audioFile.copy(
      '${dir.path}/${_safeFileName(_currentTitle)}.$ext',
    );
    await Share.shareXFiles([
      XFile(namedFile.path),
    ], subject: '$_currentTitle — Audio');
  }

  Future<void> _exportTranscript() async {
    final enriched = _exportableTranscript;
    if (enriched == null || enriched.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transcript to export.')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${_safeFileName(_currentTitle)}_transcript.txt',
    );
    await file.writeAsString(
      'Transcript: $_currentTitle\n${'=' * 40}\n\n$enriched',
    );
    await Share.shareXFiles([
      XFile(file.path),
    ], subject: '$_currentTitle — Transcript');
  }

  Future<void> _exportSummary() async {
    if (_summaryJson == null || _summaryJson!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No summary to export.')));
      }
      return;
    }

    // Try to produce a human-readable summary
    String exportContent;
    try {
      String raw = _summaryJson!.trim();
      if (raw.startsWith('```')) {
        final lines = raw.split('\n');
        if (lines.length > 2) {
          raw = lines.sublist(1, lines.length - 1).join('\n');
        }
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
      exportContent =
          'AI Summary: ${widget.recording.title}\n${'=' * 40}\n\n$_summaryJson';
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${_safeFileName(_currentTitle)}_summary.txt',
    );
    await file.writeAsString(exportContent);
    await Share.shareXFiles([
      XFile(file.path),
    ], subject: '$_currentTitle — AI Summary');
  }

  Future<void> _exportAll() async {
    final files = <XFile>[];

    // Audio — copy with current title
    final audioFile = File(widget.recording.audioPath);
    if (await audioFile.exists()) {
      final ext = widget.recording.audioPath.split('.').last;
      final dir = await getTemporaryDirectory();
      final namedAudio = await audioFile.copy(
        '${dir.path}/${_safeFileName(_currentTitle)}.$ext',
      );
      files.add(XFile(namedAudio.path));
    }

    // Transcript
    final enrichedAll = _exportableTranscript;
    if (enrichedAll != null && enrichedAll.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      final txtFile = File(
        '${dir.path}/${_safeFileName(_currentTitle)}_transcript.txt',
      );
      await txtFile.writeAsString(
        'Transcript: $_currentTitle\n${'=' * 40}\n\n$enrichedAll',
      );
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
          if (lines.length > 2) {
            raw = lines.sublist(1, lines.length - 1).join('\n');
          }
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
      final sumFile = File(
        '${dir.path}/${_safeFileName(_currentTitle)}_summary.txt',
      );
      await sumFile.writeAsString(exportContent);
      files.add(XFile(sumFile.path));
    }

    // AI Chat log
    final chatLog = await _folderRepo.getExportableChatLog(widget.recording.id);
    if (chatLog != null && chatLog.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      final chatFile = File(
        '${dir.path}/${_safeFileName(_currentTitle)}_chat.txt',
      );
      await chatFile.writeAsString(
        'AI Chat Log: $_currentTitle\n${'=' * 40}\n\n$chatLog',
      );
      files.add(XFile(chatFile.path));
    }

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nothing to export.')));
      }
      return;
    }

    await Share.shareXFiles(files, subject: '$_currentTitle — Full Export');
  }

  Future<void> _exportMarkdown() async {
    final sb = StringBuffer();
    sb.writeln('# $_currentTitle');
    sb.writeln();
    sb.writeln('**Date:** ${_formatDate(_meetingDate)}  ');
    sb.writeln(
      '**Duration:** ${_formatPos(Duration(milliseconds: widget.recording.durationMs))}  ',
    );
    sb.writeln();

    // Summary section
    if (_summaryJson != null && _summaryJson!.isNotEmpty) {
      try {
        String raw = _summaryJson!.trim();
        if (raw.startsWith('```')) {
          final lines = raw.split('\n');
          if (lines.length > 2) {
            raw = lines.sublist(1, lines.length - 1).join('\n');
          }
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
    final enrichedTranscript = _exportableTranscript;
    if (enrichedTranscript != null && enrichedTranscript.isNotEmpty) {
      sb.writeln('---');
      sb.writeln();
      sb.writeln('## Full Transcript');
      sb.writeln();
      sb.writeln(enrichedTranscript);
    }

    // AI Chat section
    final chatLog = await _folderRepo.getExportableChatLog(widget.recording.id);
    if (chatLog != null && chatLog.isNotEmpty) {
      sb.writeln();
      sb.writeln('---');
      sb.writeln();
      sb.writeln('## AI Chat Log');
      sb.writeln();
      sb.writeln(chatLog);
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeFileName(_currentTitle)}.md');
    await file.writeAsString(sb.toString());
    await Share.shareXFiles([
      XFile(file.path),
    ], subject: '$_currentTitle — Markdown Export');
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $amPm';
  }

  /// Formats a token count with thousands separators: 1250 → "1,250"
  String _formatTokenCount(int count) {
    if (count < 1000) return count.toString();
    final str = count.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  Future<void> _showMeetingDatePicker() async {
    final pickedDate = await showDatePicker(
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
    if (pickedDate == null || !mounted) return;

    // Now pick a time
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_meetingDate),
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

    final DateTime finalDate;
    if (pickedTime != null) {
      finalDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    } else {
      // User skipped time — keep existing time, update date only
      finalDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _meetingDate.hour,
        _meetingDate.minute,
      );
    }

    if (mounted) {
      setState(() => _meetingDate = finalDate);
      await _folderRepo.setMeetingDate(widget.recording.id, finalDate);
    }
  }

  // 2A-08: Per-recording language override picker
  void _showLanguageOverridePicker() {
    // Supported languages — same list as in settings
    const languages = <String, String>{
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'nl': 'Dutch',
      'pl': 'Polish',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'tr': 'Turkish',
      'vi': 'Vietnamese',
      'th': 'Thai',
      'uk': 'Ukrainian',
      'sv': 'Swedish',
      'da': 'Danish',
      'fi': 'Finnish',
      'no': 'Norwegian',
      'he': 'Hebrew',
      'id': 'Indonesian',
      'ms': 'Malay',
      'tl': 'Tagalog',
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KrakenSpacing.s4),
                child: Text(
                  'Transcription Language',
                  style: KrakenText.displayMd(),
                ),
              ),
              const Divider(height: 1, color: KrakenColors.border),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: languages.entries.map((e) {
                    final selected = e.key == _transcriptionLanguage;
                    return ListTile(
                      dense: true,
                      leading: selected
                          ? const Icon(
                              Icons.check_circle,
                              color: KrakenColors.accent,
                              size: 20,
                            )
                          : const Icon(
                              Icons.circle_outlined,
                              color: KrakenColors.textMuted,
                              size: 20,
                            ),
                      title: Text(
                        '${e.value}  (${e.key})',
                        style: KrakenText.bodyMd(
                          color: selected
                              ? KrakenColors.accent
                              : KrakenColors.textPrimary,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx, e.key);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    ).then((selectedCode) async {
      if (selectedCode == null || selectedCode == _transcriptionLanguage) {
        return;
      }

      // Save override to recordings table
      final vault = context.read<VaultService>();
      await vault.db.update(
        'recordings',
        {'language_override': selectedCode},
        where: 'audio_path = ?',
        whereArgs: [widget.recording.audioPath],
      );

      setState(() => _transcriptionLanguage = selectedCode);

      // Offer to re-transcribe with the new language
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Language set to ${whisperLanguageLabel(selectedCode)}.',
            ),
            action: _transcriptText != null
                ? SnackBarAction(
                    label: 'Re-transcribe',
                    textColor: KrakenColors.accent,
                    onPressed: () async {
                      final engine = TranscriptionEngine();
                      // Clear old job
                      await vault.db.delete(
                        'transcription_jobs',
                        where: 'audio_path = ?',
                        whereArgs: [widget.recording.audioPath],
                      );
                      await engine.queueJob(
                        vault,
                        widget.recording.audioPath,
                        language: selectedCode,
                      );
                      _startTranscriptionPolling();
                      if (mounted) {
                        setState(() => _isActivelyTranscribing = true);
                      }
                    },
                  )
                : null,
          ),
        );
      }
    });
  }

  void _showExportSheet() {
    final hasTranscript =
        _transcriptText != null && _transcriptText!.isNotEmpty;
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
                  padding: const EdgeInsets.symmetric(
                    vertical: KrakenSpacing.s4,
                    horizontal: KrakenSpacing.s4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
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
                        setSheetState,
                        selected,
                        'pdf',
                        Icons.picture_as_pdf,
                        'PDF Document',
                        'Summary + transcript in one report',
                        enabled: hasTranscript || hasSummary,
                      ),
                      _exportCheckbox(
                        setSheetState,
                        selected,
                        'docx',
                        Icons.description_outlined,
                        'Word Document',
                        'Editable .docx with summary + transcript',
                        enabled: hasTranscript || hasSummary,
                      ),

                      const Divider(color: KrakenColors.border, height: 24),

                      // Raw formats
                      _exportCheckbox(
                        setSheetState,
                        selected,
                        'audio',
                        Icons.audio_file,
                        'Audio File',
                        hasAudio ? '.wav recording' : 'Audio unavailable',
                        enabled: hasAudio,
                      ),
                      _exportCheckbox(
                        setSheetState,
                        selected,
                        'transcript',
                        Icons.text_snippet,
                        'Transcript Only',
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
      secondary: Icon(
        icon,
        color: enabled ? KrakenColors.accent : KrakenColors.textMuted,
      ),
      title: Text(
        title,
        style: KrakenText.bodyMd(
          color: enabled ? KrakenColors.textPrimary : KrakenColors.textMuted,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: KrakenText.bodySm(color: KrakenColors.textMuted),
      ),
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

    // Load brand config from preferences
    final prefs = RepositoryProvider.of<PreferencesService>(
      context,
      listen: false,
    );
    final logoPath = await prefs.getBrandLogoPath();
    final headerText = await prefs.getBrandHeaderText();
    final footerText = await prefs.getBrandFooterText();
    final brandColor = await prefs.getBrandColor();

    Uint8List? logoBytes;
    if (logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        logoBytes = await logoFile.readAsBytes();
      }
    }

    final branding = BrandConfig(
      logoBytes: logoBytes,
      headerText: headerText.isNotEmpty ? headerText : null,
      footerText: footerText.isNotEmpty ? footerText : null,
      accentColorHex: brandColor.isNotEmpty ? brandColor : '#818CF8',
    );

    // PDF (auto-includes summary when available)
    if (selected['pdf'] == true) {
      try {
        final pdfFile = await exportService.exportPdf(
          recording: widget.recording,
          title: _currentTitle,
          transcriptText: _exportableTranscript,
          summaryJson: _summaryJson,
          branding: branding,
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
          transcriptText: _exportableTranscript,
          summaryJson: _summaryJson,
          branding: branding,
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
          final namedFile = await audioFile.copy(
            '${dir.path}/kraken_$safeName.$ext',
          );
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
        await file.writeAsString(
          'Transcript: $_currentTitle\n${'=' * 40}\n\n$_transcriptText',
        );
        files.add(XFile(file.path));
      } catch (e) {
        errors.add('Transcript: $e');
      }
    }

    // AI Chat log (always included if it exists)
    try {
      final chatLog = await _folderRepo.getExportableChatLog(
        widget.recording.id,
      );
      if (chatLog != null && chatLog.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final chatFile = File('${dir.path}/kraken_${safeName}_chat.txt');
        await chatFile.writeAsString(
          'AI Chat Log: $_currentTitle\n${'=' * 40}\n\n$chatLog',
        );
        files.add(XFile(chatFile.path));
      }
    } catch (e) {
      errors.add('Chat: $e');
    }

    if (files.isEmpty) {
      if (mounted) {
        final msg = errors.isNotEmpty
            ? 'Export failed: ${errors.join('; ')}'
            : 'Nothing to export.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }

    try {
      await Share.shareXFiles(files, subject: '$_currentTitle — Kraken Export');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
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
        if (lines.length > 2) {
          raw = lines.sublist(1, lines.length - 1).join('\n');
        }
      }
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final sb = StringBuffer();
      sb.writeln('AI Summary: $_currentTitle');
      sb.writeln('Date: ${_formatDate(_meetingDate)}');
      sb.writeln(
        'Duration: ${_formatPos(Duration(milliseconds: widget.recording.durationMs))}',
      );
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

      sb.writeln('=' * 50);
      sb.writeln('Generated by The Kraken');

      return sb.toString();
    } catch (_) {
      return 'AI Summary: $_currentTitle\n${'=' * 50}\n\n$_summaryJson';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Auto-save any pending transcript edits before popping
        if (_isEditingTranscript) {
          await _saveTranscriptEdits();
        }
        if (_isEditingDiarizedTranscript && _editableChunks != null) {
          await _saveDiarizedEdits();
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: KrakenColors.bg,
        appBar: AppBar(
          backgroundColor: KrakenColors.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
            onPressed: () async {
              // Auto-save any pending transcript edits before popping
              if (_isEditingTranscript) {
                await _saveTranscriptEdits();
              }
              if (_isEditingDiarizedTranscript && _editableChunks != null) {
                await _saveDiarizedEdits();
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          title: _isEditingTitle
              ? TextField(
                  controller: _titleEditController,
                  focusNode: _titleFocusNode,
                  style: KrakenText.displayMd(),
                  maxLength: 100,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    counterText: '',
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: KrakenColors.accent),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: KrakenColors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _commitInlineRename(),
                  onTapOutside: (_) => _commitInlineRename(),
                )
              : GestureDetector(
                  onTap: _startInlineRename,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _currentTitle,
                          style: KrakenText.displayMd(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.edit,
                        size: 14,
                        color: KrakenColors.textSecondary,
                      ),
                    ],
                  ),
                ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.ios_share,
                color: KrakenColors.textSecondary,
              ),
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
                            color: KrakenColors.accent.withValues(
                              alpha: _pulseAnimation.value,
                            ),
                          ),
                        ),
                        const SizedBox(height: KrakenSpacing.s4),
                        // Dynamic phase label from engine
                        ValueListenableBuilder<Map<String, String>>(
                          valueListenable:
                              TranscriptionEngine().transcriptionPhase,
                          builder: (context, phaseMap, _) {
                            final phase =
                                phaseMap[widget.recording.audioPath] ??
                                'Transcribing on device...';
                            return Text(
                              phase,
                              style: KrakenText.displayMd(),
                              textAlign: TextAlign.center,
                            );
                          },
                        ),
                        const SizedBox(height: KrakenSpacing.s3),
                        // Real progress bar with percentage and phase label
                        ValueListenableBuilder<Map<String, double>>(
                          valueListenable:
                              TranscriptionEngine().transcriptionProgress,
                          builder: (context, progressMap, _) {
                            final progress =
                                progressMap[widget.recording.audioPath];
                            if (progress == null) {
                              return const LinearProgressIndicator(
                                value: null,
                                backgroundColor: KrakenColors.surface,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  KrakenColors.accent,
                                ),
                              );
                            }
                            final pct = (progress * 100).toInt();
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: KrakenColors.accent,
                                      ),
                                    ),
                                    const SizedBox(width: KrakenSpacing.s2),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: KrakenColors.border,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(KrakenColors.accent),
                                          minHeight: 6,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: KrakenSpacing.s2),
                                    Text(
                                      '$pct%',
                                      style: KrakenText.bodySm(
                                        color: KrakenColors.accent,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: KrakenSpacing.s6),
                        // ─── Token meter ────────────────────────────
                        ValueListenableBuilder<Map<String, int>>(
                          valueListenable:
                              TranscriptionEngine().transcriptionTokens,
                          builder: (context, tokenMap, _) {
                            final tokens =
                                tokenMap[widget.recording.audioPath] ?? 0;
                            return AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, _) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: KrakenSpacing.s4,
                                  vertical: KrakenSpacing.s2,
                                ),
                                decoration: BoxDecoration(
                                  color: KrakenColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    KrakenRadius.md,
                                  ),
                                  border: Border.all(
                                    color: KrakenColors.accent.withValues(
                                      alpha:
                                          0.15 + 0.15 * _pulseAnimation.value,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.bolt,
                                      size: 16,
                                      color: KrakenColors.accent.withValues(
                                        alpha:
                                            0.5 + 0.5 * _pulseAnimation.value,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatTokenCount(tokens),
                                      style:
                                          KrakenText.bodySm(
                                            color: KrakenColors.accent,
                                          ).copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: [
                                              const FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'tokens processed',
                                      style: KrakenText.bodySm(
                                        color: KrakenColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: KrakenSpacing.s4),
                        // Flowing shimmer banner
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, _) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: KrakenSpacing.s4,
                              vertical: KrakenSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  KrakenColors.accent.withValues(alpha: 0.05),
                                  KrakenColors.accent.withValues(
                                    alpha: 0.15 * _pulseAnimation.value,
                                  ),
                                  KrakenColors.accent.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                KrakenRadius.md,
                              ),
                              border: Border.all(
                                color: KrakenColors.accent.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: KrakenColors.accent.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Processing locally — audio never leaves your device',
                                    style: KrakenText.bodySm(
                                      color: KrakenColors.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Icon(
                          (widget.recording.transcriptionStatus == 'failed' ||
                                  _transcriptionFailed)
                              ? Icons.error_outline
                              : Icons.pending_actions,
                          size: 64,
                          color:
                              (widget.recording.transcriptionStatus ==
                                      'failed' ||
                                  _transcriptionFailed)
                              ? Colors.orangeAccent
                              : KrakenColors.textMuted,
                        ),
                        const SizedBox(height: KrakenSpacing.s4),
                        Text(
                          (widget.recording.transcriptionStatus == 'failed' ||
                                  _transcriptionFailed)
                              ? 'Transcription failed'
                              : 'No transcript available yet.',
                          style: KrakenText.displayMd(),
                        ),
                        const SizedBox(height: KrakenSpacing.s2),
                        if (widget.recording.transcriptionStatus == 'failed' ||
                            _transcriptionFailed)
                          Text(
                            'The recording may be too short or in an unsupported format.',
                            style: KrakenText.bodyMd(
                              color: KrakenColors.textMuted,
                            ),
                            textAlign: TextAlign.center,
                          )
                        else
                          Text(
                            'Status: ${widget.recording.transcriptionStatus ?? 'Unknown'}',
                            style: KrakenText.bodyMd(
                              color: KrakenColors.textMuted,
                            ),
                          ),
                        if (widget.recording.transcriptionStatus == 'failed' ||
                            widget.recording.transcriptionStatus == null ||
                            _transcriptionFailed) ...[
                          const SizedBox(height: KrakenSpacing.s6),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final engine = TranscriptionEngine();
                              final vault = RepositoryProvider.of<VaultService>(
                                context,
                                listen: false,
                              );

                              // Clear any old failed job
                              await vault.db.delete(
                                'transcription_jobs',
                                where: 'audio_path = ?',
                                whereArgs: [widget.recording.audioPath],
                              );

                              await engine.queueJobWithDefaultLanguage(
                                vault,
                                widget.recording.audioPath,
                              );
                              _startTranscriptionPolling();
                              if (mounted) {
                                setState(() {
                                  _isActivelyTranscribing = true;
                                  _transcriptionFailed = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Transcription re-queued.'),
                                  ),
                                );
                              }
                            },
                            icon: Icon(
                              (widget.recording.transcriptionStatus ==
                                          'failed' ||
                                      _transcriptionFailed)
                                  ? Icons.refresh
                                  : Icons.record_voice_over,
                            ),
                            label: Text(
                              (widget.recording.transcriptionStatus ==
                                          'failed' ||
                                      _transcriptionFailed)
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
                                    ? () => _isPlaying
                                          ? _player.pause()
                                          : _player.play()
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.all(
                                    KrakenSpacing.s3,
                                  ),
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
                                    Text(
                                      widget.recording.title,
                                      style: KrakenText.bodyLg(),
                                    ),
                                    Text(
                                      '${_formatPos(_playerPosition)} / ${_formatPos(_playerDuration)}',
                                      style: KrakenText.bodySm(
                                        color: KrakenColors.textMuted,
                                      ),
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
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: KrakenColors.accent,
                              inactiveTrackColor: KrakenColors.border,
                              thumbColor: KrakenColors.accent,
                            ),
                            child: Slider(
                              min: 0,
                              max: _playerDuration.inMilliseconds
                                  .toDouble()
                                  .clamp(1, double.infinity),
                              value: _playerPosition.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    _playerDuration.inMilliseconds
                                        .toDouble()
                                        .clamp(1, double.infinity),
                                  ),
                              onChanged: (val) {
                                _player.seek(
                                  Duration(milliseconds: val.toInt()),
                                );
                              },
                            ),
                          ),
                          // Retention policy (tappable, lives on the MP3 card)
                          const SizedBox(height: KrakenSpacing.s2),
                          Divider(
                            color: KrakenColors.border.withValues(alpha: 0.3),
                            height: 1,
                          ),
                          const SizedBox(height: KrakenSpacing.s2),
                          GestureDetector(
                            onTap: _showRetentionPolicySheet,
                            child: Row(
                              children: [
                                Icon(
                                  _retentionPolicyIcon(_retentionPolicy),
                                  size: 13,
                                  color: KrakenColors.textMuted.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _retentionPolicyLabel(_retentionPolicy),
                                  style:
                                      KrakenText.bodySm(
                                        color: KrakenColors.textMuted,
                                      ).copyWith(
                                        fontSize: 11,
                                        decoration: TextDecoration.underline,
                                        decorationColor: KrakenColors.textMuted
                                            .withValues(alpha: 0.4),
                                      ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: KrakenColors.textMuted.withValues(
                                    alpha: 0.5,
                                  ),
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
                                  color: KrakenColors.textMuted.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Meeting: ${_formatDate(_meetingDate)}',
                                  style:
                                      KrakenText.bodySm(
                                        color: KrakenColors.textMuted,
                                      ).copyWith(
                                        fontSize: 11,
                                        decoration: TextDecoration.underline,
                                        decorationColor: KrakenColors.textMuted
                                            .withValues(alpha: 0.4),
                                      ),
                                ),
                                if (_meetingDate.year !=
                                        widget.recording.createdAt.year ||
                                    _meetingDate.month !=
                                        widget.recording.createdAt.month ||
                                    _meetingDate.day !=
                                        widget.recording.createdAt.day) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '(Recorded ${_formatDate(widget.recording.createdAt)})',
                                    style: KrakenText.bodySm(
                                      color: KrakenColors.textMuted,
                                    ).copyWith(fontSize: 10),
                                  ),
                                ],
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: KrakenColors.textMuted.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: KrakenSpacing.s6),
                    if (_summaryJson == null && !_isGeneratingSummary)
                      Column(
                        children: [
                          // Summary style picker
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Style: ',
                                  style: KrakenText.bodySm(
                                    color: KrakenColors.textMuted,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: KrakenColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: KrakenColors.border,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _summaryStyle,
                                      isDense: true,
                                      dropdownColor:
                                          KrakenColors.surfaceElevated,
                                      style: KrakenText.bodySm(
                                        color: KrakenColors.textPrimary,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'concise',
                                          child: Text('Concise'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'detailed',
                                          child: Text('Detailed'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'bullets',
                                          child: Text('Bullet Points'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _summaryStyle = v);
                                          _saveSummaryStyle(v);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: _generateSummary,
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Generate AI Summary'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: KrakenColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: KrakenSpacing.s6,
                                  vertical: KrakenSpacing.s3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (_isGeneratingSummary || _summaryJson != null)
                      _buildSummaryBlock(),

                    const SizedBox(height: KrakenSpacing.s6),
                    // ─── Transcript header with action icons ───
                    Row(
                      children: [
                        Text('Transcript', style: KrakenText.displayMd()),
                        if (_isUserCorrected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: KrakenColors.accent.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Edited',
                              style: KrakenText.bodySm(
                                color: KrakenColors.accent,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        // Re-format breaks toggle
                        if (!_isEditingTranscript)
                          IconButton(
                            icon: Icon(
                              Icons.segment,
                              color: _showBreakSlider
                                  ? KrakenColors.accent
                                  : KrakenColors.textMuted,
                              size: 20,
                            ),
                            tooltip: 'Paragraph break sensitivity',
                            onPressed: () => setState(
                              () => _showBreakSlider = !_showBreakSlider,
                            ),
                          ),
                        // H1-32: Search toggle
                        IconButton(
                          icon: Icon(
                            _isSearching ? Icons.search_off : Icons.search,
                            color: _isSearching
                                ? KrakenColors.accent
                                : KrakenColors.textMuted,
                            size: 20,
                          ),
                          tooltip: 'Search transcript',
                          onPressed: _toggleSearch,
                        ),
                        // H1-30: Edit toggle
                        if (!_isEditingTranscript)
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: KrakenColors.textMuted,
                              size: 20,
                            ),
                            tooltip: 'Edit transcript',
                            onPressed: _startEditingTranscript,
                          )
                        else ...[
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            tooltip: 'Cancel edits',
                            onPressed: _cancelTranscriptEdits,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.check,
                              color: KrakenColors.accent,
                              size: 20,
                            ),
                            tooltip: 'Save edits',
                            onPressed: _saveTranscriptEdits,
                          ),
                        ],
                      ],
                    ),
                    // ─── Break sensitivity slider (collapsible) ───
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Container(
                        margin: const EdgeInsets.only(
                          top: KrakenSpacing.s2,
                          bottom: KrakenSpacing.s2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: KrakenColors.surface,
                          borderRadius: BorderRadius.circular(KrakenRadius.md),
                          border: Border.all(
                            color: KrakenColors.accent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.segment,
                                  size: 16,
                                  color: KrakenColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Paragraph Breaks',
                                  style: KrakenText.bodySm(),
                                ),
                                const Spacer(),
                                Text(
                                  '${_breakThreshold.toStringAsFixed(1)}s',
                                  style: KrakenText.bodySm(
                                    color: KrakenColors.accent,
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: KrakenColors.accent,
                                inactiveTrackColor: Colors.white10,
                                thumbColor: KrakenColors.accent,
                                overlayColor: KrakenColors.accent.withValues(
                                  alpha: 0.15,
                                ),
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                              ),
                              child: Slider(
                                min: 0.1,
                                max: 5.0,
                                divisions: 49,
                                value: _breakThreshold,
                                onChanged: (v) {
                                  setState(() => _breakThreshold = v);
                                },
                                onChangeEnd: (v) async {
                                  // Persist + auto-apply
                                  final prefs =
                                      RepositoryProvider.of<PreferencesService>(
                                        context,
                                      );
                                  await prefs.setBreakThreshold(v);
                                  _reformatTranscriptBreaks();
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'More breaks',
                                    style: KrakenText.caption(
                                      color: KrakenColors.textMuted,
                                    ),
                                  ),
                                  Text(
                                    'Fewer breaks',
                                    style: KrakenText.caption(
                                      color: KrakenColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      crossFadeState: _showBreakSlider
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                    // H1-32: Search bar
                    if (_isSearching)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: KrakenSpacing.s3,
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: KrakenText.bodyMd(),
                          decoration: InputDecoration(
                            hintText: 'Search transcript…',
                            hintStyle: KrakenText.bodyMd(
                              color: KrakenColors.textMuted,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 18,
                              color: KrakenColors.textMuted,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            filled: true,
                            fillColor: KrakenColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                KrakenRadius.md,
                              ),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: KrakenColors.textMuted,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                    const SizedBox(height: KrakenSpacing.s3),
                    // ─── Speaker detection controls ─────────────────────────
                    if (!_isEditingTranscript && kDiarizationEnabled)
                      _buildSpeakerDetectionPanel(),
                    if (!_isEditingTranscript && kDiarizationEnabled)
                      const SizedBox(height: KrakenSpacing.s3),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(KrakenSpacing.s4),
                      decoration: BoxDecoration(
                        color: KrakenColors.surface,
                        borderRadius: BorderRadius.circular(KrakenRadius.lg),
                        border: Border.all(
                          color: _isEditingTranscript
                              ? KrakenColors.accent
                              : KrakenColors.border,
                        ),
                      ),
                      child: _isEditingTranscript
                          ? TextField(
                              controller: _transcriptEditController,
                              maxLines: null,
                              style: KrakenText.bodyLg().copyWith(height: 1.6),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            )
                          : _buildInteractiveTranscript(),
                    ),
                    const SizedBox(height: KrakenSpacing.s8),
                  ],
                ),
              ),
      ),
    ); // closes Scaffold + PopScope
  }

  // ─── Inline speaker detection panel ──────────────────────────────────────────

  Widget _buildSpeakerDetectionPanel() {
    // Gate: show locked panel for free users
    if (!_isPaidUser) {
      return GestureDetector(
        onTap: _showDiarizationUpgradePrompt,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KrakenColors.surface,
            borderRadius: BorderRadius.circular(KrakenRadius.md),
            border: Border.all(color: KrakenColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: KrakenColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Speaker Detection',
                  style: KrakenText.bodySm().copyWith(
                    fontWeight: FontWeight.w600,
                    color: KrakenColors.textSecondary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KrakenColors.accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PRO',
                  style: KrakenText.caption(
                    color: KrakenColors.accent,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasDiarization =
        _diarizationSegments != null && _diarizationSegments!.isNotEmpty;
    final detectedCount = hasDiarization
        ? _diarizationSegments!.map((s) => s.speaker).toSet().length
        : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KrakenColors.surface,
        borderRadius: BorderRadius.circular(KrakenRadius.md),
        border: Border.all(color: KrakenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header row: label + detect/re-run button ──────────────
          Row(
            children: [
              const Icon(
                Icons.record_voice_over,
                size: 16,
                color: KrakenColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Speaker Detection',
                style: KrakenText.bodySm().copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasDiarization) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: KrakenColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$detectedCount found',
                    style: KrakenText.caption(
                      color: KrakenColors.accent,
                    ).copyWith(fontWeight: FontWeight.w600, fontSize: 10),
                  ),
                ),
              ],
              const Spacer(),
              // ─── Detect / Re-run button ─────────────────────
              GestureDetector(
                onTap: _isDiarizing
                    ? null
                    : () {
                        if (hasDiarization) {
                          _reclusterWithThreshold(_diarizationThreshold);
                        } else {
                          _runManualDiarization();
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _isDiarizing
                        ? KrakenColors.accent.withValues(alpha: 0.05)
                        : KrakenColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: KrakenColors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDiarizing) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KrakenColors.accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Detecting…',
                          style: KrakenText.caption(
                            color: KrakenColors.accent,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ] else ...[
                        Icon(
                          hasDiarization ? Icons.refresh : Icons.play_arrow,
                          size: 14,
                          color: KrakenColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasDiarization ? 'Re-run' : 'Detect',
                          style: KrakenText.caption(
                            color: KrakenColors.accent,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          // ─── Expected speakers selector ────────────────────────────
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Expected:',
                style: KrakenText.caption(
                  color: KrakenColors.textMuted,
                ).copyWith(fontSize: 10),
              ),
              const SizedBox(width: 6),
              for (final n in [null, 2, 3, 4, 5, 6])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: _isDiarizing
                        ? null
                        : () {
                            setState(() => _expectedSpeakers = n);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _expectedSpeakers == n
                            ? KrakenColors.accent.withValues(alpha: 0.2)
                            : KrakenColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _expectedSpeakers == n
                              ? KrakenColors.accent
                              : KrakenColors.border,
                        ),
                      ),
                      child: Text(
                        n == null ? 'Auto' : '$n',
                        style:
                            KrakenText.caption(
                              color: _expectedSpeakers == n
                                  ? KrakenColors.accent
                                  : KrakenColors.textMuted,
                            ).copyWith(
                              fontSize: 10,
                              fontWeight: _expectedSpeakers == n
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ─── Sensitivity slider ───────────────────────────────────
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'More',
                style: KrakenText.caption(
                  color: KrakenColors.textMuted,
                ).copyWith(fontSize: 9),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: KrakenColors.accent,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: KrakenColors.accent,
                    overlayColor: KrakenColors.accent.withAlpha(30),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: _diarizationThreshold,
                    min: 0.40,
                    max: 0.90,
                    divisions: 10,
                    onChanged: _isDiarizing
                        ? null
                        : (v) {
                            setState(() => _diarizationThreshold = v);
                          },
                    onChangeEnd: (v) {
                      _saveDiarizationThreshold(v);
                      if (hasDiarization) {
                        _reclusterWithThreshold(v);
                      }
                    },
                  ),
                ),
              ),
              Text(
                'Fewer',
                style: KrakenText.caption(
                  color: KrakenColors.textMuted,
                ).copyWith(fontSize: 9),
              ),
            ],
          ),
          // Threshold value label
          Center(
            child: Text(
              'Sensitivity: ${_diarizationThreshold.toStringAsFixed(2)}',
              style: KrakenText.caption(
                color: KrakenColors.textMuted,
              ).copyWith(fontSize: 10),
            ),
          ),

          // ─── Speaker legend (inline) ───────────────────────────────
          if (hasDiarization) ...[
            const SizedBox(height: 8),
            _buildSpeakerLegend(),
          ],
        ],
      ),
    );
  }

  // ─── Speaker legend ──────────────────────────────────────────────────────────

  Widget _buildSpeakerLegend() {
    if (_diarizationSegments == null || _diarizationSegments!.isEmpty) {
      return const SizedBox.shrink();
    }

    final speakerIndices =
        _diarizationSegments!.map((s) => s.speaker).toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KrakenSpacing.s3,
            vertical: KrakenSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: KrakenColors.surfaceElevated,
            borderRadius: BorderRadius.circular(KrakenRadius.md),
            border: Border.all(color: KrakenColors.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 14,
                color: KrakenColors.textMuted.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                '${speakerIndices.length} speaker${speakerIndices.length != 1 ? 's' : ''}',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: speakerIndices.map((idx) {
                    final color = _speakerColors[idx % _speakerColors.length];
                    final label = _speakerLabels[idx] ?? 'Speaker ${idx + 1}';
                    return GestureDetector(
                      onTap: () => _showSpeakerRenameDialog(idx, label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              label,
                              style: KrakenText.bodySm(color: color).copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.edit,
                              size: 10,
                              color: color.withValues(alpha: 0.6),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        // "Adjust speakers" button
        if (_currentDiarizationConfig != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: _isReclustering ? null : _showSpeakerAdjustSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: KrakenColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: KrakenColors.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isReclustering) ...[
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: KrakenColors.accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Adjusting speakers...',
                        style: KrakenText.bodySm(
                          color: KrakenColors.accent,
                        ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                      ),
                    ] else ...[
                      Icon(Icons.tune, size: 13, color: KrakenColors.accent),
                      const SizedBox(width: 5),
                      Text(
                        'Speaker labels look wrong?',
                        style: KrakenText.bodySm(
                          color: KrakenColors.accent,
                        ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        // Remove speaker labels button
        if (!_isReclustering)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: _removeSpeakerLabels,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: KrakenColors.danger.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KrakenColors.danger.withAlpha(40)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.close,
                      size: 13,
                      color: KrakenColors.danger.withAlpha(180),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Remove labels',
                      style: KrakenText.bodySm(
                        color: KrakenColors.danger,
                      ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Speaker adjustment sheet (v1.1) ────────────────────────────────────────

  void _showSpeakerAdjustSheet() {
    final currentThreshold = _currentDiarizationConfig?.threshold ?? 0.75;
    // Distinct speakers in the current post-process result. If this is high
    // (>3) on what's typically a 1-on-1 or small meeting, the user almost
    // certainly wants to combine voices — surface a hint so they don't
    // have to guess which direction to nudge the slider.
    final detectedSpeakerCount =
        _diarizationSegments?.map((s) => s.speaker).toSet().length ?? 0;
    final showLotsOfSpeakersHint = detectedSpeakerCount > 3;
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KrakenColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Adjust Speaker Detection', style: KrakenText.displayMd()),
              const SizedBox(height: 4),
              Text(
                'Current threshold: ${currentThreshold.toStringAsFixed(2)}',
                style: KrakenText.bodySm(color: KrakenColors.textSecondary),
              ),
              if (showLotsOfSpeakersHint) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: KrakenColors.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: KrakenColors.accent.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: KrakenColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Looks like a lot of speakers ($detectedSpeakerCount). '
                          'Try "Combine similar voices" — or pick the exact '
                          'count below if you know it.',
                          style: KrakenText.bodySm(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Combine voices — increase threshold (+0.05)
              _buildAdjustOption(
                ctx,
                icon: Icons.call_merge,
                iconColor: const Color(0xFF4ECDC4),
                title: 'Combine similar voices',
                subtitle: 'Merge voices that sound alike → fewer speakers',
                enabled: currentThreshold < 0.95 - 1e-6,
                onTap: () {
                  Navigator.pop(ctx);
                  final newThreshold = (currentThreshold + 0.05).clamp(
                    0.3,
                    0.95,
                  );
                  _reclusterWithThreshold(newThreshold);
                },
              ),
              const SizedBox(height: 8),

              // Separate voices — decrease threshold (-0.05)
              _buildAdjustOption(
                ctx,
                icon: Icons.call_split,
                iconColor: const Color(0xFFFF6B6B),
                title: 'Separate similar voices',
                subtitle: 'Split overlapping voices → more speakers',
                enabled: currentThreshold > 0.3 + 1e-6,
                onTap: () {
                  Navigator.pop(ctx);
                  final newThreshold = (currentThreshold - 0.05).clamp(
                    0.3,
                    0.95,
                  );
                  _reclusterWithThreshold(newThreshold);
                },
              ),
              const SizedBox(height: 8),

              // Reset to default
              _buildAdjustOption(
                ctx,
                icon: Icons.refresh,
                iconColor: KrakenColors.accent,
                title: 'Reset to default',
                subtitle: 'Re-run with default settings (threshold 0.75)',
                enabled: (currentThreshold - 0.75).abs() > 0.01,
                onTap: () {
                  Navigator.pop(ctx);
                  _reclusterWithThreshold(0.75);
                },
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              Text(
                'I know how many speakers there are',
                style: KrakenText.bodySm(
                  color: KrakenColors.textSecondary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Bypass auto-detection — forces an exact count.',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in const [2, 3, 4, 5, 6])
                    _buildSpeakerCountChip(
                      ctx,
                      count: n,
                      isCurrent: _currentDiarizationConfig?.numSpeakers == n,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeakerCountChip(
    BuildContext ctx, {
    required int count,
    required bool isCurrent,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _reclusterWithCount(count);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? KrakenColors.accent.withValues(alpha: 0.18)
              : KrakenColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCurrent ? KrakenColors.accent : KrakenColors.border,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Text(
          '$count',
          style: KrakenText.bodyMd(
            color: isCurrent ? KrakenColors.accent : KrakenColors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildAdjustOption(
    BuildContext ctx, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final opacity = enabled ? 1.0 : 0.35;
    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: KrakenColors.bg.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled
                    ? iconColor.withValues(alpha: 0.25)
                    : KrakenColors.border.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: KrakenText.bodyMd().copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: KrakenText.bodySm(
                          color: KrakenColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: KrakenColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Re-clusters from cached embeddings with a new threshold.
  /// Preserves user-renamed speaker labels by best-effort overlap matching.
  Future<void> _reclusterWithThreshold(double newThreshold) =>
      _recluster(threshold: newThreshold, numSpeakers: null);

  Future<void> _reclusterWithCount(int count) =>
      _recluster(threshold: null, numSpeakers: count);

  /// Shared re-cluster path. Pass either a [threshold] (auto clustering)
  /// or a [numSpeakers] (forced count, bypasses threshold). When
  /// [numSpeakers] is non-null the threshold is preserved from the
  /// previous config but ignored by the native pipeline.
  Future<void> _recluster({
    required double? threshold,
    required int? numSpeakers,
  }) async {
    if (_isReclustering) return;
    setState(() => _isReclustering = true);

    try {
      final diarizer = NemoDiarizer(
        downloadFile: ModelFileDownloader().download,
      );
      final newConfig = DiarizationConfig(
        threshold: threshold ?? _currentDiarizationConfig?.threshold ?? 0.75,
        minDuration: _currentDiarizationConfig?.minDuration ?? 1.0,
        numSpeakers: numSpeakers,
      );

      // 1. Try fast re-clustering from cached embeddings.
      DiarizationResult? result;
      final embeddingsPath = await _folderRepo.getEmbeddingsPath(
        widget.recording.id,
      );
      if (embeddingsPath != null) {
        try {
          result = await diarizer.reclusterRecording(
            embeddingsPath: embeddingsPath,
            config: newConfig,
          );
        } catch (e) {
          // Cache missing or stale (e.g. produced by an older embedding
          // model). Fall through to a full re-process.
          debugPrint(
            '[Recluster] Fast path failed ($e). Falling back to full re-process.',
          );
        }
      }

      // 2. Fallback: full re-process from audio if no usable cache exists.
      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Re-analyzing speakers from audio (this may take a moment)…',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        final audioDir = widget.recording.audioPath.substring(
          0,
          widget.recording.audioPath.lastIndexOf('/'),
        );
        final freshCachePath = '$audioDir/${widget.recording.id}.embeddings';
        result = await diarizer.processRecording(
          widget.recording.audioPath,
          config: newConfig,
          embeddingsCachePath: freshCachePath,
        );
      }

      // 3. Persist updated result (saveDiarizationResult handles label preservation)
      await _folderRepo.saveDiarizationResult(widget.recording.id, result);

      // 4. Reload state
      final segments = await _folderRepo.getDiarizationSegments(
        widget.recording.id,
      );
      final labels = await _folderRepo.getSpeakerLabels(widget.recording.id);

      if (mounted) {
        setState(() {
          _diarizationSegments = segments;
          _speakerLabels = labels;
          _currentDiarizationConfig = newConfig;
          _editableChunks = null;
          _isEditingDiarizedTranscript = false;
        });
        final speakerNoun = 'speaker${result.speakerCount != 1 ? 's' : ''}';
        final detail = numSpeakers != null
            ? 'forced to $numSpeakers'
            : 'threshold ${newConfig.threshold.toStringAsFixed(2)}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Re-analyzed: ${result.speakerCount} $speakerNoun ($detail)',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Recluster] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speaker adjustment failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReclustering = false);
    }
  }

  // ─── Speaker rename dialog ──────────────────────────────────────────────────

  Future<void> _showSpeakerRenameDialog(
    int speakerIndex,
    String currentLabel,
  ) async {
    final controller = TextEditingController(text: currentLabel);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _speakerColors[speakerIndex % _speakerColors.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text('Rename Speaker', style: KrakenText.displayMd()),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyLg(),
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g., Dr. Smith',
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
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.accent,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentLabel) {
      await _folderRepo.renameSpeaker(
        widget.recording.id,
        speakerIndex,
        newName,
      );
      if (mounted) {
        setState(() {
          _speakerLabels[speakerIndex] = newName;
          // Clear per-instance overrides for this speaker so global rename applies
          if (_editableChunks != null) {
            for (final c in _editableChunks!) {
              if (c.speaker == speakerIndex) c.labelOverride = null;
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speaker renamed to "$newName"')),
        );
      }
    }
  }

  // ─── Speaker lookup from timestamp ────────────────────────────────────────

  /// Returns the speaker index for a given timestamp (in seconds), or null.
  int? _speakerAtTimestamp(double timestampSeconds) {
    if (_diarizationSegments == null) return null;
    for (final seg in _diarizationSegments!) {
      if (timestampSeconds >= seg.startSeconds &&
          timestampSeconds <= seg.endSeconds) {
        return seg.speaker;
      }
    }
    // Fallback: find nearest segment within 3 seconds tolerance
    DiarizationSegment? nearest;
    double nearestDist = double.infinity;
    for (final seg in _diarizationSegments!) {
      final dist = (seg.startSeconds - timestampSeconds).abs();
      if (dist < nearestDist && dist < 3.0) {
        nearestDist = dist;
        nearest = seg;
      }
    }
    return nearest?.speaker;
  }

  /// Parse a timestamp string [MM:SS] or [H:MM:SS] into total seconds.
  double _parseTimestampSeconds(String ts) {
    final cleaned = ts.replaceAll(RegExp(r'[\[\]]'), '');
    final parts = cleaned.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60.0 +
          (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600.0 +
          (int.tryParse(parts[1]) ?? 0) * 60.0 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return 0;
  }

  /// Formats a seconds value into a human-readable timestamp string.
  /// Returns [M:SS] for durations under an hour, [H:MM:SS] otherwise.
  String _formatSecondsAsTimestamp(double totalSeconds) {
    final total = totalSeconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '[$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}]';
    }
    return '[$m:${s.toString().padLeft(2, '0')}]';
  }

  // ─── Structural editing helpers for diarized transcript ──────────────────

  /// Show an action menu for a speaker label in edit mode.
  /// Offers: rename this label, rename all for this speaker,
  /// delete this label, delete all labels for this speaker.
  void _showChunkLabelActions(int index) {
    final chunk = _editableChunks![index];
    final currentLabel =
        chunk.labelOverride ??
        _speakerLabels[chunk.speaker] ??
        'Speaker ${chunk.speaker + 1}';
    final color = _speakerColors[chunk.speaker % _speakerColors.length];

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KrakenColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header showing which label
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: KrakenText.displayMd().copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Rename this label ──
              ListTile(
                leading: Icon(Icons.edit_outlined, color: KrakenColors.accent),
                title: Text('Rename This Label', style: KrakenText.bodyMd()),
                subtitle: Text(
                  'Change only this one instance',
                  style: KrakenText.caption(color: KrakenColors.textSecondary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameChunkLabelInline(index, currentLabel);
                },
              ),
              const Divider(color: Colors.white10, height: 1),

              // ── Rename all for this speaker ──
              ListTile(
                leading: Icon(Icons.people_outline, color: KrakenColors.accent),
                title: Text(
                  'Rename All "$currentLabel"',
                  style: KrakenText.bodyMd(),
                ),
                subtitle: Text(
                  'Change every label for this speaker',
                  style: KrakenText.caption(color: KrakenColors.textSecondary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSpeakerRenameDialog(chunk.speaker, currentLabel);
                },
              ),
              const Divider(color: Colors.white10, height: 1),

              // ── Delete this label ──
              ListTile(
                leading: Icon(
                  Icons.remove_circle_outline,
                  color: Colors.orange,
                ),
                title: Text('Delete This Label', style: KrakenText.bodyMd()),
                subtitle: Text(
                  'Merge this text into the previous speaker',
                  style: KrakenText.caption(color: KrakenColors.textSecondary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteChunkLabel(index);
                },
              ),
              const Divider(color: Colors.white10, height: 1),

              // ── Delete all for this speaker ──
              ListTile(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: KrakenColors.danger,
                ),
                title: Text(
                  'Delete All "$currentLabel"',
                  style: KrakenText.bodyMd(color: KrakenColors.danger),
                ),
                subtitle: Text(
                  'Remove every label for this speaker and merge text',
                  style: KrakenText.caption(color: KrakenColors.textSecondary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAllChunkLabelsForSpeaker(chunk.speaker);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inline rename dialog for a single speaker label instance.
  void _renameChunkLabelInline(int index, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Rename This Label', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyLg(),
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g., Dr. Smith',
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
            style: ElevatedButton.styleFrom(
              backgroundColor: KrakenColors.accent,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == currentLabel) return;
    setState(() => _editableChunks![index].labelOverride = newName);
  }

  /// Delete a single chunk label — merge its text into the previous chunk.
  void _deleteChunkLabel(int index) {
    if (_editableChunks == null || _editableChunks!.length <= 1) return;
    setState(() {
      if (index > 0) {
        // Merge text into previous chunk
        _editableChunks![index - 1].text =
            '${_editableChunks![index - 1].text} ${_editableChunks![index].text}'
                .trim();
      } else if (_editableChunks!.length > 1) {
        // First chunk — merge text into the next chunk
        _editableChunks![1].text =
            '${_editableChunks![index].text} ${_editableChunks![1].text}'
                .trim();
      }
      _editableChunks!.removeAt(index);
    });
  }

  /// Delete all chunk labels for a given speaker — merge each into adjacent chunks.
  void _deleteAllChunkLabelsForSpeaker(int speaker) {
    if (_editableChunks == null) return;
    setState(() {
      // Work backwards to preserve indices
      for (int i = _editableChunks!.length - 1; i >= 0; i--) {
        if (_editableChunks![i].speaker != speaker) continue;
        if (_editableChunks!.length <= 1) break; // Always keep at least one

        if (i > 0) {
          _editableChunks![i - 1].text =
              '${_editableChunks![i - 1].text} ${_editableChunks![i].text}'
                  .trim();
        } else if (_editableChunks!.length > 1) {
          _editableChunks![1].text =
              '${_editableChunks![i].text} ${_editableChunks![1].text}'.trim();
        }
        _editableChunks!.removeAt(i);
      }
    });
  }

  /// Move speaker label UP — steal the last word from previous chunk.
  void _moveLabelUp(int index) {
    if (index <= 0 || _editableChunks == null) return;
    final prev = _editableChunks![index - 1];
    final curr = _editableChunks![index];
    final prevWords = prev.text.split(RegExp(r'\s+'));
    if (prevWords.length <= 1) return; // Can't steal the only word
    final stolen = prevWords.removeLast();
    setState(() {
      prev.text = prevWords.join(' ');
      curr.text = '$stolen ${curr.text}'.trim();
    });
  }

  /// Move speaker label DOWN — give the first word to the next chunk.
  void _moveLabelDown(int index) {
    if (_editableChunks == null || index >= _editableChunks!.length - 1) return;
    final curr = _editableChunks![index];
    final next = _editableChunks![index + 1];
    final currWords = curr.text.split(RegExp(r'\s+'));
    if (currWords.length <= 1) return;
    final given = currWords.removeLast();
    setState(() {
      curr.text = currWords.join(' ');
      next.text = '$given ${next.text}'.trim();
    });
  }

  /// Split a chunk at a word boundary, creating a new speaker turn.
  void _splitChunk(int index, String beforeText, String afterText) {
    if (_editableChunks == null) return;
    final chunk = _editableChunks![index];
    if (afterText.trim().isEmpty || beforeText.trim().isEmpty) return;
    setState(() {
      chunk.text = beforeText.trim();
      _editableChunks!.insert(
        index + 1,
        _EditableSpeakerChunk(
          speaker: chunk.speaker,
          text: afterText.trim(),
          startSeconds: chunk.startSeconds,
          labelOverride: chunk.labelOverride,
        ),
      );
    });
  }

  /// Merge a chunk with the previous chunk (backspace at start).
  void _mergeWithPrevious(int index) {
    if (index <= 0 || _editableChunks == null) return;
    final prev = _editableChunks![index - 1];
    final curr = _editableChunks![index];
    setState(() {
      prev.text = '${prev.text} ${curr.text}'.trim();
      _editableChunks!.removeAt(index);
    });
  }

  /// Save structural edits back: rebuild transcript text and persist.
  Future<void> _saveDiarizedEdits() async {
    if (_editableChunks == null || _editableChunks!.isEmpty) return;

    // Rebuild the flat transcript text from chunks
    final buffer = StringBuffer();
    for (final chunk in _editableChunks!) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(chunk.text);
    }
    final newText = buffer.toString().trim();

    // Persist the transcript text
    await _folderRepo.updateTranscriptionText(
      widget.recording.audioPath,
      newText,
    );

    // Persist any per-instance label overrides as global speaker renames
    // (only for chunks where the user set a custom label).
    for (final chunk in _editableChunks!) {
      if (chunk.labelOverride != null &&
          chunk.labelOverride != _speakerLabels[chunk.speaker]) {
        // Keep it as a per-instance override — do NOT write to global labels
      }
    }

    setState(() {
      _transcriptText = newText;
      _isEditingDiarizedTranscript = false;
      _isUserCorrected = true;
      _transcriptSegments = null; // Invalidate Whisper segments
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transcript saved.')));
    }
  }

  // H1-32 + H1-33 + D-01: Interactive transcript with speaker attribution,
  // search highlighting and tappable timestamps.
  Widget _buildInteractiveTranscript() {
    final text = _transcriptText ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    final hasDiarization =
        _diarizationSegments != null && _diarizationSegments!.isNotEmpty;

    // Split transcript into lines for speaker attribution
    if (hasDiarization && kDiarizationEnabled) {
      return _buildDiarizedTranscript(text);
    }

    // ── Fallback: original timestamp + search highlighting ──
    return _buildPlainTranscript(text);
  }

  /// Renders transcript with speaker labels injected at turn boundaries.
  ///
  /// Two paths:
  ///   • If we have per-segment Whisper timestamps (transcribed under schema
  ///     v16 or later), align each segment to the diarization speaker that
  ///     owns its midpoint. Accurate to the segment.
  ///   • Otherwise fall back to the legacy proportional char-position
  ///     mapping. Used only for older recordings that pre-date segment
  ///     persistence.
  Widget _buildDiarizedTranscript(String text) {
    final segments = _diarizationSegments!;
    final totalDurationS = widget.recording.durationMs / 1000.0;

    if (totalDurationS <= 0) {
      return _buildPlainTranscript(text);
    }

    // Sort and merge consecutive same-speaker diarization segments.
    final sortedSegs = List<DiarizationSegment>.from(segments)
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    final merged = <DiarizationSegment>[];
    for (final seg in sortedSegs) {
      if (merged.isNotEmpty && merged.last.speaker == seg.speaker) {
        final prev = merged.removeLast();
        merged.add(
          DiarizationSegment(
            speaker: prev.speaker,
            startSeconds: prev.startSeconds,
            endSeconds: seg.endSeconds,
          ),
        );
      } else {
        merged.add(seg);
      }
    }
    if (merged.isEmpty) return _buildPlainTranscript(text);

    int speakerForTimestamp(double ts) {
      for (final seg in merged) {
        if (ts >= seg.startSeconds && ts < seg.endSeconds) return seg.speaker;
      }
      int bestSpeaker = merged.first.speaker;
      double bestDist = double.infinity;
      for (final seg in merged) {
        final mid = (seg.startSeconds + seg.endSeconds) / 2;
        final dist = (ts - mid).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestSpeaker = seg.speaker;
        }
      }
      return bestSpeaker;
    }

    // Split each Whisper segment at sentence boundaries so a speaker
    // turn that occurs mid-segment can be aligned correctly. Without
    // this, multi-sentence Whisper segments collapse to one speaker.
    final whisperSegs = _transcriptSegments == null
        ? null
        : splitWhisperSegmentsBySentence(_transcriptSegments!);
    final chunks = <_SpeakerChunk>[];

    if (whisperSegs != null && whisperSegs.isNotEmpty) {
      // ── Accurate path: align Whisper segments to diarization speakers ──
      int? currentSpeaker;
      final buf = StringBuffer();
      double chunkStartTs = 0;

      for (final seg in whisperSegs) {
        final cleaned = seg.text.trim();
        if (cleaned.isEmpty) continue;
        // Overlap-weighted majority: pick the speaker who occupies the most
        // of [start, end], not the one who happens to own the midpoint.
        // Eliminates the "midpoint lands in a 200ms wrong-speaker sliver"
        // failure mode that made labels appear to flip mid-utterance.
        final speaker =
            DiarizationSegment.speakerByOverlap(
              seg.startSeconds,
              seg.endSeconds,
              merged,
            ) ??
            speakerForTimestamp((seg.startSeconds + seg.endSeconds) / 2);

        if (speaker != currentSpeaker) {
          if (currentSpeaker != null && buf.isNotEmpty) {
            chunks.add(
              _SpeakerChunk(
                speaker: currentSpeaker,
                text: buf.toString().trim(),
                startSeconds: chunkStartTs,
              ),
            );
            buf.clear();
          }
          currentSpeaker = speaker;
          chunkStartTs = seg.startSeconds;
        }
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(cleaned);
      }
      if (currentSpeaker != null && buf.isNotEmpty) {
        chunks.add(
          _SpeakerChunk(
            speaker: currentSpeaker,
            text: buf.toString().trim(),
            startSeconds: chunkStartTs,
          ),
        );
      }
    } else {
      // ── Legacy path: proportional char-position mapping ──
      final totalTextLen = text.length;
      final wordPattern = RegExp(r'\S+');
      final wordMatches = wordPattern.allMatches(text).toList();
      if (wordMatches.isEmpty) return _buildPlainTranscript(text);

      int? currentSpeaker;
      final wordBuffer = StringBuffer();
      double chunkStartTs = 0;

      for (final m in wordMatches) {
        final charMid = (m.start + m.end) / 2;
        final fraction = (charMid / totalTextLen).clamp(0.0, 1.0);
        final wordTs = fraction * totalDurationS;
        final speaker = speakerForTimestamp(wordTs);

        if (speaker != currentSpeaker) {
          if (currentSpeaker != null && wordBuffer.isNotEmpty) {
            chunks.add(
              _SpeakerChunk(
                speaker: currentSpeaker,
                text: wordBuffer.toString().trim(),
                startSeconds: chunkStartTs,
              ),
            );
            wordBuffer.clear();
          }
          currentSpeaker = speaker;
          chunkStartTs = wordTs;
        }
        if (wordBuffer.isNotEmpty) wordBuffer.write(' ');
        wordBuffer.write(m.group(0)!);
      }
      if (currentSpeaker != null && wordBuffer.isNotEmpty) {
        chunks.add(
          _SpeakerChunk(
            speaker: currentSpeaker,
            text: wordBuffer.toString().trim(),
            startSeconds: chunkStartTs,
          ),
        );
      }
    }

    if (chunks.isEmpty) {
      return _buildPlainTranscript(text);
    }

    // ── Populate editable chunks from alignment output (once) ──
    _editableChunks ??= chunks
        .map((c) => _EditableSpeakerChunk.fromChunk(c))
        .toList();
    final editChunks = _editableChunks!;
    final isEditing = _isEditingDiarizedTranscript;

    // ── Render widgets ──
    final widgets = <Widget>[];

    // Edit / Save toolbar
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isEditing) ...[
              TextButton.icon(
                icon: const Icon(Icons.close, size: 16),
                label: Text(
                  'Cancel',
                  style: KrakenText.bodySm(color: KrakenColors.textMuted),
                ),
                onPressed: () => setState(() {
                  _isEditingDiarizedTranscript = false;
                  _editableChunks = null; // Reset to original
                }),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KrakenColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                onPressed: _saveDiarizedEdits,
              ),
            ] else
              TextButton.icon(
                icon: const Icon(
                  Icons.edit_note,
                  size: 16,
                  color: KrakenColors.accent,
                ),
                label: Text(
                  'Edit Speakers',
                  style: KrakenText.bodySm(color: KrakenColors.accent),
                ),
                onPressed: () =>
                    setState(() => _isEditingDiarizedTranscript = true),
              ),
          ],
        ),
      ),
    );

    int? lastSpeaker;

    for (int i = 0; i < editChunks.length; i++) {
      final chunk = editChunks[i];
      final speaker = chunk.speaker;
      final color = _speakerColors[speaker % _speakerColors.length];
      final label =
          chunk.labelOverride ??
          _speakerLabels[speaker] ??
          'Speaker ${speaker + 1}';
      final tsLabel = _formatSecondsAsTimestamp(chunk.startSeconds);

      // Always show speaker chip for each chunk in edit mode;
      // in read mode, only at turn changes.
      final showChip = isEditing || speaker != lastSpeaker;

      if (showChip) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: lastSpeaker == null ? 0 : 14,
              bottom: 4,
            ),
            child: Row(
              children: [
                // Speaker name chip (tappable to rename)
                GestureDetector(
                  onTap: isEditing
                      ? () => _showChunkLabelActions(i)
                      : () => _showSpeakerRenameDialog(speaker, label),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withValues(alpha: isEditing ? 0.7 : 0.4),
                        width: isEditing ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: KrakenText.bodySm(
                            color: color,
                          ).copyWith(fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                        if (isEditing) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit,
                            size: 10,
                            color: color.withValues(alpha: 0.6),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Timestamp chip (tappable to seek audio)
                GestureDetector(
                  onTap: () {
                    final pos = Duration(
                      milliseconds: (chunk.startSeconds * 1000).round(),
                    );
                    _player.seek(pos);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: KrakenColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tsLabel,
                      style: KrakenText.bodySm(color: KrakenColors.accent)
                          .copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                    ),
                  ),
                ),
                // Move up/down arrows (edit mode only)
                if (isEditing) ...[
                  const Spacer(),
                  if (i > 0)
                    _buildMoveButton(
                      icon: Icons.arrow_upward,
                      tooltip: 'Move label up (steal word)',
                      onTap: () => _moveLabelUp(i),
                    ),
                  if (i < editChunks.length - 1)
                    _buildMoveButton(
                      icon: Icons.arrow_downward,
                      tooltip: 'Move label down (give word)',
                      onTap: () => _moveLabelDown(i),
                    ),
                  if (i > 0)
                    _buildMoveButton(
                      icon: Icons.merge,
                      tooltip: 'Merge with previous',
                      onTap: () => _mergeWithPrevious(i),
                    ),
                ],
              ],
            ),
          ),
        );
        lastSpeaker = speaker;
      }

      // Render the text chunk with a coloured left border.
      if (isEditing) {
        // Editable text field for structural editing
        widgets.add(
          Container(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: color.withValues(alpha: 0.4), width: 2),
              ),
            ),
            child: TextFormField(
              initialValue: chunk.text,
              maxLines: null,
              style: KrakenText.bodyLg().copyWith(height: 1.6),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
              ),
              onChanged: (val) => chunk.text = val,
            ),
          ),
        );
      } else {
        final spans = _buildSearchHighlightedSpans(chunk.text);
        widgets.add(
          Container(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: color.withValues(alpha: 0.4), width: 2),
              ),
            ),
            child: Text.rich(
              TextSpan(children: spans),
              style: KrakenText.bodyLg().copyWith(height: 1.6),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Small icon button for move-up/down/merge in structural edit mode.
  Widget _buildMoveButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: KrakenColors.textMuted),
        ),
      ),
    );
  }

  /// Renders the transcript without diarization — timestamps + search only.
  Widget _buildPlainTranscript(String text) {
    final timestampRegex = RegExp(r'\[\d{1,2}:\d{2}(?::\d{2})?\]');
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    final matches = timestampRegex.allMatches(text).toList();

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.addAll(
          _buildSearchHighlightedSpans(text.substring(lastEnd, match.start)),
        );
      }

      final tsText = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => _seekToTimestamp(tsText),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: KrakenColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                tsText,
                style: KrakenText.bodySm(color: KrakenColors.accent).copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  fontSize: 8.5, // 35% smaller than bodySm (13)
                ),
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.addAll(_buildSearchHighlightedSpans(text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: KrakenText.bodyLg().copyWith(height: 1.6),
    );
  }

  // H1-32: Build text spans with search term highlighting
  List<InlineSpan> _buildSearchHighlightedSpans(String text) {
    if (_searchQuery.isEmpty || text.isEmpty) {
      return [TextSpan(text: text)];
    }

    final spans = <InlineSpan>[];
    final queryLower = _searchQuery.toLowerCase();
    final textLower = text.toLowerCase();
    int start = 0;

    while (true) {
      final idx = textLower.indexOf(queryLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + _searchQuery.length),
          style: TextStyle(
            backgroundColor: KrakenColors.accent.withValues(alpha: 0.3),
            color: KrakenColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = idx + _searchQuery.length;
    }

    return spans;
  }

  /// Compact style label + dropdown that appears inside the summary card.
  /// Changing the style auto-regenerates the summary.
  static const _summaryStyleLabels = {
    'concise': 'Concise',
    'detailed': 'Detailed',
    'bullets': 'Bullet Points',
  };

  Widget _buildSummaryStyleBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Icon(Icons.style, size: 14, color: KrakenColors.textMuted),
          const SizedBox(width: 6),
          Text(
            'Style:',
            style: KrakenText.caption(color: KrakenColors.textMuted),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            decoration: BoxDecoration(
              color: KrakenColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: KrakenColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _summaryStyle,
                isDense: true,
                dropdownColor: KrakenColors.surfaceElevated,
                style: KrakenText.caption(color: KrakenColors.textPrimary),
                items: _summaryStyleLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null && v != _summaryStyle) {
                    setState(() => _summaryStyle = v);
                    _saveSummaryStyle(v);
                    // Auto-regenerate with new style
                    setState(() => _summaryJson = null);
                    _generateSummary();
                  }
                },
              ),
            ),
          ),
          const Spacer(),
          // Show which style was used for current summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: KrakenColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _summaryStyleLabels[_summaryStyle] ?? 'Concise',
              style: KrakenText.caption(
                color: KrakenColors.accent,
              ).copyWith(fontWeight: FontWeight.w600, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBlock() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_isGeneratingSummary)
        SummaryDraftCard(ownerKey: 'audio:${widget.recording.audioPath}'),
      _buildSummaryContent(),
    ],
  );

  Widget _buildSummaryContent() {
    if (_isGeneratingSummary) {
      return SummaryProgressPanel(
        progress: _summaryProgress,
        phase: _summaryPhase.isEmpty ? 'Preparing summary...' : _summaryPhase,
        startedAt: _summaryStartedAt ??= DateTime.now(),
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
          raw = lines
              .sublist(
                1,
                lines.length - (lines.last.trim().startsWith('```') ? 1 : 0),
              )
              .join('\n')
              .trim();
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
                  icon: const Icon(
                    Icons.refresh,
                    color: KrakenColors.accent,
                    size: 20,
                  ),
                  tooltip: 'Regenerate',
                  onPressed: () {
                    setState(() => _summaryJson = null);
                    _generateSummary();
                  },
                ),
              ],
            ),
            _buildSummaryStyleBar(),
            const SizedBox(height: KrakenSpacing.s3),
            SelectableText(
              cleanText,
              style: KrakenText.bodyLg().copyWith(height: 1.6),
            ),
          ],
        ),
      );
    }

    // Support both old format ("summary") and new format ("tldr")
    final tldr = _cleanSummaryText(
      (parsed['tldr'] ?? parsed['summary'] ?? 'No summary available.')
          as String,
    );
    final keyPoints = ((parsed['key_points'] as List<dynamic>?) ?? [])
        .map((e) => _cleanSummaryText(e.toString()))
        .toList();
    final decisions = ((parsed['decisions'] as List<dynamic>?) ?? [])
        .map((e) => _cleanSummaryText(e.toString()))
        .toList();
    final actions = ((parsed['action_items'] as List<dynamic>?) ?? [])
        .map((e) => _cleanSummaryText(e.toString()))
        .toList();
    final openQuestions = ((parsed['open_questions'] as List<dynamic>?) ?? [])
        .map((e) => _cleanSummaryText(e.toString()))
        .toList();

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
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: KrakenSpacing.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: KrakenColors.accent,
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      item.toString(),
                      style: KrakenText.bodyLg().copyWith(height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
              Expanded(
                child: Text('AI Summary', style: KrakenText.displayMd()),
              ),
              IconButton(
                icon: const Icon(
                  Icons.tune,
                  color: KrakenColors.accent,
                  size: 20,
                ),
                tooltip: 'Refine Summary',
                onPressed: _showRefineDialog,
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: KrakenColors.accent,
                  size: 20,
                ),
                tooltip: 'Regenerate Summary',
                onPressed: () {
                  setState(() => _summaryJson = null);
                  _generateSummary();
                },
              ),
            ],
          ),
          _buildSummaryStyleBar(),
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
                  style: KrakenText.bodySm(
                    color: KrakenColors.accent,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          const SizedBox(height: KrakenSpacing.s3),
          // Summary
          Text(
            'Summary',
            style: KrakenText.displayMd().copyWith(
              fontSize: 13,
              color: KrakenColors.accent,
            ),
          ),
          const SizedBox(height: KrakenSpacing.s2),
          SelectableText(
            tldr,
            style: KrakenText.bodyLg().copyWith(height: 1.6),
          ),
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
                  icon: const Icon(
                    Icons.chevron_left,
                    color: KrakenColors.textMuted,
                  ),
                  onPressed: _viewingVersionIndex < _summaryVersions.length - 1
                      ? () {
                          final newIdx = _viewingVersionIndex + 1;
                          setState(() {
                            _viewingVersionIndex = newIdx;
                            _summaryJson =
                                _summaryVersions[newIdx]['summary_json']
                                    as String;
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
                  icon: const Icon(
                    Icons.chevron_right,
                    color: KrakenColors.textMuted,
                  ),
                  onPressed: _viewingVersionIndex > -1
                      ? () async {
                          final newIdx = _viewingVersionIndex - 1;
                          if (newIdx == -1) {
                            // Go back to current
                            final current = await _folderRepo.getSummaryJson(
                              widget.recording.audioPath,
                            );
                            if (mounted) {
                              setState(() {
                                _viewingVersionIndex = -1;
                                _summaryJson = current;
                              });
                            }
                          } else {
                            setState(() {
                              _viewingVersionIndex = newIdx;
                              _summaryJson =
                                  _summaryVersions[newIdx]['summary_json']
                                      as String;
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
                    final versionJson =
                        _summaryVersions[_viewingVersionIndex]['summary_json']
                            as String;
                    await _folderRepo.restoreSummaryVersion(
                      widget.recording.audioPath,
                      versionJson,
                    );
                    await _loadTranscript();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Previous version restored as current.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Restore This Version',
                    style: KrakenText.bodySm(color: KrakenColors.accent),
                  ),
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
                description:
                    'Audio removed once transcription completes. Saves the most space.',
              ),
              _retentionOption(
                ctx,
                policy: '90_day',
                icon: Icons.event,
                label: '90-day retention',
                description:
                    'Audio kept for 90 days, then automatically removed.',
              ),
              _retentionOption(
                ctx,
                policy: 'keep_forever',
                icon: Icons.all_inclusive,
                label: 'Keep until I delete',
                description:
                    'Audio preserved indefinitely. Still subject to storage cap.',
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
    final isActive = _retentionPolicy == policy;
    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? KrakenColors.accent : KrakenColors.textMuted,
      ),
      title: Text(
        label,
        style: KrakenText.bodyMd(
          color: isActive ? KrakenColors.accent : KrakenColors.textPrimary,
        ),
      ),
      subtitle: Text(
        description,
        style: KrakenText.bodySm(
          color: KrakenColors.textMuted,
        ).copyWith(fontSize: 11),
      ),
      trailing: isActive
          ? const Icon(Icons.check, color: KrakenColors.accent, size: 18)
          : null,
      onTap: () async {
        Navigator.pop(ctx);
        await _folderRepo.setRetentionPolicy(widget.recording.id, policy);
        if (mounted) {
          setState(() => _retentionPolicy = policy);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Retention set to: $label')));
        }
      },
    );
  }
}
