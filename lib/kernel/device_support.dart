import 'package:flutter/services.dart';

class DeviceSupport {
  static const _channel = MethodChannel('kraken.kernel/inference');

  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('deviceSupport');
      return result?['supported'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
