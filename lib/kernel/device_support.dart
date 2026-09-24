import 'package:flutter/services.dart';
import 'inference/model_profile.dart';

class DeviceSupport {
  static const _channel = MethodChannel('kraken.kernel/inference');

  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'deviceSupport',
      );
      return ModelProfile.configure(result);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
