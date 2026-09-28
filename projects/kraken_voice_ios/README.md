# Kraken Voice iOS

Independent iOS conversion of the current Kraken Voice Flutter source, copied
on 2026-09-27 from the Android working tree (including its uncommitted changes).
Source lives here; the Android project is not used at runtime.
Dart package name remains `krak_en_voice` to preserve internal imports.

- App: **Kraken Voice iOS**, version **0.1.6+7**
- Bundle identifier: `org.krak-en.voice.ios`
- Deployment target: iOS/iPadOS 17.0 or later
- Xcode workspace: `ios/Runner.xcworkspace`

## First conversion milestone

Implemented: AVAudioRecorder capture into persistent Documents/recordings,
permission handling, pause/resume/stop, amplitude events, duration lookup,
audio input selection, interruption saving, recording time limits, iOS
notifications, and iPad share popover anchors. Channels register after Flutter's
implicit engine initializes, supporting the UIScene lifecycle.

Carried over for device testing: encrypted vault, recording list, folders,
playback, audio export, calendar screens and preferences.

Whisper is bundled and installed with SHA-256 verification at first launch, without
network access. `scripts/prepare_models.sh` fetches the pinned build asset.
Gemma uses a vendored copy of FWPlanner's Gemma4Swift/MLX runtime
with documented shared-KV and quantized-projection fixes with model setup, progress,
cancellation, readiness checks and token budgeting. This build requires at least
6 GB of physical-device RAM for Gemma. Simulator Gemma inference is unavailable.

Pending: PDF extraction, incoming share extension, App Store purchases, and
long-running background AI processing.
The iOS background task API gives limited execution time; it does not reproduce
Android's indefinite foreground service. Recording uses the audio background mode.
Silence-triggered voice commands are not implemented in this milestone.

## Build and load

Google Drive attaches metadata that Apple's code signer rejects. Use a disposable
build copy outside cloud storage; always edit the source in this project.

```sh
./scripts/stage.sh
cd /private/tmp/kraken_voice_ios_build
flutter pub get
flutter build ios --debug --no-codesign  # compilation only
flutter devices
flutter run --release -d DEVICE_UDID    # sign, install and launch on hardware
```

The Xcode project selects the user's confirmed Apple Developer team
`ZVCZM72MN3`. Xcode must have that account signed in and be able to provision
`org.krak-en.voice.ios`. Connect/unlock the device, trust this Mac, and enable
Developer Mode if iOS requests it. See Flutter's official setup instructions:
https://docs.flutter.dev/platform-integration/ios/setup

To rebuild, install and launch in one command from this project:

```sh
./scripts/install_device.sh 00008130-000A48A11408001C
```

## Device acceptance checks

1. Complete preview onboarding; deny microphone once and verify Settings recovery.
2. Record speech, pause, resume, stop; confirm the saved entry plays correctly.
3. Lock the phone while recording; unlock and stop; verify complete playback.
4. Receive a call/Siri interruption; verify recording is saved, not left active.
5. Relaunch and verify recordings and folders persist.
6. Export audio through the system share sheet on both iPhone and iPad.
7. Verify the recording time limit stops and saves the file.

Native recording smoke test (permission must be granted on the device):

```sh
flutter test integration_test/ios_recording_test.dart -d DEVICE_UDID
```

No physical-device acceptance result should be inferred from compilation or Dart
unit tests. TestFlight/App Store submission is a later release step.

## Validation — 2026-09-27

- iPhone debug build without signing: passed.
- Signed iPhone release build: passed (89.4 MB).
- Recording safety, trial export and processing regression tests: 17 passed.
- Final static analysis: no errors or warnings; 25 informational lint findings.
- Added `integration_test/ios_recording_test.dart`; hardware execution pending.
- Apple Silicon simulator limitation: the inherited FFmpeg plugin does not
  provide the required arm64 simulator slice. Hardware builds work; simulator
  support needs a dependency change in the next conversion milestone.

Build staging directory is disposable. Re-run `scripts/stage.sh` after source
changes; remove stale source files there manually if a later conversion deletes
or renames files.

## Signing and deployment

Use **ZVCZM72MN3 only** for this project. The user explicitly confirmed this team
and reports accepting its updated agreement. Do not select a different team from
cached accounts or certificates.

Target: iPhone 15 Pro Max (`00008130-000A48A11408001C`). Device-specific
provisioning succeeded with the confirmed team. The release preview was installed
and launched successfully on this iPhone using `devicectl`. Recording/playback
acceptance checks still require hands-on testing.

## Whisper conversion — 0.1.1+2

The AI Models screen now downloads Whisper base (147,951,465 bytes), displays
progress and errors, allows cancellation/retry, and verifies the pinned SHA-256
before committing the model file. Gemma is explicitly marked unavailable. Returning
from Settings model management goes back to Settings. iOS transcription no longer
calls the missing Android inference bridge or attempts automatic Gemma summaries.

Validation: seven model-download/UI tests passed; static analysis has no errors
or warnings (26 informational findings). A release qualification build downloaded
and verified Whisper on the iPhone 15 Pro Max, converted a generated AAC sample,
and transcribed it correctly in 879 ms. See `docs/IOS_WHISPER_CHECK.json`.
The test downloaded Whisper into the app's model directory, so it is already
installed on this phone; the download prompt will still appear on a fresh install.
The generated sample is `assets/qa/whisper_check.m4a`; qualification entry point:
`lib/qualification/ios_whisper_check.dart`. This check does not record or use user audio.

FWPlanner's existing iOS Gemma source was located; see
`docs/FWPLANNER_IOS_REFERENCE.md` for the MLX integration details.

The normal 0.1.1+2 app was signed with ZVCZM72MN3, installed and launched on the
iPhone 15 Pro Max after qualification. The temporary test screen was replaced.

## Icon update — 0.1.2+3

The iOS icon now uses the Android adaptive icon background color `#0D0D1A`.
The development-only launcher icon generator is vendored under
`tool/flutter_launcher_icons` with a two-channel alpha-blending correction;
upstream 0.14.4 mixed background alpha into green, creating bright green fringes
when flattening the transparent logo over a dark color. The corrected generated
1024px icon was visually checked. Regenerate using `dart run flutter_launcher_icons`.

Version 0.1.2+3 was signed with ZVCZM72MN3, installed and launched on the iPhone
15 Pro Max on 2026-09-28.

## Model and simulator update — 0.1.4+5

FFmpeg is pinned to 3.6.2 for native arm64 simulator support. Simulator builds
select arm64 because the Whisper pod excludes Intel kernels. Xcode's Metal
Toolchain component is required for MLX. Swift package revisions are locked to
the FWPlanner reference versions.

Run `scripts/test_simulator.sh SIMULATOR_UUID` against a booted simulator.
`lib/qualification/ios_models_check.dart` installs models and checks generated
speech and a synthetic meeting note on hardware; restore `lib/main.dart` afterward.
Qualification does not read user recordings. The Gemma model is downloaded into
persistent app storage; Whisper is included in the app bundle. Historical results
above apply only to their specified builds; current results are recorded in
`docs/IOS_DEVICE_TESTING.md`.

Whisper's iOS-only plugin fork under `tool/whisper_ggml_plus` selects CPU inference
for Simulator while preserving Metal on hardware. Run `scripts/prepare_models.sh`
before running tests directly from a fresh checkout. The model bytes are ignored
by Git and downloaded from the pinned revision with checksum validation.
