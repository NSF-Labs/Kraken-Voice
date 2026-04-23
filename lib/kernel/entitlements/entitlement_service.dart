import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../spoke_contract.dart';

enum EntitlementSource { platform, dev, manual }

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
}

class EntitlementServiceImpl implements EntitlementService {
  final _changesController = StreamController<EntitlementChangeEvent>.broadcast();
  final Map<String, EntitlementTier> _spokeTiers = {};
  late final Future<void> _readyFuture;
  
  // Platform channel for native StoreKit / Play Billing
  static const MethodChannel _channel = MethodChannel('kraken.kernel/entitlement');

  EntitlementServiceImpl() {
    _readyFuture = _loadDevEntitlements();
  }

  @override
  Future<void> get ready => _readyFuture;

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
    try {
      // Stub: in reality this would call queryPurchases, get result, update _spokeTiers
      final result = await _channel.invokeMethod<List<dynamic>>('getCurrentEntitlements');
      if (result != null) {
        for (final item in result) {
          final id = item.toString();
          final oldTier = currentTier(id);
          _spokeTiers[id] = EntitlementTier.paid;
          if (oldTier != EntitlementTier.paid) {
            _changesController.add(EntitlementChangeEvent(
              spokeId: id,
              oldTier: oldTier,
              newTier: EntitlementTier.paid,
              source: EntitlementSource.platform,
            ));
          }
        }
      }
    } on PlatformException catch (_) {
      // Handle or ignore depending on logic
    }
  }

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
          // Platform entitlements take precedence. If already paid, do nothing.
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
