import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/inference/drafted_summary_stream.dart';

void main() {
  test(
    'a limit error preserves all emitted text, including the final short tail',
    () async {
      final saves = <String>[];
      Stream<InferenceToken> source() async* {
        yield InferenceToken('A' * 600);
        yield const InferenceToken('Maya: October 16.');
        throw StateError('Context full');
      }

      await expectLater(
        checkpointSummaryStream(
          source(),
          save: (text) async => saves.add(text),
        ).drain<void>(),
        throwsStateError,
      );
      expect(saves.first.length, 600);
      expect(saves.last, '${'A' * 600}Maya: October 16.');
    },
  );
  test(
    'continuation preserves output ordering without duplicating a boundary',
    () async {
      final saves = <String>[];
      final output = StringBuffer();
      await for (final token in checkpointSummaryStream(
        Stream.fromIterable([
          const InferenceToken('Start '),
          const InferenceToken('continued '),
          const InferenceToken('finished.'),
        ]),
        save: (text) async => saves.add(text),
      )) {
        output.write(token.text);
      }
      expect(output.toString(), 'Start continued finished.');
      expect(saves.single, output.toString());
    },
  );
  test('cancellation checkpoints the received draft', () async {
    String? saved;
    await checkpointSummaryStream(
      Stream.fromIterable([
        const InferenceToken('Partial text'),
        const InferenceToken(' should not arrive'),
      ]),
      save: (text) async => saved = text,
    ).take(1).drain<void>();
    expect(saved, 'Partial text');
  });
}
