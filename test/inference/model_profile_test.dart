import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kraken.kernel/inference');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('matching app and native profile loads the requested model', () async {
    String? loaded;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'deviceSupport') {
        return {
          'modelFilename': ModelProfile.filename,
          'build': ModelProfile.build,
        };
      }
      if (call.method == 'loadModel') {
        loaded = (call.arguments as Map)['modelPath'] as String;
      }
      return null;
    });
    await LocalInferenceService().loadModel(
      modelPath: '/models/${ModelProfile.filename}',
    );
    expect(loaded, '/models/${ModelProfile.filename}');
  });

  test('stale native profile is rejected before loading any model', () async {
    for (final native in [
      {'modelFilename': 'gemma4.litertlm', 'build': ModelProfile.build},
      {'modelFilename': ModelProfile.filename, 'build': 'old-build'},
      <String, String>{},
    ]) {
      var loadCalled = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'deviceSupport') return native;
        if (call.method == 'loadModel') loadCalled = true;
        return null;
      });
      await expectLater(
        LocalInferenceService().loadModel(modelPath: '/models/test'),
        throwsStateError,
      );
      expect(loadCalled, false);
    }
  });
}
