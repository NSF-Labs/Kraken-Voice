import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:kraken_hub/kernel/vault/vault_service.dart';
import 'package:kraken_hub/kernel/inference/local_inference_service.dart';
import 'package:kraken_hub/shell/inference/model_manager.dart';
import 'package:kraken_hub/kernel/notifications/kraken_notification_service.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'package:whisper_ggml_plus_ffmpeg/whisper_ggml_plus_ffmpeg.dart';

enum TranscriptionStatus { pending, processing, completed, failed }

class TranscriptionJob {
  final String id;
  final String audioPath;
  final TranscriptionStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? transcriptionText;

  TranscriptionJob({
    required this.id,
    required this.audioPath,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.transcriptionText,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'audio_path': audioPath,
      'status': status.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'started_at': startedAt?.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'transcription_text': transcriptionText,
    };
  }

  factory TranscriptionJob.fromMap(Map<String, dynamic> map) {
    return TranscriptionJob(
      id: map['id'],
      audioPath: map['audio_path'],
      status: TranscriptionStatus.values.firstWhere((e) => e.name == map['status']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      startedAt: map['started_at'] != null ? DateTime.fromMillisecondsSinceEpoch(map['started_at']) : null,
      completedAt: map['completed_at'] != null ? DateTime.fromMillisecondsSinceEpoch(map['completed_at']) : null,
      transcriptionText: map['transcription_text'],
    );
  }
}

class TranscriptionEngine {
  // Singleton
  static final TranscriptionEngine _instance = TranscriptionEngine._internal();
  factory TranscriptionEngine() => _instance;
  TranscriptionEngine._internal() {
    WhisperFFmpegConverter.register();
  }

  final WhisperController _controller = WhisperController();
  final WhisperModel _model = WhisperModel.base;
  
  bool _isWorkerRunning = false;
  
  // State for UI
  final ValueNotifier<bool> isModelDownloading = ValueNotifier(false);
  final ValueNotifier<double> modelDownloadProgress = ValueNotifier(0.0);
  final ValueNotifier<bool> isModelLoaded = ValueNotifier(false);
  
  final ValueNotifier<List<TranscriptionJob>> activeJobs = ValueNotifier([]);
  
  // Progress estimation: maps audioPath -> estimated progress 0.0-1.0
  final ValueNotifier<Map<String, double>> transcriptionProgress = ValueNotifier({});
  Timer? _progressTimer;

  Future<void> _refreshJobs(VaultService vault) async {
    if (!vault.isOpen) return;

    final results = await vault.db.query(
      'transcription_jobs',
      orderBy: 'created_at DESC',
    );
    activeJobs.value = results.map((e) => TranscriptionJob.fromMap(e)).toList();
  }

  /// Queues a new transcription job and ensures the worker is running.
  Future<String> queueJob(VaultService vault, String audioPath) async {
    final job = TranscriptionJob(
      id: const Uuid().v4(),
      audioPath: audioPath,
      status: TranscriptionStatus.pending,
      createdAt: DateTime.now(),
    );

    await vault.db.insert('transcription_jobs', job.toMap());
    await _refreshJobs(vault);
    
    // Ensure the worker is running — if it crashed or was never started,
    // this will restart it. If already running, startWorker is a no-op.
    startWorker(vault);
    
    return job.id;
  }

  Future<void> downloadModel() async {
    isModelDownloading.value = true;
    try {
      await _controller.downloadModel(_model);
    } catch (e) {
      isModelDownloading.value = false;
      throw Exception('Failed to download model: $e');
    }
    isModelDownloading.value = false;
  }

  /// Checks if the Whisper model file is downloaded, and downloads it if not.
  Future<void> _ensureModelDownloaded() async {
    try {
      final modelPath = await _controller.getPath(_model);
      if (!await File(modelPath).exists()) {
        debugPrint('[TranscriptionEngine] Model not found at $modelPath — downloading...');
        isModelDownloading.value = true;
        await _controller.downloadModel(_model);
        isModelDownloading.value = false;
        debugPrint('[TranscriptionEngine] Model download complete.');
      }
    } catch (e) {
      isModelDownloading.value = false;
      debugPrint('[TranscriptionEngine] Failed to ensure model: $e');
      rethrow;
    }
  }

  void startWorker(VaultService vault) {
    if (_isWorkerRunning) return;
    _isWorkerRunning = true;
    
    if (vault.isOpen) {
      // Reset any orphaned 'processing' jobs from a previous session back to 'pending'
      vault.db.update(
        'transcription_jobs',
        {'status': TranscriptionStatus.pending.name},
        where: 'status = ?',
        whereArgs: [TranscriptionStatus.processing.name],
      ).then((_) {
        _refreshJobs(vault); // Load jobs immediately for UI
        _processNextJob(vault);
      });
    } else {
      _refreshJobs(vault);
      _processNextJob(vault);
    }
  }

  void stopWorker() {
    _isWorkerRunning = false;
  }

