import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/processing/background_processing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kraken.kernel/processing');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'transcription and summaries serialize and share a foreground lease',
    () async {
      final queue = BackgroundProcessing();
      final blocked = Completer<void>();
      final started = Completer<void>();
      final order = <String>[];
      final first = queue.run('transcribe', () async {
        order.add('transcribe');
        started.complete();
        await blocked.future;
      });
      await started.future;
      final second = queue.run('summary', () async {
        order.add('summary');
      });
      await Future<void>.delayed(Duration.zero);
      expect(order, ['transcribe']);
      expect(calls, ['start']);
      blocked.complete();
      await Future.wait([first, second]);
      await Future<void>.delayed(Duration.zero);
      expect(order, ['transcribe', 'summary']);
      expect(calls, ['start', 'stop']);
    },
  );

  test(
    'same recording deduplicates and a failed task does not poison later work',
    () async {
      final queue = BackgroundProcessing();
      final gate = Completer<void>();
      final first = queue.run('recording', () async {
        await gate.future;
        throw StateError('native failure');
      });
      final duplicate = queue.run('recording', () async {
        fail('duplicate ran');
      });
      expect(identical(first, duplicate), true);
      final failure = expectLater(first, throwsStateError);
      var recovered = false;
      final next = queue.run('next', () async {
        recovered = true;
      });
      gate.complete();
      await failure;
      await next;
      expect(recovered, true);
      expect(calls, ['start', 'stop']);
    },
  );

  test(
    'foreground rejection never starts unprotected model work and releases queue',
    () async {
      final queue = BackgroundProcessing();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'start')
              throw PlatformException(code: 'background_restricted');
            return null;
          });
      await expectLater(
        queue.run('job', () async {
          fail('ran without foreground protection');
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['start', 'stop']);
    },
  );
}
