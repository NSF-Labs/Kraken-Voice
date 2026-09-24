import 'dart:async';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:krak_en_voice/kernel/model_storage_helper.dart';

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
  static final LocalInferenceService _instance =
      LocalInferenceService._internal();
  factory LocalInferenceService() => _instance;
  LocalInferenceService._internal();

  final MethodChannel _channel = const MethodChannel('kraken.kernel/inference');

  // Real Gemma 4 E2B capabilities
  final ModelCapabilities capabilities = const ModelCapabilities(
    contextWindow: ModelProfile.contextWindow,
    supportsStreaming: true,
    supportedModalities: ['text'],
  );

  /// Resolves the model path from the persistent models directory,
  /// matching where ModelManager downloads the file.
  Future<String> _resolveModelPath() async {
    final modelsDir = await ModelStorageHelper().getModelsDirectory();
    return '$modelsDir/${ModelProfile.filename}';
  }

  /// Reactive signal: true whenever Gemma is actively generating.
  /// UI can listen to show busy indicators (e.g. nav bar glow).
  final ValueNotifier<bool> isBusy = ValueNotifier(false);

  /// Number of inference tasks currently waiting in the queue.
  /// UI can display "2 tasks queued" or similar feedback.
  final ValueNotifier<int> queueSize = ValueNotifier(0);

  // ── Inference queue ─────────────────────────────────────────────────────
  //
  // The native Gemma pipeline can only run one inference at a time.
  // All callers go through generateStream(), which serializes access
  // via this FIFO queue. Each queued item waits for the previous one
  // to complete before starting.

  final Queue<Completer<void>> _queue = Queue();
  bool _isRunning = false;

  /// Acquires exclusive access to the inference pipeline.
  /// Returns a function that the caller MUST invoke when done.
  Future<void Function()> _acquireSlot() async {
    final myTurn = Completer<void>();

    if (_isRunning) {
      // Someone else is running — enqueue and wait
      _queue.add(myTurn);
      queueSize.value = _queue.length;
      debugPrint('[InferenceQueue] Queued task (${_queue.length} waiting)');
      await myTurn.future;
    }

    _isRunning = true;
    queueSize.value = _queue.length;

    return () {
      // Release the slot and wake the next waiter
      _isRunning = _queue.isNotEmpty;
      if (_queue.isNotEmpty) {
        final next = _queue.removeFirst();
        queueSize.value = _queue.length;
        next.complete();
      } else {
        queueSize.value = 0;
      }
    };
  }

  /// Loads the model into memory.
  Future<void> loadModel({String? modelPath}) async {
    try {
      final profile = await _channel.invokeMapMethod<String, dynamic>(
        'deviceSupport',
      );
      if (!ModelProfile.configure(profile)) {
        throw StateError(
          'The app and AI backend versions do not match. Reinstall the current build without clearing app data.',
        );
      }
      final path = modelPath ?? await _resolveModelPath();
      debugPrint(
        '[Inference] Loading ${ModelProfile.filename} (${ModelProfile.build})',
      );
      await _channel.invokeMethod('loadModel', {'modelPath': path});
    } on PlatformException catch (e) {
      throw Exception('Failed to load model: ${e.message}');
    }
  }

  /// The pinned Hexagon backend is ready after load; no synthetic warm-up
  /// requests are needed (and they must not consume the output budget).
  Future<void> warmUp() async {}

  Future<int> countTokens(String prompt) async =>
      (await _channel.invokeMethod<int>('countTokens', {'prompt': prompt}))!;

  /// Kept for callers shared with the former backend; Hexagon needs no warm-up.
  void resetWarmUp() {}

  /// Unloads the model to free up RAM.
  Future<void> unloadModel() async {
    try {
      await _channel.invokeMethod('unloadModel');
    } on PlatformException catch (e) {
      throw Exception('Failed to unload model: ${e.message}');
    }
  }

  /// Generates text from a prompt, streaming tokens back.
  ///
  /// This method is **queued**: if another generation is already in
  /// progress, this call waits until the previous one finishes.
  /// Callers can observe [queueSize] to show waiting feedback.
  Stream<InferenceToken> generateStream(
    String prompt, {
    int maxTokens = 1024,
    bool autoContinue = false,
  }) {
    final controller = StreamController<InferenceToken>();
    StreamSubscription<InferenceToken>? inner;
    final finished = Completer<void>();
    var cancelled = false;
    controller.onCancel = () async {
      cancelled = true;
      await inner?.cancel();
      if (!finished.isCompleted) finished.complete();
    };
    controller.onListen = () async {
      final releaseSlot = await _acquireSlot();
      try {
        if (cancelled) return;
        inner =
            _rawGenerateStream(
              prompt,
              maxTokens: maxTokens.clamp(1, ModelProfile.maxOutputTokens),
              autoContinue: autoContinue,
            ).listen(
              controller.add,
              onError: (Object error, StackTrace stack) {
                if (!cancelled) controller.addError(error, stack);
              },
              onDone: () {
                if (!finished.isCompleted) finished.complete();
              },
            );
        await finished.future;
      } catch (e, stack) {
        if (!cancelled) controller.addError(e, stack);
      } finally {
        await inner?.cancel();
        releaseSlot();
        if (!controller.isClosed) unawaited(controller.close());
      }
    };
    return controller.stream;
  }

  /// Raw (unqueued) native inference stream.
  ///
  /// Only used internally by [generateStream] (which handles queuing)
  /// and by [warmUp] (which runs inside an already-acquired slot).
  Stream<InferenceToken> _rawGenerateStream(
    String prompt, {
    int maxTokens = 1024,
    bool autoContinue = false,
  }) {
    final eventChannel = const EventChannel('kraken.kernel/inference/stream');
    final controller = StreamController<InferenceToken>();

    isBusy.value = true;

    final subscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final map = event as Map;
        final isDone = map['isDone'] as bool;
        if (isDone) {
          isBusy.value = false;
          controller.close();
        } else {
          final text = map['text'] as String;
          controller.add(InferenceToken(text, isDone: isDone));
        }
      },
      onError: (error) {
        isBusy.value = false;
        controller.addError(Exception(error.toString()));
        controller.close();
      },
      onDone: () {
        isBusy.value = false;
        if (!controller.isClosed) controller.close();
      },
    );

    controller.onCancel = () async {
      await subscription.cancel();
      await _channel.invokeMethod('cancelGeneration');
      isBusy.value = false;
    };

    // Invoke method AFTER listener is attached
    _channel
        .invokeMethod('generate', {
          'prompt': prompt,
          'maxTokens': maxTokens,
          'autoContinue': autoContinue,
        })
        .catchError((error) {
          isBusy.value = false;
          if (!controller.isClosed) {
            controller.addError(
              Exception('Failed to start generation: $error'),
            );
            controller.close();
          }
        });

    return controller.stream;
  }
}
