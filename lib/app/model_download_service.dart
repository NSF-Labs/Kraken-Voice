import 'dart:async';
import 'dart:io';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/kernel/native_model_download.dart';
import 'package:krak_en_voice/inference/model_manager.dart';
import 'package:krak_en_voice/kernel/model_storage_helper.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/kernel/model_readiness_service.dart';
import 'package:krak_en_voice/app/feature_flags.dart';

// ── Sherpa-onnx model URLs ──────────────────────────────────────────────────
const _segModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';

const _embModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'speaker-recongition-models/'
    'nemo_en_titanet_small.onnx';

String get _gemmaUrl => ModelProfile.url;

/// Overall download pipeline state.
enum DownloadPipelineState { idle, checking, downloading, completed, error }

/// Per-step status.
enum StepStatus { pending, downloading, done, error }

/// Describes a single model in the download pipeline.
class DownloadStep {
  final String label;
  final String sizeHint;
  StepStatus status;
  double progress;
  String progressText;

  DownloadStep({
    required this.label,
    required this.sizeHint,
    this.status = StepStatus.pending,
    this.progress = 0.0,
    this.progressText = '',
  });

  DownloadStep copyWith({
    StepStatus? status,
    double? progress,
    String? progressText,
  }) {
    return DownloadStep(
      label: label,
      sizeHint: sizeHint,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      progressText: progressText ?? this.progressText,
    );
  }
}

/// Singleton service that manages model downloads independently of UI lifecycle.
///
/// Downloads persist in the background even when the user navigates away.
/// Any screen can observe [state], [steps], [error], and [overallProgress]
/// to display download status.
///
/// **Background resilience:** The Gemma model (2.5 GB) is downloaded entirely
/// on the native Android side via a foreground service, so it continues even
/// when Flutter's Dart engine is paused. Smaller models (Whisper, Sherpa)
/// are downloaded via Dart/Dio since they complete quickly.
class ModelDownloadService {
  // Singleton
  static final ModelDownloadService _instance =
      ModelDownloadService._internal();
  factory ModelDownloadService() => _instance;
  ModelDownloadService._internal() {
    _setupNativeCallbacks();
  }

  final ModelManager _modelManager = ModelManager();

  /// Platform channel for download service management.
  final _downloadChannel = NativeModelDownload();

  /// Current pipeline state.
  final ValueNotifier<DownloadPipelineState> state = ValueNotifier(
    DownloadPipelineState.idle,
  );

  /// The list of download steps. Updated in-place and re-notified.
  final ValueNotifier<List<DownloadStep>> steps = ValueNotifier([]);

  /// Error message if the pipeline failed.
  final ValueNotifier<String?> error = ValueNotifier(null);

  /// Overall progress (0.0 – 1.0) across all steps.
  final ValueNotifier<double> overallProgress = ValueNotifier(0.0);

  /// Index of the currently active step (for error reporting).
  int _currentStep = 0;

  /// Active Dio cancel token — for non-Gemma downloads.
  CancelToken? _cancelToken;

  /// Completer that resolves when the native Gemma download finishes.
  Completer<void>? _nativeDownloadCompleter;

  /// Whether a download is actively in flight.
  bool get isDownloading => state.value == DownloadPipelineState.downloading;

  // ── Native callback handler ──────────────────────────────────────────────
  // Listens for progress/completion/error from the native download service.

  void _setupNativeCallbacks() {
    _downloadChannel.setEventHandler((method, arguments) async {
      switch (method) {
        case 'onDownloadProgress':
          final args = arguments as Map?;
          if (args != null) {
            final progress = (args['progress'] as num?)?.toDouble() ?? 0.0;
            final sizeStr = args['sizeStr'] as String? ?? '';
            _updateStep(0, progress: progress, progressText: sizeStr);
          }
          break;

        case 'onDownloadComplete':
          debugPrint('[ModelDownloadService] Native Gemma download complete.');
          _updateStep(0, status: StepStatus.done, progress: 1.0);
          if (_nativeDownloadCompleter != null &&
              !_nativeDownloadCompleter!.isCompleted) {
            _nativeDownloadCompleter!.complete();
          }
          break;

        case 'onDownloadError':
          final args = arguments as Map?;
          final errorMsg =
              args?['error'] as String? ?? 'Unknown native download error';
          debugPrint(
            '[ModelDownloadService] Native Gemma download failed: $errorMsg',
          );
          if (_nativeDownloadCompleter != null &&
              !_nativeDownloadCompleter!.isCompleted) {
            _nativeDownloadCompleter!.completeError(Exception(errorMsg));
          }
          break;
      }
    });
  }

