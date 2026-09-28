import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the device-bound secret stored in the platform keystore.
abstract class SecureKeyStore {
  Future<Uint8List> getOrCreateDeviceSecret();
  Future<void> deleteDeviceSecret();

  /// Stores the derived key protected by biometrics (if possible) for fast unlock.
  Future<void> cacheDerivedKey(Uint8List derivedKey);

  /// Retrieves the cached derived key. Returns null if not found or biometric auth fails.
  Future<Uint8List?> getCachedDerivedKey();

  /// Clears the cached derived key (e.g., if biometrics are disabled).
  Future<void> clearCachedDerivedKey();
}

class FlutterSecureKeyStore implements SecureKeyStore {
  static const _secretKey = 'kraken_device_bound_secret';
  static const _cachedKeyKey = 'kraken_cached_derived_key';

  final FlutterSecureStorage _storage;

  FlutterSecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<Uint8List> getOrCreateDeviceSecret() async {
    final existingSecret = await _storage.read(key: _secretKey);
    if (existingSecret != null) {
      return base64Decode(existingSecret);
    }

    // Generate 32 secure random bytes
    final random = Random.secure();
    final newSecret = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      newSecret[i] = random.nextInt(256);
    }

    await _storage.write(key: _secretKey, value: base64Encode(newSecret));
    return newSecret;
  }

  @override
  Future<void> deleteDeviceSecret() async {
    await _storage.delete(key: _secretKey);
  }

  @override
  Future<void> cacheDerivedKey(Uint8List derivedKey) async {
    // In a real app, you'd use AndroidOptions/IOSOptions to enforce biometrics here
    await _storage.write(key: _cachedKeyKey, value: base64Encode(derivedKey));
  }

  @override
  Future<Uint8List?> getCachedDerivedKey() async {
    final cached = await _storage.read(key: _cachedKeyKey);
    if (cached != null) {
      return base64Decode(cached);
    }
    return null;
  }

  @override
  Future<void> clearCachedDerivedKey() async {
    await _storage.delete(key: _cachedKeyKey);
  }
}
