import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/inference/model_profile.dart';
import 'document_import_test.dart' as documents;

// Synthetic data only. Install with adb install -r, never flutter test on a
// populated phone: Flutter's integration runner can uninstall the existing app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  documents.main();
  testWidgets(
    'S24 GPU facts, output limits, cancellation and reload',
    (tester) async {
      const channel = MethodChannel('kraken.kernel/inference');
      final profile = await channel.invokeMapMethod<String, dynamic>(
        'deviceSupport',
      );
      expect(ModelProfile.gpu, true);
      expect(profile?['supported'], true);
      expect(profile?['backend'], 'GPU');
      final inference = LocalInferenceService();
      Future<String> answer(
        String prompt, {
        int limit = 128,
        bool continuation = false,
      }) async {
        final result = StringBuffer();
        await for (final token in inference.generateStream(
          prompt,
          maxTokens: limit,
          autoContinue: continuation,
        )) {
          result.write(token.text);
        }
        return result.toString();
      }

      await inference.loadModel();
      try {
        final clock = Stopwatch()..start();
        const facts =
            'The proposed budget was 90000 dollars but was rejected. The final approved budget is 42750 dollars. Maya owns the audit, due October 16. State only the approved budget, owner and due date in one sentence.';
        final result = await answer(facts);
        expect(result.replaceAll(',', ''), contains('42750'));
        expect(result, contains('Maya'));
        expect(result, contains('16'));
        expect(result, isNot(contains('90000')));
        debugPrint(
          'GPU_CHECK corrected_facts=PASS elapsed_ms=${clock.elapsedMilliseconds}',
        );
        expect(
          await answer(
            'State the capital of France.',
            limit: 1,
            continuation: true,
          ),
          contains('Paris'),
        );
        debugPrint('GPU_CHECK soft_limit_continuation=PASS');
        await expectLater(
          answer('Write a long essay about the ocean.', limit: 1),
          throwsException,
        );
        debugPrint('GPU_CHECK explicit_output_limit=PASS');
        await inference
            .generateStream(
              'Write a long essay about trees.',
              autoContinue: true,
            )
            .take(1)
            .drain<void>();
        expect(
          await answer('What is 17 plus 25? Reply only with the number.'),
          contains('42'),
        );
        debugPrint('GPU_CHECK cancellation_and_next_request=PASS');
        await inference.unloadModel();
        await inference.loadModel();
        expect(await answer('State the capital of France.'), contains('Paris'));
        debugPrint('GPU_CHECK unload_reload=PASS');
      } finally {
        await inference.unloadModel();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
