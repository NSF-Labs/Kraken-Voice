import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kraken.kernel/inference');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const nativeNpu = {
    'supported': true,
    'backend': 'NPU',
    'profile': 'gemma4-hexagon-v81',
    'modelFilename': ModelProfile.npuFilename,
    'build': ModelProfile.build,
    'contextWindow': 4096,
  };
  setUp(() {
    ModelProfile.resetForTest();
    ModelProfile.configure(nativeNpu);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    ModelProfile.resetForTest();
  });

  test('selects matching model and refuses backend changes', () {
    expect(ModelProfile.gpu, false);
    expect(ModelProfile.filename, ModelProfile.npuFilename);
    final gpu = {
      ...nativeNpu,
      'backend': 'GPU',
      'profile': 'gemma4-litert171-adreno750',
      'modelFilename': 'gemma4-e2b-gpu.litertlm',
    };
    expect(ModelProfile.configure(gpu), false);
    ModelProfile.resetForTest();
    expect(ModelProfile.configure(gpu), true);
    expect(ModelProfile.gpu, true);
    expect(ModelProfile.bytes, 2008432640);
    expect(ModelProfile.url, contains('gemma-4-E2B-it-gpu.litertlm'));
    expect(ModelProfile.configure({...gpu, 'build': 'stale'}), false);
  });

  test('S25 selects the existing NPU weights with a v79 profile', () {
    ModelProfile.resetForTest();
    expect(
      ModelProfile.configure({...nativeNpu, 'profile': 'gemma4-hexagon-v79'}),
      true,
    );
    expect(ModelProfile.filename, ModelProfile.npuFilename);
    expect(ModelProfile.bytes, 2620370976);
    expect(ModelProfile.url, endsWith('gemma4-e2b-w4.gguf'));
  });

  test('uninitialized and unsupported profiles cannot select model files', () {
    ModelProfile.resetForTest();
    expect(() => ModelProfile.filename, throwsStateError);
    for (final invalid in [
      {...nativeNpu, 'supported': false},
      {...nativeNpu, 'profile': 'unknown'},
      {...nativeNpu, 'contextWindow': 8192},
      {...nativeNpu, 'backend': 'CPU'},
    ]) {
      expect(ModelProfile.configure(invalid), false);
    }
    expect(() => ModelProfile.url, throwsStateError);
  });

  test('matching app and native profile loads the requested model', () async {
    String? loaded;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'deviceSupport') {
        return nativeNpu;
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
