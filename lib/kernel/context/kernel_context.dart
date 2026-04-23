import '../voice_input/voice_input_service.dart';
import '../audio/audio_channel.dart';
import '../inference/local_inference_service.dart';
import '../vault/vault_service.dart';
import '../workspaces/workspace_service.dart';
import '../entitlements/entitlement_service.dart';

// Stubs for services not yet implemented
class ExportService {}
class SearchIndex {}
class AuditLog {}

class KernelContext {
  final AudioEngine audio;
  final LocalInferenceService inference;
  final VaultService vault;
  final WorkspaceService workspace;
  final ExportService export;
  final SearchIndex search;
  final VoiceInputService voiceInput;
  final EntitlementService entitlement;
  final AuditLog audit;

  const KernelContext({
    required this.audio,
    required this.inference,
    required this.vault,
    required this.workspace,
    required this.export,
    required this.search,
    required this.voiceInput,
    required this.entitlement,
    required this.audit,
  });
}
