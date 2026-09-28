# iOS device qualification — 2026-09-28

Build under test: 0.1.4+5, org.krak-en.voice.ios. Signing team: ZVCZM72MN3 only.

## Physical devices

| Device | Model checks | Normal app installation |
| --- | --- | --- |
| iPhone 15 Pro Max, iOS 27 | Whisper and Gemma passed | Installed and launched 0.1.4+5 |
| iPhone 11, iOS 27 | Whisper passed; Gemma disabled by the 6 GB memory requirement | Installed and launched 0.1.4+5 |
| Physical iPad | Not connected to this Mac | Not installed |

The checks use generated speech and a synthetic meeting note, never user recordings.
The iPhone 15 generated: “Alex will send the budget to Morgan on Friday.”
Evidence: `device_checks/iphone15-models.json` and `device_checks/iphone11-models.json`.
Gemma downloads persist in app Documents; no physical-device app uninstall or data reset was used.
Whisper is bundled, SHA-256 verified and atomically installed on first launch.

## Virtual devices

| Device | OS | Result |
| --- | --- | --- |
| iPhone 18 Pro | iOS 27 | Passed full integration suite |
| iPhone 18 Pro Max | iOS 27 | Passed full integration suite |
| iPad Air 13-inch M4 | iPadOS 27 | Passed full integration suite |
| iPhone 17 Pro | iOS 26.5 | Passed full integration suite |

The integration test exercises onboarding, Settings → AI
Models and back, bundled Whisper transcription through FFmpeg, native recording,
pause/resume, saved-file duration, and playback. Whisper uses CPU inference in Simulator; hardware retains Metal.
Simulators explicitly report
Gemma inference unsupported because its Metal engine requires physical hardware.

Normal app entry point: `lib/main.dart`. Physical installs were confirmed running
with `devicectl`, and the signed bundle reports version 0.1.4, build 5. The same
normal entry point was built and installed on all four simulators after the integration tests; its launch was verified on iPhone 17 Pro.

## Regression checks

25 targeted Dart/widget tests passed, including cancelled/corrupt Whisper
downloads, retry, download-screen errors, onboarding completion, recording recovery,
export behavior and processing serialization. Static analysis has no errors or
warnings; informational lints remain in inherited code.

## Fixes uncovered during qualification

- FFmpeg 3.6.2 provides the native arm64 simulator slice. Simulator architectures
  are constrained to arm64 because the Whisper pod excludes Intel kernels.
- Completing onboarding now explicitly opens Home. The download route stays
  accessible after onboarding for Settings navigation.
- Gemma's baseline instantiated K/V modules for layers with shared K/V weights,
  and its custom projection wasn't quantizable. Both fixes are documented in
  `../ios/Gemma4Swift/KRAKEN_PATCH.md`; hardware inference passed after correction.
- Both workspace and project Swift package locks are synchronized, and the
  critical MLX dependencies are pinned directly in the vendored manifest.
- Continuous UI animation requires bounded frame pumping in integration tests.
- Settings cards now provide a Material surface for ListTile ink rendering.
- Home captures its audio service before disposal instead of looking up a
  deactivated widget's ancestors.
- Whisper's iPhone Metal kernels cannot run in Simulator; the vendored plugin
  uses CPU there and preserves the hardware GPU path.

## Remaining acceptance scope

These checks do not establish App Store readiness. A physical iPad still needs
installation/testing. App-update recording playback, long recordings, lock-screen/call interruptions, Bluetooth
routes, large real-world summaries, and the iPad system share sheet need hands-on
acceptance. Purchases, incoming share extension, and PDF extraction remain outside
this conversion milestone. Nothing has been submitted to App Store Connect.

## Summary crash and memory investigation — 0.1.5+6, 2026-09-28

The text-only Gemma adapter returned the entire prompt from `prepare`, bypassing
MLX's chunked prefill. It now evaluates prompt chunks of 64 tokens, clears freed
allocator buffers between chunks, and releases the completed chat session. The
bridge caps retained MLX allocator cache at 64 MiB. Interrupted iOS summary jobs
are marked failed on relaunch and require manual retry, preserving requests and
summary drafts instead of restarting inference during startup.

The latest available iPhone 15 Pro Max Jetsam report (11:40:39) killed another
process, not Runner. It does not establish the cause of the user's specific crash.
The prefill defect and automatic retry path are confirmed code findings; the
reported user transcript has not been reproduced.

