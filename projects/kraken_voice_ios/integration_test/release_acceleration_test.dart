import 'package:krak_en_voice/kernel/inference/summary_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';

// Only model inference: never opens, clears, or modifies the user's vault.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'S26 accelerated inference: short, long, repeated requests',
    (tester) async {
      const channel = MethodChannel('kraken.kernel/inference');
      final support = await channel.invokeMapMethod<String, dynamic>(
        'deviceSupport',
      );
      expect(support?['supported'], true);
      expect(support?['backend'], 'NPU');
      final service = LocalInferenceService();
      final load = Stopwatch()..start();
      await service.loadModel().timeout(const Duration(minutes: 3));
      debugPrint(
        'RELEASE_BENCH load_ms=${load.elapsedMilliseconds} soc=${support?['soc']} backend=NPU',
      );
      try {
        final context = List.generate(
          60,
          (i) =>
              'Agenda item $i: The team reviewed progress, discussed testing, and agreed to keep the existing schedule.',
        ).join('\n');
        final prompts = [
          'Answer in one sentence: What is the capital of France?',
          '$context\nFinal decision: Approve a budget of 42750 dollars. Maya must deliver the audit by October 16. '
              'Summarize ONLY the final decision, amount, owner and deadline in one sentence.',
          'Answer in one sentence: What is 17 plus 25?',
        ];
        for (var i = 0; i < prompts.length; i++) {
          final watch = Stopwatch()..start();
          int? firstMs;
          final output = StringBuffer();
          await for (final token
              in service
                  .generateStream(prompts[i], maxTokens: 256)
                  .timeout(const Duration(minutes: 2))) {
            firstMs ??= watch.elapsedMilliseconds;
            output.write(token.text);
          }
          debugPrint(
            'RELEASE_BENCH case=$i first_ms=$firstMs total_ms=${watch.elapsedMilliseconds} output=$output',
          );
          expect(output.toString().trim(), isNotEmpty);
          expect(watch.elapsed, lessThan(const Duration(seconds: 60)));
          if (i == 0) {
            expect(output.toString().toLowerCase(), contains('paris'));
          }
          if (i == 1) {
            expect(output.toString(), contains('Maya'));
            expect(output.toString().replaceAll(',', ''), contains('42750'));
            expect(output.toString(), contains('16'));
          }
          if (i == 2) expect(output.toString(), contains('42'));
        }
        Future<String> answer(String prompt, {int limit = 128}) async {
          final text = StringBuffer();
          await for (final token in service.generateStream(
            prompt,
            maxTokens: limit,
          )) {
            text.write(token.text);
          }
          return text.toString();
        }

        final count = await service.countTokens(
          'The capital of France is Paris.',
        );
        expect(count, greaterThan(0));
        await expectLater(answer('word ' * 5000), throwsException);
        await expectLater(
          answer('Explain the history of Paris.', limit: 1),
          throwsException,
        );
        expect(
          await answer('What is 17 plus 25? Answer briefly.'),
          contains('42'),
        );
        debugPrint('RELEASE_BENCH bounds_and_recovery=PASS');

        await service
            .generateStream('Write a long history of France.', maxTokens: 1024)
            .take(1)
            .drain<void>();
        expect(
          await answer('What is the capital of France? Answer briefly.'),
          contains('Paris'),
        );
        debugPrint('RELEASE_BENCH cancel_and_recovery=PASS');

        final corrected = await answer(
          'Elena proposed 31000 dollars and March 8. That was rejected. '
          'The final approved budget is 28500 dollars. Omar owns the audit due March 22. '
          'Give only the final amount, owner and deadline in one sentence.',
        );
        expect(corrected.replaceAll(',', ''), contains('28500'));
        expect(corrected, contains('Omar'));
        expect(corrected, contains('22'));
        debugPrint('RELEASE_BENCH correction=PASS output=$corrected');
        final unicode = await answer(
          'Answer in French: what is the capital of France?',
        );
        expect(unicode, contains('Paris'));
        expect(unicode, isNot(contains('�')));

        final longTranscript =
            '$context\n$context\n$context\n$context\n'
            'Final approved decision: 42750 dollars; Maya owns the audit due October 16.';
        var chunks = 0;
        final prepared =
            await SummaryContext(
              countTokens: service.countTokens,
              condense: (section) async {
                chunks++;
                return answer(section, limit: 768);
              },
            ).prepare(
              longTranscript,
              (text) =>
                  '$text\nState the final approved amount, owner and deadline in one sentence.',
            );
        expect(chunks, greaterThan(1));
        expect(await service.countTokens(prepared), lessThanOrEqualTo(3072));
        final condensed = await answer(prepared);
        expect(condensed.replaceAll(',', ''), contains('42750'));
        expect(condensed, contains('Maya'));
        expect(condensed, contains('16'));
        debugPrint(
          'RELEASE_BENCH long_summary=PASS chunks=$chunks output=$condensed',
        );

        await service.unloadModel();
        await service.loadModel();
        expect(
          await answer('What is the capital of France? Answer briefly.'),
          contains('Paris'),
        );
        debugPrint('RELEASE_BENCH reload=PASS');
      } finally {
        await service.unloadModel();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
