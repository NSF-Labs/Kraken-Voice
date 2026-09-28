# Approved Dependencies
This file lists every production dependency with a one-line note on its network behavior.

- `flutter`: core framework (none)
- `cupertino_icons`: assets (none)
- `sqflite_sqlcipher`: encrypted local database persistence (none)
- `path_provider`: local filesystem path resolution (none)
- `flutter_secure_storage`: device keystore access (none)
- `local_auth`: local biometric hardware integration (none)
- `pointycastle`: pure dart cryptography for KDF (none)
- `flutter_bloc`: state management (none)
- `equatable`: value equality for bloc state (none)
- `go_router`: declarative routing (none)
- `file_picker`: local file selection for workspace imports (none)
- `shared_preferences`: storing simple local settings/preferences (none)
- `path`: path manipulation (none)
- `yaml`: parsing yaml (none)
- `uuid`: generating unique identifiers (none)
- `dio`: HTTP client for downloading models (restricted to app/ and inference/ model downloads)

- `google_fonts`: UI fonts (may download font assets if not bundled)
- `whisper_ggml_plus`: on-device transcription (downloads speech models)
- `whisper_ggml_plus_ffmpeg`: local audio conversion for transcription (none)
- `ffmpeg_kit_flutter_new_min`: local audio processing (none)
- `just_audio`: playback of local recordings (supports URLs; app uses local files)
- `share_plus`: user-initiated sharing through the OS (destination controlled by user)
- `receive_sharing_intent`: receiving shared files from other apps (none)
- `archive`: local archive creation/extraction (none)
- `flutter_local_notifications`: local notifications and reminders (none)
- `pdf`: local PDF export generation (none)
- `image_picker`: system image selection for branding (none)
- `permission_handler`: OS permission requests (none)
- `sherpa_onnx`: on-device speaker processing (models downloaded separately)
- `url_launcher`: user-initiated links and email through external apps
- `package_info_plus`: local application version metadata (none)
- `eventide`: device calendar access (no direct app network client)
- `timezone`: bundled timezone data and conversions (none)
- `intl`: local date/number formatting (none)
- `in_app_purchase`: platform-store billing and purchase restoration (store network access)

## Boundaries

Kernel code may import Flutter `foundation.dart` for notifiers/logging and
`services.dart` for platform channels. Flutter UI belongs in app/screens/widgets.
Preference persistence belongs in `kernel/vault/PreferencesService`; SQL access
is restricted by the architecture tests to the vault and existing data consumers.
Direct Dart HTTP clients belong outside the kernel. Model-download orchestration
lives in `app/`, with the Android foreground-service bridge in `kernel/`.
Transcription and summarization remain on-device; model downloads do not upload
recording content.

`flutter_skill` is a development-only testing dependency, not a production dependency.

## Android NPU build 1.0.10-npu-sm8850+10

LiteRT-LM 0.15.0 is replaced by the pinned llama.cpp `0ef6e55` ARM64 runtime
published in `h2loop-ai/gemma-4-e2b-hexagon` revision
`1bb2044c313769541558f2c27fa67561894d0f26`. Seven libraries are verified against
`android/app/src/main/cpp/runtime-artifacts.json` before each build. The JNI
bridge uses matching vendored headers. Model/runtime selection and validated
hardware limits are documented in `RELEASE_DEVICE_POLICY.md`. No native code
is downloaded by the installed app; only the checksum-pinned GGUF weights.

## S24 GPU evaluation profile
- `com.google.ai.edge.litertlm:litertlm-android:0.17.1`: local GPU inference only; selected only by `KRAKEN_S24_GPU=true`. No runtime network calls. Kotlin 2.4.20 is selected for this build to match the 2.4 library metadata.
- Gemma 4 E2B GPU model: public download from the pinned `litert-community/gemma-4-E2B-it-litert-lm` revision `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1`, checked by SHA-256 before loading.
# Unified build 16

The unified app includes the existing LiteRT-LM 0.17.1 GPU dependency alongside
the pinned Hexagon runtime. Kotlin 2.4.20 now applies to the whole Android build.
Added the publisher's `libggml-htp-v79.so` from the same pinned revision for S25;
its size and SHA-256 are recorded in `runtime-artifacts.json`. Model weights and
network endpoints are unchanged. See `UNIFIED_RELEASE.md` for test coverage.