Physical-device synthetic summary results (`lib/qualification/ios_summary_memory_check.dart`):

| Device | Measurement | Result |
| --- | --- | --- |
| iPhone 15 Pro Max | 211 / 735 / 1,855 input tokens, up to 512 output tokens | All three produced budget/Friday summaries, 3.3 / 3.6 / 4.8 seconds |
| iPhone 15 Pro Max | Peak sampled whole-process footprint | 3,255,668,760 bytes (3.26 GB / 3.03 GiB) |
| iPhone 15 Pro Max | MLX allocator peak | 2,702,965,030 bytes |
| iPhone 15 Pro Max | Whole-process footprint after unload | 353,389,248 bytes |
| iPhone 11 | Additional app memory allowance at startup | 2,182,084,888 bytes (2.18 GB / 2.03 GiB) |
| iPhone 11 | Gemma | Skipped: production 6 GB physical RAM requirement; model not installed |

The iPhone 11 has nominal 4 GB RAM; the connected iPhone 15 is a Pro Max with
nominal 8 GB. Physical RAM is not the app's memory allowance. On this iPhone 11,
startup footprint plus additional allowance was about 2.20 GB. These values vary
with OS and device state.

The harness samples `task_vm_info.phys_footprint` and `os_proc_available_memory`
every second and at stage boundaries. Sampling may miss transient peaks. The
3,000,000,000-byte target is **measured, not enforced**. This build exceeds that
target and does not establish stable operation with a 3 GB process ceiling.
MLX allocator limits alone do not impose a hard whole-process ceiling. A smaller
model or additional memory reductions are needed before claiming 3 GB support;
do not bypass the iPhone 11 gate based on total physical RAM alone.

Evidence: `device_checks/iphone15-summary-memory.json` and
`device_checks/iphone11-summary-memory.json`. No user audio or transcript was used
by this harness. Twelve targeted summary/processing regression tests passed,
including the iOS interrupted-job recovery test. Targeted Dart analysis had no
errors or warnings (two existing informational lints). Signed hardware builds
compiled successfully. Normal app entry point is restored after qualification;
no physical-device uninstall or data reset is performed.

Normal 0.1.5+6 (`FLUTTER_TARGET=lib/main.dart`, signed team ZVCZM72MN3) was
installed over the existing app and launched successfully on both connected
physical phones after qualification. User confirmation of the original failing
summary remains pending; synthetic success is not a guarantee for every recording.

## Audio import crash — 0.1.6+7, 2026-09-28

Both physical-device crash reports confirmed a TCC termination: the audio picker
accessed the Apple Music library without NSAppleMusicUsageDescription. This was
a permissions/configuration crash, not a memory termination.

The iOS-local file_picker 8.3.7 fork routes FileType.audio to the Files document
picker filtered to public.audio. It imports recording files from local storage
and file providers without requesting Music library access. Its private FileUtils
class is renamed KrakenFilePickerUtils to eliminate the observed collision with
Apple's OSAnalytics.framework. Both normal import entry points and the developer
audio picker share the corrected native routing. Android source is unchanged.

Validation on iPhone 15 Pro Max and iPhone 11:

- Native Files picker actually presented with the audio filter; no Music picker
  was created. Cancellation returned nil and dismissal completed.
- The native document-picker delegate imported a synthetic AAC fixture; cached
  bytes matched, copying to Documents succeeded, and AVAudioPlayer decoded it
  with a duration over one second and prepared it for playback.
- Both native XCTest cases passed on each physical device. The initial test run
  exposed a test timing issue (delegate called before presentation animation
  completed); the tests now await presentation and dismissal before proceeding.
- Existing Dart import-choice widget test passed.

The native test supplies the synthetic file to the real delegate after presenting
the real picker; it does not automate Files-provider navigation or cloud downloads.
Those interactions still need hands-on acceptance with the user's source files.
No existing recordings or documents are removed. The normal signed release is
rebuilt without the XCTest bundle after testing.

Evidence: `device_checks/audio-import-crashes.json`,
`device_checks/audio-import-fix.json`, and `ios/RunnerTests/RunnerTests.swift`.
Vendored changes: `tool/file_picker/KRAKEN_PATCH.md`.

Normal 0.1.6+7 was installed over the existing app on both physical phones and
launched successfully after testing. The release artifact contains no XCTest
bundle. No app uninstall or data reset was used.
