import 'package:flutter/widgets.dart';

import 'context/kernel_context.dart';

/// The SpokeContext is the only way a Spoke can communicate with the Hub.
/// It provides scoped access to the Vault and other Kernel services.
abstract class SpokeContext {
  /// The unique ID of the spoke requesting context.
  String get spokeId;

  /// Access to global kernel services like VoiceInput.
  KernelContext get kernel;

  /// Writes data specific to this spoke.
  Future<void> writeData(String key, String value);

  /// Reads data specific to this spoke.
  Future<String?> readData(String key);

  /// Writes to the shared entity table (restricted to allowed types).
  Future<void> writeEntity(String id, String type, Map<String, dynamic> data);
}

enum SpokePermission {
  microphone,
  camera,
  files,
}

enum EntitlementTier {
  free,
  paid,
}

class SpokeMetadata {
  final String displayName;
  final String description;
  final IconData icon;
  final List<SpokePermission> requiredPermissions;
  final EntitlementTier tier;

  const SpokeMetadata({
    required this.displayName,
    required this.description,
    required this.icon,
    this.requiredPermissions = const [],
    this.tier = EntitlementTier.free,
  });
}

abstract class SpokeModule {
  String get spokeId;
  SpokeMetadata get metadata;

  Future<void> initialize(KernelContext kernel);
  Future<void> dispose();

  Widget buildUi(SpokeContext context);
}
