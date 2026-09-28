import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:krak_en_voice/app/app_lifecycle_bloc.dart';
import 'package:krak_en_voice/kernel/vault/preferences_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/app/ios_whisper_download.dart';
import 'package:krak_en_voice/screens/onboarding/download_screen.dart';

class TestPreferences extends PreferencesService {
  bool onboarded = false;
  @override
  Future<void> setOnboarded() async { onboarded = true; }
  @override
  Future<bool> getIsOnboarded() async => onboarded;
}

class TestDownload extends IOSWhisperDownload {
  @override
  Future<void> check() async { checking = false; notifyListeners(); }
  @override
  Future<void> download() async {
    error = 'Network unavailable. Please retry.';
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('kraken.kernel/inference'), (_) async => {
        'supported': false, 'ready': false, 'reason': 'Gemma requires a supported physical device.',
      },
    );
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('kraken.kernel/inference'), null,
  ));
  testWidgets('offers Whisper download, explains Gemma status, stays on screen after error', (tester) async {
    final download = TestDownload();
    await tester.pumpWidget(MaterialApp(home: DownloadScreen(download: download)));
    await tester.pumpAndSettle();
    expect(find.text('Download Whisper'), findsOneWidget);
    expect(find.textContaining('Gemma requires a supported physical device.'), findsOneWidget);
    await tester.tap(find.text('Download Whisper'));
    await tester.pumpAndSettle();
    expect(find.text('Network unavailable. Please retry.'), findsOneWidget);
    expect(find.text('AI Models'), findsOneWidget);
    expect(find.text('Download Whisper'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    download.dispose();
  });
  testWidgets('finishing first-time model setup opens Home and persists onboarding', (tester) async {
    final preferences = TestPreferences();
    final download = TestDownload()..ready = true;
    final lifecycle = AppLifecycleBloc(preferences);
    final router = GoRouter(initialLocation: '/models', routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('Home reached'))),
      GoRoute(path: '/models', builder: (_, _) => DownloadScreen(download: download)),
    ]);
    await tester.pumpWidget(BlocProvider.value(value: lifecycle,
      child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Home reached'), findsOneWidget);
    expect(preferences.onboarded, isTrue);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await tester.runAsync(lifecycle.close);
    download.dispose();
  });

}
