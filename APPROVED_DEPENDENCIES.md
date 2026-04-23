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
- `dio`: HTTP client for downloading models (restricted to shell)
## Voice Input Service Note
- No new external Flutter packages were added for the `VoiceInputService`. It utilizes the existing native `AudioEngine` channel stub for zero-cloud, on-device audio capture and processing.