  Future<void> _processNextJob(VaultService vault) async {
    if (!_isWorkerRunning || !vault.isOpen) {
      _isWorkerRunning = false;
      return;
    }

    // Find the oldest pending job
    final results = await vault.db.query(
      'transcription_jobs',
      where: 'status = ?',
      whereArgs: [TranscriptionStatus.pending.name],
      orderBy: 'created_at ASC',
      limit: 1,
    );

    if (results.isEmpty) {
      // No pending jobs, wait and poll again
      await Future.delayed(const Duration(seconds: 2));
      _processNextJob(vault);
      return;
    }

    final jobMap = results.first;
    final job = TranscriptionJob.fromMap(jobMap);

    // Update status to processing
    await vault.db.update(
      'transcription_jobs',
      {
        'status': TranscriptionStatus.processing.name,
        'started_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [job.id],
    );
    await _refreshJobs(vault);

    // Start progress estimator
    // Look up the audio duration from the recordings table
    double estimatedDurationSec = 60.0; // fallback
    try {
      final recResult = await vault.db.query(
        'recordings',
        columns: ['duration_ms'],
        where: 'audio_path = ?',
        whereArgs: [job.audioPath],
        limit: 1,
      );
      if (recResult.isNotEmpty && recResult.first['duration_ms'] != null) {
        final durationMs = recResult.first['duration_ms'] as int;
        estimatedDurationSec = durationMs / 1000.0;
      }
    } catch (_) {}
    
    // Start progress tracking
    // Whisper provides no progress callback. We estimate based on elapsed time.
    // Empirical benchmark on S24 Ultra: processing takes ~0.35x audio duration.
    // We use a linear ramp to 90% during the estimated window, then a slow
    // log tail that asymptotes at 98% to handle variance in actual speed.
    final startTime = DateTime.now();
    final estimatedProcessingSec = estimatedDurationSec * 0.35; // calibrated to device
    
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final elapsedSec = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      double progress;
      if (elapsedSec < estimatedProcessingSec) {
        // Phase 1: linear ramp to 90%
        progress = 0.9 * (elapsedSec / estimatedProcessingSec);
      } else {
        // Phase 2: slow log tail from 90% toward 98%
        final overtime = elapsedSec - estimatedProcessingSec;
        progress = 0.9 + 0.08 * (1.0 - math.exp(-overtime / (estimatedProcessingSec * 0.5)));
      }
      final map = Map<String, double>.from(transcriptionProgress.value);
      map[job.audioPath] = progress.clamp(0.0, 0.98);
      transcriptionProgress.value = map;
    });

    // Ensure Whisper model is downloaded before attempting transcription
    try {
      await _ensureModelDownloaded();
    } catch (e) {
      debugPrint('Model download failed for job ${job.id}: $e');
      // Mark failed and move on
      await vault.db.update(
        'transcription_jobs',
        {'status': TranscriptionStatus.failed.name, 'completed_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [job.id],
      );
      await _refreshJobs(vault);
      _progressTimer?.cancel();
      _processNextJob(vault);
      return;
    }

    // Process transcription
    String? text;
    TranscriptionStatus finalStatus = TranscriptionStatus.completed;

    try {
      text = await transcribeFile(job.audioPath);
      if (text == "Transcription failed.") {
        finalStatus = TranscriptionStatus.failed;
      }
    } catch (e) {
      debugPrint('Transcription failed for job ${job.id}: $e');
      finalStatus = TranscriptionStatus.failed;
    }

    // Stop progress estimator and set to 100%
    _progressTimer?.cancel();
    _progressTimer = null;
    final progressMap = Map<String, double>.from(transcriptionProgress.value);
    progressMap[job.audioPath] = 1.0;
    transcriptionProgress.value = progressMap;
    // Clean up after a short delay so the UI can show 100%
    Future.delayed(const Duration(seconds: 2), () {
      final m = Map<String, double>.from(transcriptionProgress.value);
      m.remove(job.audioPath);
      transcriptionProgress.value = m;
    });

    // Update status to completed or failed
    await vault.db.update(
      'transcription_jobs',
      {
        'status': finalStatus.name,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
        'transcription_text': text,
      },
      where: 'id = ?',
      whereArgs: [job.id],
    );
    await _refreshJobs(vault);

    // Look up the recording title for the notification
    String recordingTitle = 'Recording';
    try {
      final recResult = await vault.db.query(
        'recordings',
        columns: ['title'],
        where: 'audio_path = ?',
        whereArgs: [job.audioPath],
        limit: 1,
      );
      if (recResult.isNotEmpty) {
        recordingTitle = recResult.first['title'] as String? ?? 'Recording';
      }
    } catch (_) {}

    // Fire system notification
    if (finalStatus == TranscriptionStatus.completed) {
      KrakenNotificationService().notifyTranscriptionComplete(recordingTitle);
    } else {
      KrakenNotificationService().notifyTranscriptionFailed(recordingTitle);
    }

    // Auto-tag if transcription succeeded
    if (finalStatus == TranscriptionStatus.completed && text != null && text.isNotEmpty) {
      _autoTagRecording(vault, job.audioPath, text);
    }

    // Process the next job immediately
    _processNextJob(vault);
  }

