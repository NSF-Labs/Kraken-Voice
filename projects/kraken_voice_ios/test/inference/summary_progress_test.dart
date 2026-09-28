import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/inference/summary_context.dart';
import 'package:krak_en_voice/kernel/inference/summary_progress.dart';

void main() {
  test(
    'section progress advances only after successful work, across passes',
    () async {
      final updates = <SummarySectionProgress>[];
      final context = SummaryContext(
        countTokens: (text) async => text.length,
        condense: (_) async => 'Useful short notes',
        onProgress: updates.add,
      );
      await context.prepare('source ' * 1200, (s) => s);
      expect(updates.first.completed, 0);
      expect(updates.first.total, greaterThan(1));
      expect(updates.last.completed, updates.last.total);
      for (var i = 1; i < updates.length; i++) {
        expect(
          updates[i].estimate,
          greaterThanOrEqualTo(updates[i - 1].estimate),
        );
      }
      expect(
        const SummarySectionProgress(2, 0, 2).estimate,
        const SummarySectionProgress(1, 4, 4).estimate,
      );
    },
  );
  test('failed section never reports itself complete', () async {
    final updates = <SummarySectionProgress>[];
    final context = SummaryContext(
      countTokens: (text) async => text.length,
      condense: (_) async => throw StateError('inference failure'),
      onProgress: updates.add,
    );
    await expectLater(
      context.prepare('source ' * 1200, (s) => s),
      throwsStateError,
    );
    expect(updates.single.completed, 0);
  });
  test('continued output keeps advancing without claiming completion', () {
    expect(
      summaryWritingProgress(20000),
      greaterThan(summaryWritingProgress(10000)),
    );
    expect(summaryWritingProgress(1000000), lessThan(0.99));
  });
}
