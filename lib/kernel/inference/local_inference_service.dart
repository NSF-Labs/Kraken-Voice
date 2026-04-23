import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ModelCapabilities {
  final int contextWindow;
  final bool supportsStreaming;
  final List<String> supportedModalities;

  const ModelCapabilities({
    required this.contextWindow,
    required this.supportsStreaming,
    required this.supportedModalities,
  });
}

class InferenceToken {
  final String text;
  final bool isDone;
  const InferenceToken(this.text, {this.isDone = false});
}

class LocalInferenceService {
  final MethodChannel _channel = const MethodChannel('kraken.kernel/inference');

  // Real Gemma 4 E2B capabilities
  final ModelCapabilities capabilities = const ModelCapabilities(
    contextWindow: 8192,
    supportsStreaming: true,
    supportedModalities: ['text'],
  );

  /// Resolves the model path from the app's documents directory,
  /// matching where ModelManager downloads the file.
  Future<String> _resolveModelPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/gemma4.litertlm';
  }

  /// Loads the model into memory.
  Future<void> loadModel({String? modelPath}) async {
    final path = modelPath ?? await _resolveModelPath();
    try {
      await _channel.invokeMethod('loadModel', {'modelPath': path});
    } on PlatformException catch (e) {
      throw Exception('Failed to load model: ${e.message}');
    }
  }

  /// Unloads the model to free up RAM.
  Future<void> unloadModel() async {
    try {
      await _channel.invokeMethod('unloadModel');
    } on PlatformException catch (e) {
      throw Exception('Failed to unload model: ${e.message}');
    }
  }

  /// Generates text from a prompt, streaming tokens back.
  Stream<InferenceToken> generateStream(String prompt, {int maxTokens = 1024}) {
    final eventChannel = const EventChannel('kraken.kernel/inference/stream');
    final controller = StreamController<InferenceToken>();

    final subscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final map = event as Map;
        final isDone = map['isDone'] as bool;
        if (isDone) {
          controller.close();
        } else {
          final text = map['text'] as String;
          controller.add(InferenceToken(text, isDone: isDone));
        }
      },
      onError: (error) {
        controller.addError(Exception(error.toString()));
        controller.close();
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    controller.onCancel = () {
      subscription.cancel();
    };

    // Invoke method AFTER listener is attached
    _channel
        .invokeMethod('generate', {'prompt': prompt, 'maxTokens': maxTokens})
        .catchError((error) {
          controller.addError(Exception('Failed to start generation: $error'));
          controller.close();
        });

    return controller.stream;
  }
}