  Future<String> transcribeFile(String audioPath, {String lang = 'en'}) async {
    final result = await _controller.transcribe(
      model: _model,
      audioPath: audioPath,
      lang: lang,
      threads: 4, // Use multi-core parallelism for faster inference
      convert: true, // Let whisper_ggml_plus_ffmpeg convert m4a to wav
    );
    
    if (result == null) return "Transcription failed.";
    return result.transcription.text;
  }

  /// Generates topic tags from a transcript using Gemma, then persists them.
  /// Runs fire-and-forget so it doesn't block the transcription queue.
  void _autoTagRecording(VaultService vault, String audioPath, String transcriptText) async {
    try {
      // Find the recording ID for this audio path
      final recResult = await vault.db.query(
        'recordings',
        columns: ['id'],
        where: 'audio_path = ?',
        whereArgs: [audioPath],
        limit: 1,
      );
      if (recResult.isEmpty) return;
      final recordingId = recResult.first['id'] as String;

      // Check if Gemma model is available
      final modelManager = ModelManager();
      final hasModel = await modelManager.hasModel();

      List<String> tags;
      if (hasModel) {
        tags = await _generateTagsWithGemma(transcriptText);
      } else {
        tags = _extractKeywords(transcriptText);
      }

      if (tags.isEmpty) return;

      // Save tags to DB
      final now = DateTime.now().millisecondsSinceEpoch;
      // Clear existing auto-tags
      await vault.db.delete('recording_tags', where: 'recording_id = ?', whereArgs: [recordingId]);
      for (final tag in tags) {
        final cleaned = tag.trim().toLowerCase();
        if (cleaned.isEmpty || cleaned.length > 30) continue;
        await vault.db.insert('recording_tags', {
          'id': '${recordingId}_$cleaned',
          'recording_id': recordingId,
          'tag': cleaned,
          'created_at': now,
        });
      }
      debugPrint('[AutoTag] Tagged recording $recordingId with: $tags');
    } catch (e) {
      debugPrint('[AutoTag] Failed to auto-tag: $e');
      // Non-fatal — recording still works without tags
    }
  }

  /// Uses Gemma to generate topic tags from transcript text.
  Future<List<String>> _generateTagsWithGemma(String transcriptText) async {
    try {
      // Truncate transcript to fit context window
      String snippet = transcriptText;
      if (snippet.length > 2000) {
        snippet = '${snippet.substring(0, 2000)}\n\n[...truncated...]';
      }

      final prompt = '''Analyze this meeting transcript and return ONLY a comma-separated list of 3-5 topic tags. 
Tags should be short (1-2 words each), lowercase, and describe the key topics discussed.
Examples of good tags: budget, hiring, product launch, q3 planning, customer feedback

Transcript:
$snippet

Tags:''';

      final inference = LocalInferenceService();
      await inference.loadModel();
      
      final completer = Completer<String>();
      String buffer = '';
      
      inference.generateStream(prompt, maxTokens: 64).listen(
        (token) => buffer += token.text,
        onDone: () => completer.complete(buffer),
        onError: (e) => completer.completeError(e),
      );

      final rawOutput = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => buffer,
      );

      // Parse comma-separated tags
      return rawOutput
          .replaceAll('\n', ',')
          .split(',')
          .map((t) => t.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ''))
          .where((t) => t.isNotEmpty && t.length <= 30 && t.length >= 2)
          .take(5)
          .toList();
    } catch (e) {
      debugPrint('[AutoTag] Gemma tagging failed, falling back to keywords: $e');
      return _extractKeywords(transcriptText);
    }
  }

  /// Lightweight keyword extraction fallback when Gemma is unavailable.
  List<String> _extractKeywords(String text) {
    const stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
      'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
      'should', 'may', 'might', 'can', 'shall', 'it', 'its', 'this', 'that',
      'these', 'those', 'i', 'you', 'he', 'she', 'we', 'they', 'me', 'him',
      'her', 'us', 'them', 'my', 'your', 'his', 'our', 'their', 'what',
      'which', 'who', 'whom', 'when', 'where', 'why', 'how', 'not', 'no',
      'so', 'if', 'then', 'than', 'too', 'very', 'just', 'about', 'also',
      'up', 'out', 'all', 'some', 'any', 'each', 'every', 'both', 'few',
      'more', 'most', 'other', 'into', 'over', 'such', 'only', 'own',
      'same', 'like', 'get', 'got', 'go', 'going', 'know', 'think', 'thing',
      'things', 'want', 'need', 'make', 'made', 'say', 'said', 'well',
      'yeah', 'okay', 'right', 'really', 'actually', 'gonna', 'um', 'uh',
    };

    final words = text.toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !stopWords.contains(w));

    // Count word frequencies
    final freq = <String, int>{};
    for (final w in words) {
      freq[w] = (freq[w] ?? 0) + 1;
    }

    // Sort by frequency, take top 4
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(4).map((e) => e.key).toList();
  }
}

