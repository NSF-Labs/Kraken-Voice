import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/app/feature_flags.dart';
import 'package:krak_en_voice/inference/model_manager.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/kernel/model_storage_helper.dart';

/// Centralized reactive model readiness service.
///
/// All screens should observe these ValueNotifiers instead of performing
/// ad-hoc `hasModel()` checks. Call [refresh] on startup and after any
/// download/delete operation to keep the state current.
class ModelReadinessService {
  // Singleton
  static final ModelReadinessService _instance = ModelReadinessService._internal();
  factory ModelReadinessService() => _instance;
  ModelReadinessService._internal();

  /// Whether the Whisper speech-to-text model is available.
  final ValueNotifier<bool> whisperReady = ValueNotifier(false);

  /// Whether the Gemma AI model (tagging/summaries) is available.
  final ValueNotifier<bool> gemmaReady = ValueNotifier(false);

  /// Whether speaker diarization models are available.
  final ValueNotifier<bool> diarizationReady = ValueNotifier(false);

  /// True when all models are downloaded and the app is fully operational.
  /// When [kDiarizationEnabled] is false, diarization is excluded from this
  /// check so missing diarization models don't block the user.
  bool get allReady =>
      whisperReady.value &&
      gemmaReady.value &&
      (kDiarizationEnabled ? diarizationReady.value : true);

  /// True when the minimum viable set (Whisper) is available for basic
  /// recording + transcription.
  bool get canTranscribe => whisperReady.value;

  /// Refreshes all model readiness checks. Call on startup (vault unlock),
  /// after a download completes, or after a model deletion.
  Future<void> refresh() async {
    await Future.wait([
      _checkWhisper(),
      _checkGemma(),
      _checkDiarization(),
    ]);
    debugPrint('[ModelReadiness] whisper=${whisperReady.value} '
        'gemma=${gemmaReady.value} diarization=${diarizationReady.value}');
  }

  Future<void> _checkWhisper() async {
    try {
      final engine = TranscriptionEngine();
      final modelPath = await engine.controller.getPath(engine.model);
      whisperReady.value = await File(modelPath).exists();
    } catch (_) {
      whisperReady.value = false;
    }
  }

  Future<void> _checkGemma() async {
    try {
      gemmaReady.value = await ModelManager().hasModel();
    } catch (_) {
      gemmaReady.value = false;
    }
  }

  Future<void> _checkDiarization() async {
    try {
      final baseDir = await ModelStorageHelper().getModelsDirectory();
      final modelsDir = '$baseDir/diarization_models';
      final segPath = '$modelsDir/sherpa-onnx-pyannote-segmentation-3-0/model.onnx';
      final embPath = '$modelsDir/nemo_en_titanet_small.onnx';
      diarizationReady.value =
          await File(segPath).exists() && await File(embPath).exists();
    } catch (_) {
      diarizationReady.value = false;
    }
  }
}
