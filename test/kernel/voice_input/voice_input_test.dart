import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/kernel.dart';

class MockVoiceInputService implements VoiceInputService {
  bool isEnabled = true;

  @override
  Future<String> transcribeUtterance({Duration? maxDuration}) async {
    if (!isEnabled) throw VoiceInputError.notImplemented;
    await Future.delayed(const Duration(milliseconds: 10));
    return 'Transcribed Test String';
  }

  @override
  Stream<TranscriptionEvent> startLiveTranscription() async* {
    if (!isEnabled) {
      yield const TranscriptionErrorEvent(VoiceInputError.notImplemented);
      return;
    }
    yield const TranscriptionPartial('Transcribing', 0.5);
    await Future.delayed(const Duration(milliseconds: 10));
    yield const TranscriptionFinal('Final text', Duration(seconds: 1));
  }

  @override
  Future<void> stopLiveTranscription() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> stopCapture() async {}
}

void main() {
  group('VoiceInputBloc Tests', () {
    late MockVoiceInputService mockService;
    late VoiceInputBloc bloc;

    setUp(() {
      mockService = MockVoiceInputService();
      bloc = VoiceInputBloc(mockService);
    });

    tearDown(() {
      bloc.close();
    });

    test('Initial state is VoiceInputIdle', () {
      expect(bloc.state, isA<VoiceInputIdle>());
    });

    test('Emits Listening then Success on successful transcribeUtterance', () async {
      final expectedStates = [
        isA<VoiceInputListening>(),
        isA<VoiceInputSuccess>().having((s) => s.text, 'text', 'Transcribed Test String'),
      ];

      expectLater(bloc.stream, emitsInOrder(expectedStates));
      bloc.add(VoiceInputStartCapture(isLive: false));
    });

    test('Emits ErrorState when service is disabled', () async {
      mockService.isEnabled = false;

      final expectedStates = [
        isA<VoiceInputListening>(),
        isA<VoiceInputErrorState>().having((s) => s.error, 'error', VoiceInputError.notImplemented),
      ];

      expectLater(bloc.stream, emitsInOrder(expectedStates));
      bloc.add(VoiceInputStartCapture(isLive: false));
    });

    test('Emits live transcription states correctly', () async {
      final expectedStates = [
        isA<VoiceInputListening>(),
        isA<VoiceInputTranscribing>().having((s) => s.partialText, 'partialText', 'Transcribing'),
        isA<VoiceInputSuccess>().having((s) => s.text, 'text', 'Final text'),
      ];

      expectLater(bloc.stream, emitsInOrder(expectedStates));
      bloc.add(VoiceInputStartCapture(isLive: true));
    });
  });
}
