import 'dart:io';
import 'package:flutter/foundation.dart';

/// Paired with Android ReleaseHardware/HexagonBridge. Other profiles require
/// device validation before they can be selected; there is no CPU fallback.
abstract final class ModelProfile {
  static const build = '0.1.0+1';
  static String? _backend;
  static String? _profile;
  static bool get gpu {
    if (Platform.isIOS) return false;
    if (_backend == null) {
      throw StateError('Device AI profile has not been initialized');
    }
    return _backend == 'GPU';
  }

  /// Native selection is checked against known profiles before model paths or
  /// download URLs become available. Never accept arbitrary URLs from a channel.
  static bool configure(Map<String, dynamic>? native) {
    if (native?['supported'] != true ||
        native?['build'] != build ||
        native?['contextWindow'] != contextWindow) {
      return false;
    }
    final backend = native?['backend'];
    final profile = native?['profile'];
    final validGpu =
        backend == 'GPU' &&
        profile == 'gemma4-litert171-opencl-adreno750' &&
        native?['modelFilename'] == 'gemma4-e2b-portable-gpu.litertlm';
    final validNpu =
        backend == 'NPU' &&
        (profile == 'gemma4-hexagon-v79' || profile == 'gemma4-hexagon-v81') &&
        native?['modelFilename'] == npuFilename;
    if (!validGpu && !validNpu) return false;
    if (_backend != null && (_backend != backend || _profile != profile)) {
      return false;
    }
    _backend = backend as String;
    _profile = profile as String;
    return true;
  }

  @visibleForTesting
  static void resetForTest() => clearAfterUnload();

  /// Internal qualification runner only: call after native unload completes.
  static void clearAfterUnload() {
    _backend = null;
    _profile = null;
  }

  static String get label => Platform.isIOS
      ? 'Gemma 4 · Apple GPU'
      : gpu
      ? 'Gemma 4 · Adreno GPU · S24'
      : 'Gemma 4 · Hexagon NPU';
  static const npuFilename = 'gemma4-e2b-w4.gguf';
  static String get filename => Platform.isIOS
      ? 'mlx-community/gemma-4-e2b-it-4bit'
      : gpu
      ? 'gemma4-e2b-portable-gpu.litertlm'
      : npuFilename;
  static int get bytes => gpu ? 2588147712 : 2620370976;
  static const contextWindow = 4096;
  static const maxOutputTokens = 2048;
  static String get url => Platform.isIOS
      ? throw UnsupportedError(
          'AI summaries are not available in this iOS preview.',
        )
      : gpu
      ? 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm'
      : 'https://huggingface.co/h2loop-ai/gemma-4-e2b-hexagon/'
            'resolve/1bb2044c313769541558f2c27fa67561894d0f26/gemma4-e2b-w4.gguf';
}
