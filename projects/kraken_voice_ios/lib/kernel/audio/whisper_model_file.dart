import 'dart:io';
import 'package:flutter/services.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// The multilingual base model used by the iOS transcription engine.
abstract final class WhisperModelFile {
  static const bytes = 147951465;
  static const sha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  static const url =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
      '5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin';

  static Future<String> path() =>
      WhisperController().getPath(WhisperModel.base);

  /// Installs the checksum-verified bundled model on first launch, offline.
  static Future<void> installBundled() async {
    if (!Platform.isIOS || await isReady()) return;
    await const MethodChannel('kraken.kernel/models').invokeMethod<void>(
      'installBundledWhisper', {'path': await path()},
    );
  }

  static Future<bool> isReady() async {
    final file = File(await path());
    return await file.exists() && await file.length() == bytes;
  }
}
