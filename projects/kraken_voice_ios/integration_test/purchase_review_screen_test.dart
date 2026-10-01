import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krak_en_voice/main.dart' as app;
import 'package:krak_en_voice/kernel/vault/preferences_service.dart';
import 'package:krak_en_voice/kernel/entitlements/entitlement_service.dart';
import 'package:krak_en_voice/kernel/entitlements/ios_entitlement_service.dart';
import 'package:krak_en_voice/widgets/ios_purchase_dialog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    .framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('capture the actual purchase disclosure for App Review', (tester) async {
    await PreferencesService().setOnboarded();
    await app.main();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      if (find.text('Press to Record').evaluate().isNotEmpty) break;
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump(const Duration(seconds: 1));
    final context = tester.element(find.byType(Scaffold).first);
    final store = context.read<EntitlementService>() as IOSEntitlementService;
    await store.ready;
    // Uses the real StoreKit bridge and the app's actual purchase dialog.
    if (find.text('Redeem Offer Code').evaluate().isEmpty) {
      showIOSPurchaseDialog(context, store);
    }
    for (var i = 0; i < 5; i++) { await tester.pump(const Duration(seconds: 1)); }
    expect(find.text('Start 30-day Trial — Free'), findsOneWidget);
    expect(find.text('Redeem Offer Code'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    debugPrint('VOICE_REVIEW_SCREEN_READY_V3');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 40)));
    store.dispose();
  });
}
