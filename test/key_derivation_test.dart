import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraken_hub/kernel/kernel.dart';

void main() {
  group('KeyDerivation', () {
    test('derives deterministic 32-byte key', () {
      final deviceSecret = Uint8List.fromList(List.generate(32, (index) => index));
      final passphrase = 'TestPassphrase123!';

      final key1 = KeyDerivation.deriveVaultKey(
        passphrase: passphrase,
        deviceSecret: deviceSecret,
      );

      final key2 = KeyDerivation.deriveVaultKey(
        passphrase: passphrase,
        deviceSecret: deviceSecret,
      );

      expect(key1.length, 32);
      expect(key1, equals(key2));
    });

    test('produces different keys for different passphrases', () {
      final deviceSecret = Uint8List.fromList(List.generate(32, (index) => index));

      final key1 = KeyDerivation.deriveVaultKey(
        passphrase: 'PasswordA',
        deviceSecret: deviceSecret,
      );

      final key2 = KeyDerivation.deriveVaultKey(
        passphrase: 'PasswordB',
        deviceSecret: deviceSecret,
      );

      expect(key1, isNot(equals(key2)));
    });
  });
}
