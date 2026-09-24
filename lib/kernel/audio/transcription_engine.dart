import 'package:krak_en_voice/kernel/inference/drafted_summary_stream.dart';
import 'package:krak_en_voice/data/summary_draft_repository.dart';
import 'package:krak_en_voice/kernel/inference/summary_context.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:krak_en_voice/kernel/vault/vault_service.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/inference/model_manager.dart';
import 'package:krak_en_voice/kernel/notifications/kraken_notification_service.dart';
import 'package:krak_en_voice/data/summary_prompt.dart';
import 'package:krak_en_voice/kernel/vault/preferences_service.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'package:whisper_ggml_plus_ffmpeg/whisper_ggml_plus_ffmpeg.dart';

import 'whisper_segment.dart';

enum TranscriptionStatus { pending, processing, completed, failed }

class TranscriptionJob {
  final String id;
  final String audioPath;
  final TranscriptionStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? transcriptionText;
  final String language;
  final int retryCount;

  /// Maximum number of automatic retries before a job is marked permanently failed.
  static const int maxRetries = 3;

  TranscriptionJob({
    required this.id,
    required this.audioPath,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.transcriptionText,
    this.language = 'en',
    this.retryCount = 0,
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
      'language': language,
    };
  }

  factory TranscriptionJob.fromMap(Map<String, dynamic> map) {
    return TranscriptionJob(
      id: map['id'],
      audioPath: map['audio_path'],
      status: TranscriptionStatus.values.firstWhere(
        (e) => e.name == map['status'],
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      startedAt: map['started_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['started_at'])
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'])
          : null,
      transcriptionText: map['transcription_text'],
      language: map['language'] as String? ?? 'en',
      retryCount: map['retry_count'] as int? ?? 0,
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

  /// Public accessors for model existence checks in the download pipeline.
  WhisperController get controller => _controller;
  WhisperModel get model => _model;

  bool _isWorkerRunning = false;

  // State for UI
  final ValueNotifier<bool> isModelDownloading = ValueNotifier(false);
  final ValueNotifier<double> modelDownloadProgress = ValueNotifier(0.0);
  final ValueNotifier<bool> isModelLoaded = ValueNotifier(false);

  final ValueNotifier<List<TranscriptionJob>> activeJobs = ValueNotifier([]);

  // Progress estimation: maps audioPath -> estimated progress 0.0-1.0
  final ValueNotifier<Map<String, double>> transcriptionProgress =
      ValueNotifier({});
  // Descriptive phase labels: maps audioPath -> human-readable status
  final ValueNotifier<Map<String, String>> transcriptionPhase = ValueNotifier(
    {},
  );
  // Estimated token count: maps audioPath -> running token count
  final ValueNotifier<Map<String, int>> transcriptionTokens = ValueNotifier({});
  Timer? _progressTimer;

  /// True while _autoDiarizeRecording is running heavy native code.
  /// UI can check this before performing memory-intensive operations.
  final ValueNotifier<bool> isDiarizing = ValueNotifier(false);

  // ─── Queue status accessors ───────────────────────────────────────────────

  /// Number of pending jobs in the queue.
  int get pendingCount => activeJobs.value
      .where((j) => j.status == TranscriptionStatus.pending)
      .length;

  /// Number of currently processing jobs.
  int get processingCount => activeJobs.value
      .where((j) => j.status == TranscriptionStatus.processing)
      .length;

  /// All failed jobs.
  List<TranscriptionJob> get failedJobs => activeJobs.value
      .where((j) => j.status == TranscriptionStatus.failed)
      .toList();

  /// Whether the queue has any work in progress or pending.
  bool get isQueueBusy => pendingCount > 0 || processingCount > 0;

  /// Re-format stored Whisper segments with a new break threshold.
  /// This is a lightweight, CPU-only operation — no AI re-run needed.
  ///
  /// The `breakThreshold` controls how often line breaks are inserted.
  /// Two mechanisms work together:
  ///
  ///   **Gap-based** (primary — reacts to actual silence between segments):
  ///   • Gap ≥ `breakThreshold` → line break with new timestamp.
  ///   • Gap ≥ `breakThreshold × 3` → paragraph break (blank line).
  ///
  ///   **Elapsed-time** (secondary — prevents wall-of-text in continuous speech):
  ///   • Elapsed ≥ `breakThreshold × 10` → line break.
  ///   • Elapsed ≥ `breakThreshold × 30` → paragraph break.
  ///
  /// At low thresholds (0.1s), breaks are frequent and closely spaced.
  /// At high thresholds (3.0s), only significant pauses cause breaks,
  /// with safety line-breaks every ~30s of continuous speech.
  ///
  /// Returns the newly formatted text, or null if segments are empty.
  static String? reformatSegments(
    List<WhisperSegment> segments, {
    required double breakThreshold,
  }) {
    if (segments.isEmpty) return null;

    String fmtTs(double seconds) {
      final totalSec = seconds.round();
      final min = totalSec ~/ 60;
      final sec = totalSec % 60;
      return '[$min:${sec.toString().padLeft(2, '0')}]';
    }

    final buf = StringBuffer();
    double lastBreakAt = 0; // audio-seconds of the last inserted break

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final segText = seg.text.trim();
      if (segText.isEmpty) continue;

      if (i == 0) {
        // First segment — always gets a timestamp
        buf.write('${fmtTs(seg.startSeconds)} $segText');
        lastBreakAt = seg.startSeconds;
        continue;
      }

      final gap = seg.startSeconds - segments[i - 1].endSeconds;
      final elapsed = seg.startSeconds - lastBreakAt;

      if (gap >= breakThreshold * 3 || elapsed >= breakThreshold * 30) {
        // Long pause or very long continuous block → paragraph break
        buf.write('\n\n${fmtTs(seg.startSeconds)} $segText');
        lastBreakAt = seg.startSeconds;
      } else if (gap >= breakThreshold || elapsed >= breakThreshold * 10) {
        // Moderate pause or long continuous block → line break
        buf.write('\n${fmtTs(seg.startSeconds)} $segText');
        lastBreakAt = seg.startSeconds;
      } else {
        // Short / continuous → same line, flowing text
        buf.write(' $segText');
      }
    }

    final result = buf.toString().trim();
    return result.isEmpty ? null : result;
  }

  void _setPhase(String audioPath, String phase) {
    final map = Map<String, String>.from(transcriptionPhase.value);
    map[audioPath] = phase;
    transcriptionPhase.value = map;
  }

  void _clearPhase(String audioPath) {
    final map = Map<String, String>.from(transcriptionPhase.value);
    map.remove(audioPath);
    transcriptionPhase.value = map;
  }

  void _setTokens(String audioPath, int count) {
    final map = Map<String, int>.from(transcriptionTokens.value);
    map[audioPath] = count;
    transcriptionTokens.value = map;
  }

  void _clearTokens(String audioPath) {
    final map = Map<String, int>.from(transcriptionTokens.value);
    map.remove(audioPath);
    transcriptionTokens.value = map;
  }

  Future<void> _refreshJobs(VaultService vault) async {
    if (!vault.isOpen) return;

    final results = await vault.db.query(
      'transcription_jobs',
      orderBy: 'created_at DESC',
    );
    activeJobs.value = results.map((e) => TranscriptionJob.fromMap(e)).toList();
  }

  /// Queues a new transcription job and ensures the worker is running.
  Future<String> queueJob(
    VaultService vault,
    String audioPath, {
    String language = 'en',
  }) async {
    final job = TranscriptionJob(
      id: const Uuid().v4(),
      audioPath: audioPath,
      status: TranscriptionStatus.pending,
      createdAt: DateTime.now(),
      language: language,
    );

    await vault.db.insert('transcription_jobs', job.toMap());
    await _refreshJobs(vault);

    // Ensure the worker is running — if it crashed or was never started,
    // this will restart it. If already running, startWorker is a no-op.
    startWorker(vault);

    return job.id;
  }

  /// Convenience: checks for a per-recording override first, then falls back
  /// to the user's default language from prefs.
  Future<String> queueJobWithDefaultLanguage(
    VaultService vault,
    String audioPath,
  ) async {
    // 2A-08: Check per-recording language override
    String? override;
    try {
      final rows = await vault.db.query(
        'recordings',
        columns: ['language_override'],
        where: 'audio_path = ?',
        whereArgs: [audioPath],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        override = rows.first['language_override'] as String?;
      }
    } catch (_) {}

    if (override != null && override.isNotEmpty) {
      return queueJob(vault, audioPath, language: override);
    }

    final prefs = PreferencesService();
    final lang = await prefs.getString('default_language', defaultValue: 'en');
    return queueJob(vault, audioPath, language: lang);
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
        debugPrint(
          '[TranscriptionEngine] Model not found at $modelPath — downloading...',
        );
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
      vault.db
          .update(
            'transcription_jobs',
            {'status': TranscriptionStatus.pending.name},
            where: 'status = ?',
            whereArgs: [TranscriptionStatus.processing.name],
          )
          .then((_) {
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

  // ─── Queue management ─────────────────────────────────────────────────────

  /// Clears all failed jobs from the queue.
  Future<void> clearFailedJobs(VaultService vault) async {
    await vault.db.delete(
      'transcription_jobs',
      where: 'status = ?',
      whereArgs: [TranscriptionStatus.failed.name],
    );
    await _refreshJobs(vault);
  }

  /// Retries a specific failed job by resetting it to pending.
  Future<void> retryJob(VaultService vault, String jobId) async {
    await vault.db.update(
      'transcription_jobs',
      {
        'status': TranscriptionStatus.pending.name,
        'started_at': null,
        'completed_at': null,
      },
      where: 'id = ? AND status = ?',
      whereArgs: [jobId, TranscriptionStatus.failed.name],
    );
    await _refreshJobs(vault);
    startWorker(vault);
  }

  /// Cancels a pending (not yet processing) job.
  Future<void> cancelJob(VaultService vault, String jobId) async {
    await vault.db.delete(
      'transcription_jobs',
      where: 'id = ? AND status = ?',
      whereArgs: [jobId, TranscriptionStatus.pending.name],
    );
    await _refreshJobs(vault);
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
      // No pending jobs — stop the worker to avoid continuous polling.
      // It will be re-started automatically when queueJob() is called.
      debugPrint('[JobQueue] No pending jobs — worker idle, stopping.');
      _isWorkerRunning = false;
      return;
    }

    final jobMap = results.first;
    final job = TranscriptionJob.fromMap(jobMap);

    // Skip jobs for trashed recordings — delete the job and move on
    try {
      final recRows = await vault.db.rawQuery(
        '''
        SELECT is_trashed FROM recordings
        WHERE audio_path = ? LIMIT 1
      ''',
        [job.audioPath],
      );
      if (recRows.isNotEmpty && (recRows.first['is_trashed'] as int?) == 1) {
        debugPrint('[JobQueue] Skipping job ${job.id} — recording is trashed');
        await vault.db.delete(
          'transcription_jobs',
          where: 'id = ?',
          whereArgs: [job.id],
        );
        await _refreshJobs(vault);
        _processNextJob(vault);
        return;
      }
    } catch (_) {}

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
    // Empirical benchmark on S24 Ultra: processing takes ~0.20x audio duration.
    // (Calibrated from user feedback — transcription finishes faster than indicated.)
    // We use a linear ramp to 90% during the estimated window, then a slow
    // log tail that asymptotes at 98% to handle variance in actual speed.
    final startTime = DateTime.now();
    final estimatedProcessingSec =
        estimatedDurationSec * 0.20; // calibrated to device

    // Set initial phase label
    _setPhase(job.audioPath, 'Preparing audio for transcription...');

    _progressTimer?.cancel();
    _setTokens(job.audioPath, 0); // reset token counter
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final elapsedSec =
          DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      double progress;
      if (elapsedSec < estimatedProcessingSec) {
        // Phase 1: linear ramp to 82% — reserves headroom for tail + diarization
        progress = 0.82 * (elapsedSec / estimatedProcessingSec);
      } else {
        // Phase 2: curve from 82% → 95%.
        // The last 4% (96-100%) is reserved for diarization so users
        // never see 100% while speakers are still being identified.
        final overtime = elapsedSec - estimatedProcessingSec;
        final decayConstant = estimatedProcessingSec * 0.25;
        progress = 0.82 + 0.14 * (1.0 - math.exp(-overtime / decayConstant));
      }
      final map = Map<String, double>.from(transcriptionProgress.value);
      map[job.audioPath] = progress.clamp(0.0, 0.96);
      transcriptionProgress.value = map;

      // Estimate token throughput: Whisper base on S24 Ultra ≈ 25 tokens/sec.
      // Only count tokens during the active decode phase (after model load).
      if (progress >= 0.10) {
        final activeDecodeSec = elapsedSec - (estimatedProcessingSec * 0.10);
        if (activeDecodeSec > 0) {
          _setTokens(job.audioPath, (activeDecodeSec * 25).round());
        }
      }

      // Update phase label based on progress
      if (progress < 0.10) {
        _setPhase(job.audioPath, 'Loading speech recognition model...');
      } else if (progress < 0.85) {
        final pct = (progress * 100).toInt();
        _setPhase(job.audioPath, 'Transcribing audio — $pct% complete...');
      } else {
        _setPhase(job.audioPath, 'Finalizing transcript...');
      }
    });

    // Ensure Whisper model is downloaded before attempting transcription
    _setPhase(job.audioPath, 'Checking speech model...');
    try {
      await _ensureModelDownloaded();
    } catch (e) {
      debugPrint('Model download failed for job ${job.id}: $e');
      _setPhase(job.audioPath, 'Model download failed');
      // Mark failed and move on
      await vault.db.update(
        'transcription_jobs',
        {
          'status': TranscriptionStatus.failed.name,
          'completed_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [job.id],
      );
      await _refreshJobs(vault);
      _progressTimer?.cancel();
      _clearPhase(job.audioPath);
      _clearTokens(job.audioPath);
      _processNextJob(vault);
      return;
    }

    // Process transcription
    _setPhase(job.audioPath, 'Transcribing audio on device...');
    String? text;
    List<WhisperSegment>? segments;
    TranscriptionStatus finalStatus = TranscriptionStatus.completed;

    try {
      // Diagnostic: verify audio file exists and has content
      final audioFile = File(job.audioPath);
      final fileExists = await audioFile.exists();
      final fileSize = fileExists ? await audioFile.length() : 0;
      debugPrint('🎤 [TRANSCRIPTION] Starting job ${job.id}');
      debugPrint('   Audio: ${job.audioPath}');
      debugPrint(
        '   Exists: $fileExists, Size: $fileSize bytes, Lang: ${job.language}',
      );

      if (!fileExists || fileSize < 1000) {
        debugPrint(
          '❌ [TRANSCRIPTION] Audio file missing or too small ($fileSize bytes)',
        );
        finalStatus = TranscriptionStatus.failed;
      } else {
        final response = await transcribeFileWithSegments(
          job.audioPath,
          lang: job.language,
        );
        if (response == null) {
          debugPrint('❌ [TRANSCRIPTION] Whisper returned null result');
          finalStatus = TranscriptionStatus.failed;
        } else {
          final raw = response.segments;
          if (raw != null && raw.isNotEmpty) {
            segments = raw
                .map(
                  (s) => WhisperSegment(
                    startSeconds: s.fromTs.inMilliseconds / 1000.0,
                    endSeconds: s.toTs.inMilliseconds / 1000.0,
                    text: s.text,
                  ),
                )
                .toList();

            // ── Format text with timestamps and pause-aware breaks ──
            final prefs = PreferencesService();
            final breakThreshold = await prefs.getDouble(
              'break_threshold',
              defaultValue: 1.5,
            );

            text =
                reformatSegments(segments, breakThreshold: breakThreshold) ??
                '';
          } else {
            // Fallback: no segments available, use raw text
            text = response.text;
          }
          debugPrint(
            '✅ [TRANSCRIPTION] Success: ${text.length} chars, '
            '${segments?.length ?? 0} segments',
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [TRANSCRIPTION] Exception for job ${job.id}: $e');
      debugPrint('   Stack: $stackTrace');
      finalStatus = TranscriptionStatus.failed;
    }

    // Stop progress estimator — hold at 96% for diarization headroom
    _progressTimer?.cancel();
    _progressTimer = null;
    final progressMap = Map<String, double>.from(transcriptionProgress.value);
    if (finalStatus == TranscriptionStatus.completed) {
      // Hold at 96% — the remaining 4% is consumed by diarization.
      progressMap[job.audioPath] = 0.96;
      transcriptionProgress.value = progressMap;
      _setPhase(job.audioPath, 'Finalizing transcript...');

      // Snap token count to actual — Whisper tokens ≈ words × 1.3
      if (text != null && text.isNotEmpty) {
        final wordCount = text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        _setTokens(job.audioPath, (wordCount * 1.3).round());
      }
    } else {
      progressMap[job.audioPath] = 1.0;
      transcriptionProgress.value = progressMap;
      _setPhase(job.audioPath, 'Transcription failed');
      Future.delayed(const Duration(seconds: 2), () {
        final m = Map<String, double>.from(transcriptionProgress.value);
        m.remove(job.audioPath);
        transcriptionProgress.value = m;
        _clearPhase(job.audioPath);
        _clearTokens(job.audioPath);
      });
    }

    // Update status — with automatic retry for transient failures
    if (finalStatus == TranscriptionStatus.failed &&
        job.retryCount < TranscriptionJob.maxRetries) {
      // Re-queue with exponential backoff: 5s, 20s, 45s
      final backoffSeconds = 5 * math.pow(job.retryCount + 1, 2).toInt();
      debugPrint(
        '[JobQueue] ⟳ Retry ${job.retryCount + 1}/${TranscriptionJob.maxRetries} '
        'for job ${job.id} in ${backoffSeconds}s',
      );
      _setPhase(
        job.audioPath,
        'Retrying in ${backoffSeconds}s (attempt ${job.retryCount + 2})...',
      );

      await vault.db.update(
        'transcription_jobs',
        {
          'status': TranscriptionStatus.pending.name,
          'started_at': null,
          'completed_at': null,
          'retry_count': job.retryCount + 1,
        },
        where: 'id = ?',
        whereArgs: [job.id],
      );
      await _refreshJobs(vault);

      // Delay before retrying
      await Future.delayed(Duration(seconds: backoffSeconds));
      _clearPhase(job.audioPath);
      _clearTokens(job.audioPath);
      _processNextJob(vault);
      return;
    }

    // Permanent outcome: update the job record
    await vault.db.update(
      'transcription_jobs',
      {
        'status': finalStatus.name,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
        'transcription_text': text,
        'transcription_segments_json': segments == null
            ? null
            : jsonEncode(segments.map((s) => s.toJson()).toList()),
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

    // Auto-tag if transcription succeeded (fast — keyword or Gemma tagging)
    if (finalStatus == TranscriptionStatus.completed &&
        text != null &&
        text.isNotEmpty) {
      _autoTagRecording(vault, job.audioPath, text);
    }

    // Diarization is now user-triggered (manual) from the transcript view.
    // Skip auto-diarization; proceed to summary + completion.
    if (finalStatus == TranscriptionStatus.completed) {
      // Release the Whisper model to free GPU/CPU memory
      try {
        await releaseWhisper();
      } catch (_) {}

      // Auto-generate AI summary (uses Gemma)
      if (text != null && text.isNotEmpty) {
        _setPhase(job.audioPath, 'Generating summary...');

        final summaryMap = Map<String, double>.from(
          transcriptionProgress.value,
        );
        summaryMap[job.audioPath] = 0.97;
        transcriptionProgress.value = summaryMap;

        _autoGenerateSummary(vault, job.audioPath, text);
      }

      // Push to 100% and clean up
      _setPhase(job.audioPath, 'Complete!');
      final doneMap = Map<String, double>.from(transcriptionProgress.value);
      doneMap[job.audioPath] = 1.0;
      transcriptionProgress.value = doneMap;
      Future.delayed(const Duration(seconds: 2), () {
        final m = Map<String, double>.from(transcriptionProgress.value);
        m.remove(job.audioPath);
        transcriptionProgress.value = m;
        _clearPhase(job.audioPath);
        _clearTokens(job.audioPath);
      });
    }

    // Process the next job immediately
    _processNextJob(vault);
  }

  Future<String> transcribeFile(String audioPath, {String lang = 'en'}) async {
    final ext = audioPath.split('.').last.toLowerCase();
    debugPrint('🎙️ [WHISPER] transcribeFile called');
    debugPrint('   Path: $audioPath');
    debugPrint('   Extension: $ext, Lang: $lang');

    // Verify the file exists before handing to Whisper
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      debugPrint('❌ [WHISPER] Audio file does not exist: $audioPath');
      return "Transcription failed.";
    }
    final fileSize = await audioFile.length();
    debugPrint('   File size: $fileSize bytes');
    if (fileSize < 1000) {
      debugPrint('❌ [WHISPER] Audio file too small ($fileSize bytes)');
      return "Transcription failed.";
    }

    try {
      // 'auto' triggers Whisper's native language detection (pass empty string)
      final whisperLang = (lang == 'auto') ? '' : lang;
      final result = await _controller.transcribe(
        model: _model,
        audioPath: audioPath,
        lang: whisperLang,
        threads: 4, // Use multi-core parallelism for faster inference
        convert: true, // Let whisper_ggml_plus_ffmpeg convert m4a/mp3 to wav
      );

      if (result == null) {
        debugPrint('❌ [WHISPER] Controller returned null for $audioPath');
        return "Transcription failed.";
      }

      final text = result.transcription.text;
      debugPrint(
        '✅ [WHISPER] Transcription success: ${text.length} chars in ${result.time.inMilliseconds}ms',
      );
      return text;
    } catch (e, stack) {
      debugPrint('❌ [WHISPER] Exception during transcription: $e');
      debugPrint('   Stack: $stack');
      return "Transcription failed.";
    }
  }

  /// Returns the full Whisper response including timestamped segments.
  /// Used by the worker to persist per-segment timestamps for speaker
  /// alignment, and by ad-hoc diarization spikes.
  Future<WhisperTranscribeResponse?> transcribeFileWithSegments(
    String audioPath, {
    String lang = 'en',
  }) async {
    try {
      final whisperLang = (lang == 'auto') ? '' : lang;
      final result = await _controller.transcribe(
        model: _model,
        audioPath: audioPath,
        lang: whisperLang,
        threads: 4,
        convert: true,
      );
      return result?.transcription;
    } catch (e, stack) {
      debugPrint('❌ [WHISPER] Exception during transcription: $e');
      debugPrint('   Stack: $stack');
      return null;
    }
  }

  /// Releases the Whisper model from GPU memory.
  /// Call before loading Gemma to prevent OOM crashes on constrained devices.
  Future<void> releaseWhisper() async {
    try {
      await _controller.dispose(model: _model);
      debugPrint('🧹 [WHISPER] Model released from GPU memory');
    } catch (e) {
      debugPrint('⚠️ [WHISPER] Release failed: $e');
    }
  }

  /// Generates topic tags from a transcript using Gemma, then persists them.
  /// Runs fire-and-forget so it doesn't block the transcription queue.
  void _autoTagRecording(
    VaultService vault,
    String audioPath,
    String transcriptText,
  ) async {
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
      await vault.db.delete(
        'recording_tags',
        where: 'recording_id = ?',
        whereArgs: [recordingId],
      );
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

  /// Auto-generates an AI summary after transcription completes.
  /// Uses the same Gemma model + SummaryPrompt as the manual UI flow.
  /// Non-fatal — a failure here doesn't block the recording from being usable.
  void _autoGenerateSummary(
    VaultService vault,
    String audioPath,
    String transcriptText,
  ) async {
    try {
      // Skip if a summary already exists (e.g. from a previous transcription run)
      final existing = await vault.db.query(
        'transcription_jobs',
        columns: ['summary_json'],
        where: 'audio_path = ?',
        whereArgs: [audioPath],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.first['summary_json'] != null) {
        debugPrint(
          '[AutoSummary] Summary already exists for $audioPath, skipping.',
        );
        return;
      }

      // Check if Gemma model is available
      final modelManager = ModelManager();
      final hasModel = await modelManager.hasModel();
      if (!hasModel) {
        debugPrint(
          '[AutoSummary] Gemma model not available, skipping auto-summary.',
        );
        return;
      }

      debugPrint('[AutoSummary] Generating summary for $audioPath...');

      // Read summary style preference
      final prefs = PreferencesService();
      final style = await prefs.getString(
        'summary_style',
        defaultValue: 'concise',
      );

      var prompt = SummaryPrompt.initial(transcriptText, style: style);

      final inference = LocalInferenceService();

      // loadModel now handles closing any stale engine internally
      try {
        await inference.loadModel();
      } catch (e) {
        debugPrint('[AutoSummary] Model load failed: $e');
        return;
      }

      prompt =
          await SummaryContext(
            countTokens: inference.countTokens,
            condense: (section) async {
              final notes = StringBuffer();
              await for (final token in inference.generateStream(
                section,
                maxTokens: 768,
                autoContinue: true,
              )) {
                notes.write(token.text);
              }
              return notes.toString();
            },
          ).prepare(
            transcriptText,
            (text) => SummaryPrompt.initial(text, style: style),
          );

      final completer = Completer<String>();
      String buffer = '';

      final sub =
          draftedSummaryStream(
            inference,
            prompt,
            drafts: SummaryDraftRepository(vault),
            key: 'audio:$audioPath',
          ).listen(
            (token) => buffer += token.text,
            onDone: () {
              if (!completer.isCompleted) completer.complete(buffer);
            },
            onError: (e) {
              if (!completer.isCompleted) completer.completeError(e);
            },
          );

      final rawOutput = await completer.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          sub.cancel();
          throw TimeoutException(
            'Summary generation timed out; incomplete output was not saved.',
          );
        },
      );

      if (rawOutput.trim().isEmpty) {
        debugPrint('[AutoSummary] Empty output, skipping.');
        return;
      }

      // Parse the plain-text sections into JSON (same logic as the UI)
      final jsonResult = _parseSummaryToJson(rawOutput);
      if (jsonResult == null) {
        debugPrint('[AutoSummary] Failed to parse summary output.');
        return;
      }

      // Save to DB
      await vault.db.update(
        'transcription_jobs',
        {'summary_json': jsonResult},
        where: 'audio_path = ?',
        whereArgs: [audioPath],
      );

      await SummaryDraftRepository(vault).clear('audio:$audioPath');
      debugPrint('[AutoSummary] Summary saved for $audioPath.');
    } catch (e) {
      debugPrint('[AutoSummary] Failed to generate summary: $e');
      // Non-fatal — recording still works without auto-summary
    }
  }

  /// Parses Gemma's plain-text summary output into structured JSON.
  /// Mirrors the section-parsing logic in recording_detail_screen.
  String? _parseSummaryToJson(String text) {
    // Strip any preamble before the first actual section header.
    // The model sometimes echoes prompt instructions before starting.
    final firstHeader = RegExp(r'SUMMARY\s*:|TLDR\s*:', caseSensitive: false);
    final headerMatch = firstHeader.firstMatch(text);
    final effective = headerMatch != null
        ? text.substring(headerMatch.start)
        : text;

    // Clean common model artifacts
    final cleaned = effective
        .replaceAll(RegExp(r'<[^>]+>'), '') // strip HTML/XML tags
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1') // strip markdown bold
        .replaceAll(RegExp(r'\\[0-9]+'), ''); // strip \1 \2 etc. artifacts

    // Try JSON first
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      if (parsed.containsKey('tldr') || parsed.containsKey('key_points')) {
        return jsonEncode(parsed);
      }
    } catch (_) {}

    // Parse plain-text sections
    String extractSection(String src, String header, List<String> nextHeaders) {
      final pattern = RegExp(
        header.replaceAll(':', '') + r'\s*:?',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(src);
      if (match == null) return '';

      int start = match.end;
      int end = src.length;
      for (final next in nextHeaders) {
        final nextPattern = RegExp(
          next.replaceAll(':', '') + r'\s*:?',
          caseSensitive: false,
        );
        final nextMatch = nextPattern.firstMatch(src.substring(start));
        if (nextMatch != null) {
          end = start + nextMatch.start;
          break;
        }
      }
      return src.substring(start, end).trim();
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
          .toList();
    }

    const headers = [
      'TLDR:',
      'KEY POINTS:',
      'DECISIONS:',
      'ACTION ITEMS:',
      'OPEN QUESTIONS:',
    ];

    final tldr = extractSection(cleaned, 'TLDR:', headers.sublist(1));
    final keyPoints = extractSection(
      cleaned,
      'KEY POINTS:',
      headers.sublist(2),
    );
    final decisions = extractSection(cleaned, 'DECISIONS:', headers.sublist(3));
    final actionItems = extractSection(
      cleaned,
      'ACTION ITEMS:',
      headers.sublist(4),
    );
    final openQuestions = extractSection(cleaned, 'OPEN QUESTIONS:', []);

    if (tldr.isEmpty && keyPoints.isEmpty) return null;

    final result = {
      'tldr': tldr.replaceAll('\n', ' ').trim(),
      'key_points': splitLines(keyPoints),
      'decisions': splitLines(decisions),
      'action_items': splitLines(actionItems),
      'open_questions': splitLines(openQuestions),
    };
    return jsonEncode(result);
  }

  /// Uses Gemma to generate topic tags from transcript text.
  Future<List<String>> _generateTagsWithGemma(String transcriptText) async {
    try {
      // Phase 1: Send full transcript — no truncation.
      final String snippet = transcriptText;

      final prompt =
          '''Analyze this meeting transcript and return ONLY a comma-separated list of 3-5 topic tags. 
Tags should be short (1-2 words each), lowercase, and describe the key topics discussed.
Examples of good tags: budget, hiring, product launch, q3 planning, customer feedback

Transcript:
$snippet

Tags:''';

      final inference = LocalInferenceService();
      await inference.loadModel();

      final completer = Completer<String>();
      String buffer = '';

      final sub = inference
          .generateStream(prompt, maxTokens: 64)
          .listen(
            (token) => buffer += token.text,
            onDone: () {
              if (!completer.isCompleted) completer.complete(buffer);
            },
            onError: (e) {
              if (!completer.isCompleted) completer.completeError(e);
            },
          );

      final rawOutput = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          sub.cancel();
          throw TimeoutException(
            'Summary generation timed out; incomplete output was not saved.',
          );
        },
      );

      // Parse comma-separated tags
      return rawOutput
          .replaceAll('\n', ',')
          .split(',')
          .map(
            (t) => t.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ''),
          )
          .where((t) => t.isNotEmpty && t.length <= 30 && t.length >= 2)
          .take(5)
          .toList();
    } catch (e) {
      debugPrint(
        '[AutoTag] Gemma tagging failed, falling back to keywords: $e',
      );
      return _extractKeywords(transcriptText);
    }
  }

  /// Lightweight keyword extraction fallback when Gemma is unavailable.
  List<String> _extractKeywords(String text) {
    const stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'by',
      'from',
      'is',
      'are',
      'was',
      'were',
      'be',
      'been',
      'have',
      'has',
      'had',
      'do',
      'does',
      'did',
      'will',
      'would',
      'could',
      'should',
      'may',
      'might',
      'can',
      'shall',
      'it',
      'its',
      'this',
      'that',
      'these',
      'those',
      'i',
      'you',
      'he',
      'she',
      'we',
      'they',
      'me',
      'him',
      'her',
      'us',
      'them',
      'my',
      'your',
      'his',
      'our',
      'their',
      'what',
      'which',
      'who',
      'whom',
      'when',
      'where',
      'why',
      'how',
      'not',
      'no',
      'so',
      'if',
      'then',
      'than',
      'too',
      'very',
      'just',
      'about',
      'also',
      'up',
      'out',
      'all',
      'some',
      'any',
      'each',
      'every',
      'both',
      'few',
      'more',
      'most',
      'other',
      'into',
      'over',
      'such',
      'only',
      'own',
      'same',
      'like',
      'get',
      'got',
      'go',
      'going',
      'know',
      'think',
      'thing',
      'things',
      'want',
      'need',
      'make',
      'made',
      'say',
      'said',
      'well',
      'yeah',
      'okay',
      'right',
      'really',
      'actually',
      'gonna',
      'um',
      'uh',
    };

    final words = text
        .toLowerCase()
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
