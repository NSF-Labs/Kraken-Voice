import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/inference/summary_context.dart';

void main() {
  test('small transcript is passed through without condensation', () async {
    final context = SummaryContext(
      countTokens: (s) async => s.length,
      condense: (_) async => throw StateError('Unexpected condensation'),
    );
    expect(
      await context.prepare('Maya: October 16', (s) => 'Summary: $s'),
      'Summary: Maya: October 16',
    );
  });
  test(
    'long transcript includes every section and fits output budget',
    () async {
      final seen = <String>[];
      final source = '${'alpha ' * 1300}FINAL OWNER Maya: October 16';
      final context = SummaryContext(
        countTokens: (s) async => s.length,
        condense: (s) async {
          seen.add(s);
          return s.contains('FINAL OWNER')
              ? 'Maya: October 16'
              : 'Reviewed alpha';
        },
      );
      final prompt = await context.prepare(source, (s) => 'Summary: $s');
      expect(seen.length, greaterThan(1));
      expect(seen.every((prompt) => prompt.length <= 3072), isTrue);
      expect(prompt, contains('Maya: October 16'));
      expect(prompt.length, lessThanOrEqualTo(2048));
      expect(seen.map((s) => s.split('\n\n').last).join(), source);
    },
  );
  test('accepts text that fits after the final condensation pass', () async {
    var remaining = 6;
    final context = SummaryContext(
      countTokens: (_) async => remaining > 0 ? 2500 : 100,
      condense: (_) async {
        remaining--;
        return 'notes';
      },
    );
    expect(await context.prepare('source', (s) => s), 'Section 1:\nnotes');
    expect(remaining, 0);
  });
  test(
    'empty intermediate output fails rather than losing a section',
    () async {
      final context = SummaryContext(
        countTokens: (s) async => s.length,
        condense: (_) async => '',
      );
      await expectLater(
        context.prepare('x ' * 3000, (s) => s),
        throwsStateError,
      );
    },
  );
}
