import 'package:flutter/services.dart';

/// Platform bridge; download orchestration and network clients live in app/.
class NativeModelDownload {
  static const _channel = MethodChannel('kraken.kernel/wakelock');

  void setEventHandler(Future<void> Function(String, dynamic) handler) {
    _channel.setMethodCallHandler(
      (call) => handler(call.method, call.arguments),
    );
  }

  Future<void> start({required String url, required String outputPath}) =>
      _channel.invokeMethod<void>('startNativeDownload', {
        'url': url,
        'outputPath': outputPath,
      });

  Future<void> stop() => _channel.invokeMethod<void>('release');
}
