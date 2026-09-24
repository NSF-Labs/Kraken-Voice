import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/device_support.dart';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'document_import_test.dart' as documents;

// Synthetic fixtures only. Install with adb install -r to preserve app data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  documents.main();
  testWidgets('unified routing, cancellation and reload', (tester) async {
    expect(await DeviceSupport.isSupported(), true);
    final native = await const MethodChannel('kraken.kernel/inference')
        .invokeMapMethod<String, dynamic>('deviceSupport');
    expect(native?['build'], '1.0.16+16');
    expect(native?['modelFilename'], ModelProfile.filename);
    expect(native?['backend'], ModelProfile.gpu ? 'GPU' : 'NPU');
    final service = LocalInferenceService();
    Future<String> answer() async {
      final output = StringBuffer();
      await for (final token in service.generateStream(
        'What is 17 plus 25? Answer only the number.', maxTokens: 64,
      )) { output.write(token.text); }
      return output.toString();
    }
    await service.loadModel();
    try {
      expect(await answer(), contains('42'));
      await service.generateStream('Count from one to fifty.', maxTokens: 128)
          .take(1).drain<void>();
      expect(await answer(), contains('42'));
      await service.unloadModel();
      await service.loadModel();
      expect(await answer(), contains('42'));
      debugPrint('UNIFIED_CHECK backend=${native?["backend"]} routing_cancel_reload=PASS');
    } finally { await service.unloadModel(); }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
