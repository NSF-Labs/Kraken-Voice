import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/inference/summary_quality.dart';

void main() {
  test('rejects mixed-script corruption of an English source', () {
    expect(
      hasCorruptedSummaryText(
        '表中 論 Key topics После recurring Что खुद help금',
        source: 'A meeting about scheduling and support.',
      ),
      true,
    );
  });
  test('preserves accented names and legitimate multilingual summaries', () {
    expect(
      hasCorruptedSummaryText(
        'André and María will meet on October 16.',
        source: 'André and María discussed dates.',
      ),
      false,
    );
    expect(
      hasCorruptedSummaryText('今日は会議の重要事項を確認しました。', source: '今日は会議を行いました。'),
      false,
    );
  });
  test('rejects a repeated phrase loop', () {
    expect(
      hasCorruptedSummaryText(
        'Need to make sure ' * 6,
        source: 'We discussed scheduling.',
      ),
      true,
    );
  });
}
