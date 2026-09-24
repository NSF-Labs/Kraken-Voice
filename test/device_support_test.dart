import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/device_support.dart';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kraken.kernel/inference');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(ModelProfile.resetForTest);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    ModelProfile.resetForTest();
  });

  test('accepts an explicitly supported device', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'supported': true,
        'backend': 'NPU',
        'profile': 'gemma4-hexagon-v81',
        'modelFilename': ModelProfile.npuFilename,
        'build': ModelProfile.build,
        'contextWindow': 4096,
      },
    );
    expect(await DeviceSupport.isSupported(), true);
  });
  test('rejects unsupported and unknown devices', () async {
    for (final response in [
      {'supported': false},
      <String, dynamic>{},
      null,
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      expect(await DeviceSupport.isSupported(), false);
    }
  });
  test('fails closed if the platform check fails', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect(await DeviceSupport.isSupported(), false);
  });
}
