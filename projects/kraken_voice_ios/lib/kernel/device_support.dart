import 'dart:io';
import 'package:flutter/services.dart';
import 'inference/model_profile.dart';

class DeviceSupport {
  static const _channel = MethodChannel('kraken.kernel/inference');

  static Future<bool> isSupported() async {
    if (Platform.isIOS)
      return true; // Recording preview; AI support is separate.
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
