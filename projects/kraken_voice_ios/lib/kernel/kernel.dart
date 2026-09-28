// Kernel exports
// The kernel contains core services. No UI. No knowledge of specific spokes.
// v5: Spoke contract, spoke registry, and workspaces removed.

export 'auth/auth_bloc.dart';
export 'auth/auth_event.dart';
export 'auth/auth_state.dart';
export 'auth/key_derivation.dart';
export 'auth/secure_keystore.dart';

export 'vault/vault_service.dart';
export 'vault/preferences_service.dart';
export 'retention/retention_service.dart';

export 'inference/local_inference_service.dart';
export 'inference/inference_bloc.dart';
export 'audio/audio_channel.dart';
export 'audio/diarizer.dart';
export 'audio/embedding_cache.dart';
export 'audio/nemo_diarizer.dart';
export 'audio/whisper_segment.dart';

export 'context/kernel_context.dart';
export 'voice_input/voice_input_service.dart';
export 'voice_input/voice_input_bloc.dart';
export 'entitlements/entitlement_service.dart';
