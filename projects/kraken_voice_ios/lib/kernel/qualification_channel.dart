import 'package:flutter/services.dart';

class QualificationChannel {
  Future<Map<String, dynamic>> launchOptions() async =>
      await _channel.invokeMapMethod<String, dynamic>('launchOptions') ?? {};
  Future<void> keepAwake(bool enabled) =>
      _channel.invokeMethod<void>('keepAwake', {'enabled': enabled});
  static const _channel = MethodChannel('kraken.kernel/qualification');
  Future<Map<String, dynamic>> snapshot() async =>
      await _channel.invokeMapMethod<String, dynamic>('snapshot') ?? {};
  Future<void> select(String backend) =>
      _channel.invokeMethod<void>('select', {'backend': backend});
}
