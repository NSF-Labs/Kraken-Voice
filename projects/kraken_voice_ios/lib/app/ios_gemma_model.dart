import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../kernel/model_readiness_service.dart';

class IOSGemmaModel extends ChangeNotifier {
  static final instance = IOSGemmaModel();
  static const _channel = MethodChannel('kraken.kernel/inference');
  bool checking = true;
  bool supported = false;
  bool ready = false;
  bool downloading = false;
  double progress = 0;
  String? error;
  String reason = '';
  Timer? _timer;
  bool _refreshing = false;

  Future<void> check() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('modelStatus');
      supported = status?['supported'] == true;
      ready = status?['ready'] == true;
      downloading = status?['downloading'] == true;
      progress = (status?['progress'] as num?)?.toDouble() ?? 0;
      reason = status?['reason'] as String? ?? '';
      error = status?['error'] as String?;
      ModelReadinessService().gemmaReady.value = ready && supported;
      if (!downloading) { _timer?.cancel(); _timer = null; }
    } catch (e) { error = 'Could not check Gemma: $e'; }
    checking = false;
    _refreshing = false;
    notifyListeners();
  }

  Future<void> download() async {
    if (downloading) return;
    try {
      await _channel.invokeMethod<void>('downloadModel');
      await check();
      if (downloading) {
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => check());
      }
    } catch (e) { error = 'Gemma setup failed: $e'; notifyListeners(); }
  }

  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancelDownload');
    await check();
  }
}
