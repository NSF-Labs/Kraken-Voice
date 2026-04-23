import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Handles deriving the master vault encryption key from the passphrase and device secret.
class KeyDerivation {
  /// Derives a 256-bit (32-byte) key using Argon2id.
  ///
  /// The [passphrase] is used as the password.
  /// The [deviceSecret] is used as the salt.
  static Uint8List deriveVaultKey({
    required String passphrase,
    required Uint8List deviceSecret,
  }) {
    final passwordBytes = utf8.encode(passphrase);

    // Argon2id parameters (tune for mobile performance vs security as needed)
    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      deviceSecret, // 32 bytes device secret acts as our salt
      desiredKeyLength: 32, // 256-bit AES key
      iterations: 2,
      memoryPowerOf2: 15, // 32MB
      lanes: 1,
    );

    final argon2 = Argon2BytesGenerator();
    argon2.init(parameters);

    final result = argon2.process(passwordBytes);

    return result;
  }
}
