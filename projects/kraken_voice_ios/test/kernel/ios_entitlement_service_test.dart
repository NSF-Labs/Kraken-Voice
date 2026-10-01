import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/entitlements/ios_entitlement_service.dart';
import 'package:krak_en_voice/kernel/entitlements/entitlement_service.dart';
import 'package:krak_en_voice/kernel/entitlements/creation_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kraken.kernel/store');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object> state;
  late DateTime now;
  late String purchaseResult;
  late bool offline;
  late IOSEntitlementService store;
  setUp(() {
    now = DateTime.utc(2026, 10, 1);
    state = {'unlocked': false, 'nowMs': now.millisecondsSinceEpoch};
    purchaseResult = 'cancelled'; offline = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status' || call.method == 'restore') return state;
      if (call.method == 'products') {
        if (offline) throw PlatformException(code: 'offline');
        return [{'id': kProductIdFullUnlock, 'price': '\$9.99'}, {'id': kProductIdTrial, 'price': '\$0.00'}];
      }
      if (call.method == 'purchase') return purchaseResult;
      return state;
    });
    store = IOSEntitlementService(channel: channel, clock: () => now);
  });
  tearDown(() { store.dispose(); CreationAccess.check = null; messenger.setMockMethodCallHandler(channel, null); });
  test('fresh install has no access until verified trial or purchase', () async {
    await store.ready;
    expect(store.canCreate, false); expect(store.canStartTrial, true);
    expect(store.fullUnlockPrice, '\$9.99');
  });
  test('trial expires at exact 30-day boundary without deleting entitlement history', () async {
    await store.ready;
    state['trialEndMs'] = now.add(const Duration(days: 30)).millisecondsSinceEpoch;
    await store.refresh();
    expect(store.canCreate, true); expect(store.trialDaysRemaining, 30);
    now = now.add(const Duration(days: 30));
    expect(store.canCreate, false); expect(store.trialStarted, true); expect(store.canStartTrial, false);
  });
  test('Apple high-water time prevents a device clock rollback reopening trial', () async {
    await store.ready;
    state['trialEndMs'] = now.add(const Duration(days: 30)).millisecondsSinceEpoch;
    state['nowMs'] = now.add(const Duration(days: 31)).millisecondsSinceEpoch;
    await store.refresh();
    expect(store.canCreate, false);
  });
  test('cancellation and pending never grant access', () async {
    await store.ready;
    expect(await store.purchaseFullUnlock(), false); expect(store.canCreate, false);
    purchaseResult = 'pending';
    expect(await store.purchaseFullUnlock(), false); expect(store.canCreate, false);
    expect(store.message, contains('pending'));
  });
  test('restored lifetime unlock supersedes expired trial and revocation removes it', () async {
    await store.ready;
    state['unlocked'] = true;
    state['trialEndMs'] = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    await store.restorePurchases();
    expect(store.canCreate, true); expect(store.lifetimeUnlocked, true);
    state['unlocked'] = false;
    await store.refresh(); expect(store.canCreate, false);
  });
  test('verified offline ownership works without a loaded price', () async {
    await store.ready;
    store.dispose(); offline = true; state['unlocked'] = true;
    store = IOSEntitlementService(channel: channel, clock: () => now);
    await store.ready;
    expect(store.canCreate, true); expect(store.canPurchase, false);
  });
  test('creation gate refuses expired access and permits active access', () async {
    await store.ready;
    CreationAccess.check = () async => store.canCreate;
    await expectLater(CreationAccess.require(), throwsStateError);
    state['unlocked'] = true; await store.refresh();
    await CreationAccess.require();
  });
}