  // ── Foreground service helpers ────────────────────────────────────────────

  Future<void> _stopForegroundDownload() async {
    try {
      await _downloadChannel.stop();
      debugPrint('[ModelDownloadService] Foreground download service stopped.');
    } catch (e) {
      debugPrint(
        '[ModelDownloadService] Could not stop foreground service: $e',
      );
    }
  }

  /// Starts the Gemma download natively — runs entirely on the Android side,
  /// independent of Flutter's Dart engine lifecycle.
  Future<void> _startNativeGemmaDownload() async {
    final modelPath = await _modelManager.getModelPath();
    _nativeDownloadCompleter = Completer<void>();

    await _downloadChannel.start(url: _gemmaUrl, outputPath: modelPath);

    // Wait for the native side to call back with complete/error
    return _nativeDownloadCompleter!.future;
  }

  // ── Sherpa-onnx model paths ───────────────────────────────────────────────

  Future<String> get _diarizationModelsDir async {
    final baseDir = await ModelStorageHelper().getModelsDirectory();
    return '$baseDir/diarization_models';
  }

  Future<String> get _segModelPath async {
    final dir = await _diarizationModelsDir;
    return '$dir/sherpa-onnx-pyannote-segmentation-3-0/model.onnx';
  }

  Future<String> get _embModelPath async {
    final dir = await _diarizationModelsDir;
    return '$dir/nemo_en_titanet_small.onnx';
  }

  // ── Check which models are already downloaded ─────────────────────────────

  /// Checks model availability and populates [steps].
  /// Returns true if all models are already present.
  Future<bool> checkModels() async {
    state.value = DownloadPipelineState.checking;
    error.value = null;

    try {
      final stepList = <DownloadStep>[
        DownloadStep(
          label: 'Gemma 4 AI Engine',
          sizeHint:
              '${(ModelProfile.bytes / 1000000000).toStringAsFixed(1)} GB',
        ),
        DownloadStep(label: 'Whisper Transcription', sizeHint: '~40 MB'),
        if (kDiarizationEnabled)
          DownloadStep(label: 'Speaker Diarization', sizeHint: '~44 MB'),
      ];

      final hasGemma = await _modelManager.hasModel();
      bool hasWhisper = false;
      try {
        final engine = TranscriptionEngine();
        final modelPath = await engine.controller.getPath(engine.model);
        hasWhisper = await File(modelPath).exists();
      } catch (_) {}

      final hasSeg = await File(await _segModelPath).exists();
      final hasEmb = await File(await _embModelPath).exists();
      final hasSherpa = hasSeg && hasEmb;

      if (hasGemma) stepList[0].status = StepStatus.done;
      if (hasWhisper) stepList[1].status = StepStatus.done;
      if (kDiarizationEnabled && stepList.length > 2) {
        if (hasSherpa) stepList[2].status = StepStatus.done;
      }

      steps.value = stepList;
      _recalcProgress();

      final allDone =
          hasGemma && hasWhisper && (kDiarizationEnabled ? hasSherpa : true);

      state.value = allDone
          ? DownloadPipelineState.completed
          : DownloadPipelineState.idle;
      return allDone;
    } catch (e) {
      error.value = e.toString();
      state.value = DownloadPipelineState.error;
      return false;
    }
  }

  // ── Download pipeline ─────────────────────────────────────────────────────

