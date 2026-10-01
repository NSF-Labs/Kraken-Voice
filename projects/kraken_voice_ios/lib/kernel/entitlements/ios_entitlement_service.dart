import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'entitlement_service.dart';

const kProductIdTrial = 'krak_en_voice_30_day_trial';
const kPrivacyPolicyUrl = 'https://krak-en.org/voice/privacy-policy';

/// iOS access derives exclusively from verified StoreKit transactions.
class IOSEntitlementService
    with WidgetsBindingObserver
    implements EntitlementService {
  IOSEntitlementService({MethodChannel? channel, DateTime Function()? clock})
    : _channel = channel ?? const MethodChannel('kraken.kernel/store'),
      _clock = clock ?? DateTime.now {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed')
        _apply(Map<Object?, Object?>.from(call.arguments as Map));
    });
    WidgetsBinding.instance.addObserver(this);
    _ready = refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }
  final MethodChannel _channel;
  final DateTime Function() _clock;
  final _changes = StreamController<EntitlementChangeEvent>.broadcast();
  late final Future<void> _ready;
  Timer? _timer;
  bool _disposed = false;
  bool lifetimeUnlocked = false;
  DateTime? trialEnd;
  DateTime? _verifiedNow;
  final Map<String, String> _prices = {};
  String? error;
  bool busy = false;
  String? message;
  bool get trialStarted => trialEnd != null;
  bool get canStartTrial =>
      !trialStarted && _prices.containsKey(kProductIdTrial);
  bool get canPurchase => _prices.containsKey(kProductIdFullUnlock);
  DateTime get _now {
    final now = _clock();
    return _verifiedNow != null && now.isBefore(_verifiedNow!)
        ? _verifiedNow!
        : now;
  }

  bool get trialActive => trialEnd != null && _now.isBefore(trialEnd!);
  int get trialDaysRemaining =>
      trialActive ? (trialEnd!.difference(_now).inSeconds / 86400).ceil() : 0;
  bool get canCreate => lifetimeUnlocked || trialActive;

  @override
  Future<void> get ready => _ready;
  @override
  bool get isStoreAvailable => canPurchase;
  @override
  String get fullUnlockPrice => _prices[kProductIdFullUnlock] ?? r'US$9.99';
  @override
  Stream<EntitlementChangeEvent> get changes => _changes.stream;
  @override
  bool isUnlocked(String spokeId) =>
      spokeId == 'com.kraken.meeting_notes' && canCreate;
  @override
  EntitlementTier currentTier(String spokeId) =>
      isUnlocked(spokeId) ? EntitlementTier.paid : EntitlementTier.free;

  void _notify() {
    if (!_disposed)
      _changes.add(
        EntitlementChangeEvent(
          spokeId: 'com.kraken.meeting_notes',
          oldTier: EntitlementTier.free,
          newTier: currentTier('com.kraken.meeting_notes'),
          source: EntitlementSource.platform,
        ),
      );
  }

  void _apply(Map<Object?, Object?> state) {
    lifetimeUnlocked = state['unlocked'] == true;
    trialEnd = state['trialEndMs'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (state['trialEndMs'] as num).toInt(),
          )
        : null;
    _verifiedNow = state['nowMs'] is num
        ? DateTime.fromMillisecondsSinceEpoch((state['nowMs'] as num).toInt())
        : null;
    _notify();
  }

  Future<void> refresh() async {
    try {
      final state = await _channel.invokeMapMethod<Object?, Object?>('status');
      if (state != null) _apply(state);
      if (_prices.length < 2) {
        final products =
            await _channel.invokeListMethod<dynamic>('products') ?? [];
        for (final dynamic p in products) {
          _prices[p['id'] as String] = p['price'] as String;
        }
      }
      error = null;
    } catch (e) {
      error = e is PlatformException
          ? e.message
          : 'The App Store is unavailable. Please try again.';
    }
    _notify();
  }

  Future<bool> _purchase(String id) async {
    if (busy) return false;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      final result = await _channel.invokeMethod<String>('purchase', id);
      await refresh();
      if (result == 'pending')
        message =
            'Purchase pending approval. Access will update when Apple confirms it.';
      return result == 'purchased';
    } on PlatformException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> startTrial() => _purchase(kProductIdTrial);
  @override
  Future<bool> purchaseFullUnlock() => _purchase(kProductIdFullUnlock);
  Future<void> _action(String method) async {
    if (busy) return;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      final state = await _channel.invokeMapMethod<Object?, Object?>(method);
      if (state != null) _apply(state);
      message = lifetimeUnlocked
          ? 'Lifetime access restored.'
          : trialActive
          ? 'Your trial is active.'
          : 'No active access found for this Apple Account.';
    } on PlatformException catch (e) {
      error = e.message;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> redeemCode() => _action('redeem');
  @override
  Future<void> restorePurchases() => _action('restore');
  @override
  Future<void> syncFromPlatform() => refresh();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    _changes.close();
  }
}
