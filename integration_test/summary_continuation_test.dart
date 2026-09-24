import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:krak_en_voice/data/summary_draft_repository.dart';
import 'package:krak_en_voice/kernel/vault/vault_service.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/inference/drafted_summary_stream.dart';

class TestVault extends VaultService {
  TestVault(this.database);
  Database database;
  @override
  Database get db => database;
}

// Uses only synthetic text and an isolated encrypted database, never user data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native continuation and durable draft recovery',
    (tester) async {
      final inference = LocalInferenceService();
      final path =
          '${(await getTemporaryDirectory()).path}/continuation_check.db';
      await deleteDatabase(path);
      final vault = TestVault(
        await openDatabase(
          path,
          password: 'synthetic-test',
          version: 1,
          onCreate: (db, _) => db.execute(
            'CREATE TABLE summary_drafts (owner_key TEXT PRIMARY KEY, text TEXT NOT NULL, updated_at INTEGER NOT NULL)',
          ),
        ),
      );
      final drafts = SummaryDraftRepository(vault);
      Future<String> generate(
        String prompt,
        int limit,
        bool continuation,
      ) async {
        final output = StringBuffer();
        await for (final token in inference.generateStream(
          prompt,
          maxTokens: limit,
          autoContinue: continuation,
        )) {
          output.write(token.text);
        }
        return output.toString();
      }

      try {
        await inference.loadModel();
        const prompt = 'State the capital of France in one short sentence.';
        final baseline = await generate(prompt, 128, false);
        final continued = await generate(prompt, 1, true);
        expect(continued, baseline);
        expect(continued, contains('Paris'));
        debugPrint('CONTINUATION_CHECK exact_output_across_soft_limit=PASS');

        final longAnswer = await generate(
          'List every integer from 1 through 500 in order, separated by commas. Do not skip numbers, abbreviate, or add any other text.',
          1024,
          true,
        );
        expect(longAnswer.trim(), endsWith('500'));
        expect(await inference.countTokens(longAnswer), greaterThan(1024));
        debugPrint(
          'CONTINUATION_CHECK beyond_old_1024_limit=PASS chars=${longAnswer.length}',
        );

        // Leave about 100 context tokens, then demand a deliberately longer answer.
        const instruction =
            '\nIgnore the padding above. Write a detailed 2000 word essay about the ocean, starting immediately with the essay.';
        var low = 0;
        var high = 5000;
        while (low < high) {
          final mid = (low + high + 1) ~/ 2;
          final count = await inference.countTokens(
            '${' padding' * mid}$instruction',
          );
          if (count <= 3980) {
            low = mid;
          } else {
            high = mid - 1;
          }
        }
        var partial = '';
        Object? failure;
        try {
          await for (final token in checkpointSummaryStream(
            inference.generateStream(
              '${' padding' * low}$instruction',
              maxTokens: 1,
              autoContinue: true,
            ),
            save: (text) => drafts.save('synthetic', text),
          )) {
            partial += token.text;
          }
        } catch (error) {
          failure = error;
        }
        expect(failure, isNotNull);
        expect(failure.toString(), contains('filled the model context'));
        expect(partial, isNotEmpty);
        expect(await drafts.read('synthetic'), partial);
        await drafts.save('synthetic', '$partial checkpoint');
        expect((await vault.db.query('summary_drafts')).length, 1);
        await vault.database.close();
        vault.database = await openDatabase(path, password: 'synthetic-test');
        expect(await drafts.read('synthetic'), '$partial checkpoint');
        debugPrint(
          'CONTINUATION_CHECK hard_limit_and_encrypted_reopen=PASS chars=${partial.length}',
        );
        expect(await generate(prompt, 128, false), baseline);
        debugPrint('CONTINUATION_CHECK recovery_after_context_limit=PASS');
        await drafts.clear('synthetic');
        expect(await drafts.read('synthetic'), isNull);
        debugPrint('CONTINUATION_CHECK draft_cleanup=PASS');
      } finally {
        await inference.unloadModel();
        await vault.database.close();
        await deleteDatabase(path);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
