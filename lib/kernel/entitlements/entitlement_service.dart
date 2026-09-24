import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:krak_en_voice/kernel/vault/preferences_service.dart';

/// Product ID for the one-time unlock on Google Play.
/// Must match the product ID created in Play Console → Monetize → Products.
const String kProductIdFullUnlock = 'krak_en_voice_full_unlock';

/// Entitlement tier for feature access.
enum EntitlementTier { free, paid }

enum EntitlementSource { platform, dev, manual, restored }

class EntitlementChangeEvent {
  final String spokeId;
  final EntitlementTier oldTier;
  final EntitlementTier newTier;
  final EntitlementSource source;

  EntitlementChangeEvent({
    required this.spokeId,
    required this.oldTier,
    required this.newTier,
    required this.source,
  });
}

abstract class EntitlementService {
  bool isUnlocked(String spokeId);
  EntitlementTier currentTier(String spokeId);
  Stream<EntitlementChangeEvent> get changes;
  Future<void> syncFromPlatform();
  /// Completes when initial entitlement data (including dev overrides) is loaded.
  Future<void> get ready;

  /// Initiate the purchase flow for the full unlock.
  Future<bool> purchaseFullUnlock();

  /// Restore purchases (e.g. after reinstall).
  Future<void> restorePurchases();

  /// Whether the billing system is available.
  bool get isStoreAvailable;

  /// Dispose of streams.
  void dispose();
}

class EntitlementServiceImpl implements EntitlementService {
  final _changesController = StreamController<EntitlementChangeEvent>.broadcast();
  final Map<String, EntitlementTier> _spokeTiers = {};
  late final Future<void> _readyFuture;

  // In-app purchase
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _fullUnlockProduct;
  bool _storeAvailable = false;

  // Persistent flag to survive app restarts without re-querying store
  static const String _purchasedKey = 'krak_en_purchased';

  EntitlementServiceImpl() {
    _readyFuture = _initialize();
  }

  Future<void> _initialize() async {
    // Check local cache first (instant unlock on restart)
    await _loadLocalPurchaseState();

    // Load dev overrides (debug builds only)
    await _loadDevEntitlements();

    // Initialize store connection
    _storeAvailable = await _iap.isAvailable();
    if (!_storeAvailable) return;

    // Listen for purchase updates
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _purchaseSubscription?.cancel(),
      onError: (error) {
        // Log but don't crash — purchase errors are recoverable
        print('[Entitlement] Purchase stream error: $error');
      },
    );

    // Load product details
    final response = await _iap.queryProductDetails({kProductIdFullUnlock});
    if (response.productDetails.isNotEmpty) {
      _fullUnlockProduct = response.productDetails.first;
    }

    // Restore any past purchases (handles reinstalls)
    await _iap.restorePurchases();
  }

  @override
  Future<void> get ready => _readyFuture;

  @override
  bool get isStoreAvailable => _storeAvailable;

  @override
  Stream<EntitlementChangeEvent> get changes => _changesController.stream;

  @override
  bool isUnlocked(String spokeId) {
    return currentTier(spokeId) == EntitlementTier.paid;
  }

  @override
  EntitlementTier currentTier(String spokeId) {
    return _spokeTiers[spokeId] ?? EntitlementTier.free;
  }

  @override
  Future<void> syncFromPlatform() async {
    if (!_storeAvailable) return;
    await _iap.restorePurchases();
  }

  @override
  Future<bool> purchaseFullUnlock() async {
    if (_fullUnlockProduct == null) {
      print('[Entitlement] Product not loaded — cannot purchase');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: _fullUnlockProduct!);
    // Non-consumable = one-time purchase, permanently owned
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> restorePurchases() async {
    if (!_storeAvailable) return;
    await _iap.restorePurchases();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _changesController.close();
  }

  // ── Purchase handling ──────────────────────────────────────────────────────

  void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      if (purchase.productID != kProductIdFullUnlock) continue;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _grantFullAccess(
            purchase.status == PurchaseStatus.restored
                ? EntitlementSource.restored
                : EntitlementSource.platform,
          );
          // Complete the purchase to acknowledge it with Google Play
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.error:
          print('[Entitlement] Purchase error: ${purchase.error?.message}');
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.canceled:
          // User cancelled — no action needed
          break;

        case PurchaseStatus.pending:
          // Payment is processing — could show a "pending" indicator
          break;
      }
    }
  }

  void _grantFullAccess(EntitlementSource source) {
    const spokeId = 'com.kraken.meeting_notes';
    final oldTier = currentTier(spokeId);
    if (oldTier == EntitlementTier.paid) return; // Already unlocked

    _spokeTiers[spokeId] = EntitlementTier.paid;
    _changesController.add(EntitlementChangeEvent(
      spokeId: spokeId,
      oldTier: oldTier,
      newTier: EntitlementTier.paid,
      source: source,
    ));

    // Persist locally so next launch is instant
    _saveLocalPurchaseState();
  }

  // ── Local persistence ─────────────────────────────────────────────────────

  Future<void> _loadLocalPurchaseState() async {
    try {
      final prefs = PreferencesService();
      if (await prefs.getBool(_purchasedKey)) {
        _spokeTiers['com.kraken.meeting_notes'] = EntitlementTier.paid;
      }
    } catch (_) {}
  }

  Future<void> _saveLocalPurchaseState() async {
    try {
      final prefs = PreferencesService();
      await prefs.setBool(_purchasedKey, true);
    } catch (_) {}
  }

  // ── Dev overrides (debug builds) ──────────────────────────────────────────

  Future<void> _loadDevEntitlements() async {
    bool isDev = const bool.fromEnvironment('dart.vm.product') == false;
    const String devFlag = String.fromEnvironment('KRAKEN_DEV', defaultValue: 'false');
    if (devFlag == 'true') {
      isDev = true;
    }

    if (!isDev) return;

    try {
      final jsonString = await rootBundle.loadString('assets/entitlements.dev.json');
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final unlockedList = data['unlocked_spokes'] as List<dynamic>?;

      if (unlockedList != null) {
        for (final item in unlockedList) {
          final id = item.toString();
          if (_spokeTiers[id] != EntitlementTier.paid) {
            final oldTier = currentTier(id);
            _spokeTiers[id] = EntitlementTier.paid;
            _changesController.add(EntitlementChangeEvent(
              spokeId: id,
              oldTier: oldTier,
              newTier: EntitlementTier.paid,
              source: EntitlementSource.dev,
            ));
          }
        }
      }
    } catch (e) {
      // JSON missing or malformed, ignore
    }
  }
}