  /// Starts the full download pipeline. Safe to call even if already running
  /// (will no-op).
  Future<void> startDownload() async {
    if (isDownloading) return;

    state.value = DownloadPipelineState.downloading;
    error.value = null;
    _cancelToken = CancelToken();

    try {
      // Request shared storage permission so models land in a cross-app
      // accessible location from the start.
      await ModelStorageHelper().requestSharedStoragePermission();

      final stepList = steps.value;

      // Step 0: Gemma — downloaded NATIVELY on Android foreground service.
      // This continues even when the user switches to another app.
      if (stepList[0].status != StepStatus.done) {
        _currentStep = 0;
        _updateStep(0, status: StepStatus.downloading);
        await _startNativeGemmaDownload();
        // Native callback will have already set status to done
      }

      // Step 1: Whisper (small, ~40 MB — fast enough to stay in Dart)
      if (stepList[1].status != StepStatus.done) {
        _currentStep = 1;
        _updateStep(
          1,
          status: StepStatus.downloading,
          progressText: 'Downloading Whisper model...',
        );
        final engine = TranscriptionEngine();
        await engine.downloadModel();
        _updateStep(1, status: StepStatus.done, progress: 1.0);
      }

      // Step 2: Sherpa-onnx (segmentation + embedding) — only if enabled
      if (kDiarizationEnabled &&
          stepList.length > 2 &&
          stepList[2].status != StepStatus.done) {
        _currentStep = 2;
        _updateStep(
          2,
          status: StepStatus.downloading,
          progressText: 'Downloading segmentation model...',
        );

        final modelsDir = await _diarizationModelsDir;
        await Directory(modelsDir).create(recursive: true);

        // Download segmentation model (tar.bz2 → extract)
        final segPath = await _segModelPath;
        if (!await File(segPath).exists()) {
          final tarPath = '$modelsDir/seg.tar.bz2';
          await _downloadWithProgress(
            url: _segModelUrl,
            outputPath: tarPath,
            stepIndex: 2,
            label: 'Segmentation model',
          );

          _updateStep(2, progressText: 'Extracting segmentation model...');
          final r = await Process.run('tar', ['xjf', tarPath, '-C', modelsDir]);
          if (r.exitCode != 0) {
            throw Exception(
              'Failed to extract segmentation model: ${r.stderr}',
            );
          }
          try {
            await File(tarPath).delete();
          } catch (_) {}
        }

        // Download embedding model
        final embPath = await _embModelPath;
        if (!await File(embPath).exists()) {
          _updateStep(2, progressText: 'Downloading embedding model...');
          await _downloadWithProgress(
            url: _embModelUrl,
            outputPath: embPath,
            stepIndex: 2,
            label: 'Embedding model',
          );
        }

        _updateStep(2, status: StepStatus.done, progress: 1.0);
      }

      state.value = DownloadPipelineState.completed;
      // Notify all screens that model availability has changed
      ModelReadinessService().refresh();
    } catch (e) {
      if (_cancelToken?.isCancelled == true) {
        debugPrint('[ModelDownloadService] Download cancelled by user.');
        state.value = DownloadPipelineState.idle;
        return;
      }
      debugPrint('[ModelDownloadService] Download failed: $e');
      _updateStep(_currentStep, status: StepStatus.error);
      error.value = e.toString();
      state.value = DownloadPipelineState.error;
    } finally {
      _cancelToken = null;
      await _stopForegroundDownload();
    }
  }

  /// Cancels any in-progress download.
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled download');
  }

  Future<void> _downloadWithProgress({
    required String url,
    required String outputPath,
    required int stepIndex,
    required String label,
  }) async {
    final dio = Dio();
    try {
      await dio.download(
        url,
        outputPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            final sizeStr =
                '$label: ${(received / 1024 / 1024).toStringAsFixed(1)} / '
                '${(total / 1024 / 1024).toStringAsFixed(1)} MB';
            _updateStep(stepIndex, progress: progress, progressText: sizeStr);
          }
        },
      );
    } catch (e) {
      final file = File(outputPath);
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  // ── Step helpers ──────────────────────────────────────────────────────────

  void _updateStep(
    int index, {
    StepStatus? status,
    double? progress,
    String? progressText,
  }) {
    final current = steps.value;
    if (index >= current.length) return;

    final step = current[index];
    if (status != null) step.status = status;
    if (progress != null) step.progress = progress;
    if (progressText != null) step.progressText = progressText;

    // Re-notify listeners by assigning a new list reference
    steps.value = List.from(current);
    _recalcProgress();
  }

  void _recalcProgress() {
    final stepList = steps.value;
    if (stepList.isEmpty) {
      overallProgress.value = 0.0;
      return;
    }
    double total = 0;
    for (final step in stepList) {
      if (step.status == StepStatus.done) {
        total += 1.0;
      } else if (step.status == StepStatus.downloading) {
        total += step.progress;
      }
    }
    overallProgress.value = total / stepList.length;
  }
}
