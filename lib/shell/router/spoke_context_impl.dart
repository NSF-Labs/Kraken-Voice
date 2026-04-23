import '../../kernel/kernel.dart';

/// The concrete implementation of SpokeContext provided by the Shell.
class HubSpokeContext implements SpokeContext {
  @override
  final String spokeId;
  final VaultService _vault;
  @override
  final KernelContext kernel;

  HubSpokeContext({
    required this.spokeId,
    required VaultService vault,
    required this.kernel,
  }) : _vault = vault;

  @override
  Future<String?> readData(String key) async {
    return _vault.readSpokeData(spokeId, key);
  }

  @override
  Future<void> writeData(String key, String value) async {
    return _vault.writeSpokeData(spokeId, key, value);
  }

  @override
  Future<void> writeEntity(
    String id,
    String type,
    Map<String, dynamic> data,
  ) async {
    // Entities are globally synced models that spokes can contribute to.
    return _vault.writeEntity(id, type, data);
  }
}
