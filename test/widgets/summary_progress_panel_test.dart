import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/widgets/summary_progress_panel.dart';

void main() {
  testWidgets(
    'shows measured work, estimated bar and elapsed time; timer disposes',
    (tester) async {
      final start = DateTime.now().subtract(const Duration(seconds: 90));
      Widget panel(double progress, String phase, String activity) =>
          MaterialApp(
            home: Scaffold(
              body: SummaryProgressPanel(
                progress: progress,
                phase: phase,
                activity: activity,
                startedAt: start,
              ),
            ),
          );
      await tester.pumpWidget(
        panel(
          .25,
          'Pass 1: reading section 2 of 4',
          '300 characters of notes written',
        ),
      );
      expect(find.text('Pass 1: reading section 2 of 4'), findsOneWidget);
      expect(
        find.textContaining('Estimated progress: 25% · Elapsed 1:'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .25,
      );
      await tester.pumpWidget(
        panel(.85, 'Writing summary...', '900 characters written'),
      );
      expect(find.text('900 characters written'), findsOneWidget);
      expect(find.textContaining('Estimated progress: 85%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
