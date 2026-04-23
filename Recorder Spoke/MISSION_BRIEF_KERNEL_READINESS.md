# Mission Brief: Kernel Readiness for Meeting Notes

## Purpose

Close the five kernel-level gaps discovered during Meeting Notes Handoff 1 implementation. These gaps prevent Meeting Notes (and any future spoke) from being built on a solid foundation:

1. SpokeModule contract drift between Hub Implementation Plan and actual `lib/kernel/spoke_contract.dart`.
2. EntitlementService missing entirely — `entitlements.dev.json` and kernel service both absent.
3. Audio engine has no live amplitude EventChannel.
4. Android has no foreground service for background recording.
5. iOS is not configured for background audio (Info.plist, AVAudioSession).

This mission is **kernel infrastructure work**, not feature work. Its success criterion is that Meeting Notes Handoff 1 can resume and complete with real audio data, real background recording, real entitlement checks, and a clean spoke contract.

## Execution Rules (Read First)

- Follow all rules in `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §0 Execution Rules and §2.1 Non-Negotiable Coding Rules.
- Terminology per `MISSION_BRIEF_RENAME_LIBRARIES.md` — "library" in user-facing copy, code-level names unchanged.
- Visual styling uses home screen design tokens per `MISSION_BRIEF_HOME_SCREEN_DESIGN.md` (minimal UI surface in this mission, but any shown UI follows tokens).
- Privacy model is inviolable. This mission touches the audio stack; no code introduced should transmit audio data off-device, log it to external services, or allow any cloud fallback path.
- Every change here affects every future spoke. Over-engineer defensively where the cost is low; push back on complexity that is speculative rather than required.
- **Stop and flag rather than guess** remains the standing rule. If you discover additional kernel gaps beyond the five listed, report them rather than silently expanding scope.

## Authority and Precedence

- **For sequencing:** this brief is authoritative.
- **For spoke contract design:** this brief's §1 supersedes `MISSION_BRIEF_MEETING_NOTES_SPOKE.md`'s SpokeModule definition. Meeting Notes will be updated to match the new contract after this mission.
- **For entitlement mechanism:** this brief's §2 supersedes `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §3.5 where any conflict exists (§3.5 described intent; this brief defines implementation).
- **For audio capabilities:** this brief's §3 extends the hub's audio service per `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §3.2.
- **For background recording:** this brief's §4 and §5 implement the infrastructure that `MEETING_NOTES_ADDENDUM_V2.md` §12 depends on. The addendum's user-facing behavior is not changed; this brief adds the platform capabilities that make it possible.

## Workstream 1: SpokeModule Contract Resolution

The current kernel contract (`lib/kernel/spoke_contract.dart`) treats spokes as stateless widget factories with fields `id`, `name`, `icon`, `buildUi`. The Mission Brief envisioned a richer lifecycle with `spokeId`, `metadata`, `initialize()`, `getRoute()`, `dispose()`.

**Decision: expand the kernel contract, but only with what real spokes actually need.** The brief's vision is closer to the right long-term design (initialization, disposal, metadata-driven routing), but some of its fields were speculative. This workstream adds what Meeting Notes genuinely requires and defers the rest.

### 1.1 New SpokeModule contract

The updated `SpokeModule` interface in `lib/kernel/spoke_contract.dart`:

```
abstract class SpokeModule {
  // Identity
  String get spokeId;              // stable ID, e.g. "com.kraken.meeting_notes"
  SpokeMetadata get metadata;      // display metadata (see below)

  // Lifecycle
  Future<void> initialize(KernelContext kernel);
  Future<void> dispose();

  // UI
  Widget buildUi(SpokeContext context);
}

class SpokeMetadata {
  final String displayName;        // "Meeting Notes"
  final String description;        // "Record, transcribe, summarize"
  final IconData icon;             // Flutter IconData or a custom icon reference
  final List<SpokePermission> requiredPermissions;
  final EntitlementTier tier;      // free or paid, per spoke
}

enum SpokePermission {
  microphone,
  camera,
  files,
  // extensible; add values as needed by real spokes
}

enum EntitlementTier {
  free,
  paid,
}
```

### 1.2 What was deferred from the original brief vision

- **`getRoute(RouteSettings settings)`**: not added. The current `buildUi` pattern works for Meeting Notes' needs. If a future spoke requires deep-link routing into specific internal screens, add routing then. Don't build what nothing uses.
- **Custom per-spoke navigation system**: same reasoning. Each spoke manages its own internal navigation within the widget tree rooted at `buildUi`. This is simpler and sufficient.

### 1.3 Migration path for existing spokes

Mock Spoke and Meeting Notes (from Handoff 1 work) must be updated to the new contract:

- Add `spokeId` (existing `id` field becomes `spokeId`; update all references).
- Add `metadata` object, moving `name` and `icon` into it and adding `description`, `requiredPermissions`, `tier`.
- Add `initialize(KernelContext)` — for Mock Spoke, this can be a no-op. For Meeting Notes, this is where the spoke subscribes to kernel services (audio, inference) and sets up its internal state.
- Add `dispose()` — releases any held resources. For stateless spokes, no-op is fine.

### 1.4 KernelContext

The `initialize` method receives a `KernelContext` — a dependency-injection surface the spoke uses to access kernel services. Define this alongside `SpokeModule`:

```
abstract class KernelContext {
  AudioService get audio;
  InferenceService get inference;
  VaultService get vault;
  WorkspaceService get workspace;
  ExportService get export;
  SearchIndex get search;
  VoiceInputService get voiceInput;
  EntitlementService get entitlement;   // new, per §2
  AuditLog get audit;
}
```

Spokes must only access kernel services through `KernelContext`. Direct imports of kernel service implementations from spoke code are forbidden (already a rule in the Hub Implementation Plan; this makes it enforceable).

### 1.5 Tests for Workstream 1

- Unit test: a stub `SpokeModule` can be registered, initialized, UI rendered, and disposed without errors.
- Unit test: attempting to access a kernel service not provided by `KernelContext` fails at compile time, not runtime.
- Integration test: Mock Spoke and Meeting Notes both load and render using the new contract.

---

## Workstream 2: EntitlementService Implementation

The Hub Implementation Plan §3.5 specified an entitlement service; the actual implementation is absent. This workstream builds the real service with both production (platform purchase records) and development (JSON file) entitlement sources.

### 2.1 EntitlementService interface

In `lib/kernel/entitlement_service.dart`:

```
abstract class EntitlementService {
  // Synchronous check for current entitlement state.
  bool isUnlocked(String spokeId);

  // Returns the current tier for a given spoke.
  EntitlementTier currentTier(String spokeId);

  // Streams entitlement changes (e.g., after purchase restoration).
  Stream<EntitlementChangeEvent> get changes;

  // Triggers a sync with the platform purchase store.
  // Called automatically on app launch; can be invoked manually from "Restore purchases" UI.
  Future<void> syncFromPlatform();
}

class EntitlementChangeEvent {
  final String spokeId;
  final EntitlementTier oldTier;
  final EntitlementTier newTier;
  final EntitlementSource source;  // platform, dev, manual
}
```

### 2.2 Entitlement sources, in priority order

1. **Platform purchase records** (iOS StoreKit, Android Play Billing) — the authoritative source in production. Queried on app launch and stored in memory for fast access.
2. **Development entitlements file** (`assets/entitlements.dev.json`) — used only when the app is running in a dev build (`kDebugMode` is true, or an explicit `--dart-define=KRAKEN_DEV=true` flag is set). Ignored in release builds regardless of presence.
3. **No entitlement** — default. Free-tier spokes always accessible; paid-tier spokes locked.

The entitlement service merges these sources with platform records taking precedence over dev file entries.

### 2.3 entitlements.dev.json format

Create `assets/entitlements.dev.json` with this schema:

```json
{
  "$schema": "Kraken development entitlements — local testing only, never shipped",
  "description": "This file grants paid-tier access to spokes during development. It is ignored in release builds.",
  "unlocked_spokes": [
    "com.kraken.meeting_notes",
    "com.kraken.documents",
    "com.kraken.quick_capture"
  ]
}
```

Register the file in `pubspec.yaml` under `flutter > assets`.

In release builds, the asset is either absent (preferred) or ignored. Implement a release-mode guard that refuses to read the file even if it exists in the bundle.

### 2.4 Platform integration stubs

The full StoreKit and Play Billing integrations are specified in `MISSION_BRIEF_RECOVERY_AND_RESTORATION.md` §6. This workstream implements the **kernel-side scaffold** that those integrations plug into:

- A platform channel for purchase queries (`kraken.kernel/entitlement`).
- Dart-side method handlers for: `queryPurchases`, `restorePurchases`, `getCurrentEntitlements`.
- Native implementations can be stubbed for this mission — returning empty results is acceptable. The real StoreKit and Play Billing integration happens in the recovery/restoration mission.

The point of this workstream is to have the service's **interface** ready so Meeting Notes (and future spokes) can query it with confidence. Native implementations follow.

### 2.5 Tests for Workstream 2

- Unit test: dev entitlements file is read correctly in debug mode, ignored in release mode.
- Unit test: `isUnlocked` returns correct values for entries present / absent / free-tier spokes.
- Unit test: platform entitlements override dev entitlements when both are present.
- Integration test: a spoke registered as paid-tier is locked by default and unlocked when its ID appears in the dev file (in debug mode).

---

## Workstream 3: Audio Amplitude EventChannel

The audio engine currently captures audio but doesn't expose live amplitude values to Dart. The Meeting Notes waveform is currently stub-driven by randomized data. This workstream adds a real amplitude stream.

### 3.1 Native implementation

On both iOS and Android, the native audio capture path must sample amplitude values continuously and emit them to Dart via an `EventChannel`.

**Channel name:** `kraken.kernel/audio/amplitude`

**Emission rate:** approximately 30 Hz (once every ~33ms). This is fast enough for smooth waveform animation without overwhelming the channel.

**Event payload:** a single double value representing peak amplitude in dBFS (decibels relative to full scale). Range: approximately -90 dBFS (silence) to 0 dBFS (clipping).

**iOS:** hook into the `AVAudioRecorder`'s metering. Call `updateMeters()` at the sampling rate, then `averagePower(forChannel: 0)` to get a dBFS reading. Emit via `FlutterEventChannel`.

**Android:** use `MediaRecorder.getMaxAmplitude()` polled at the sampling rate. The raw value is a 0–32767 integer; convert to dBFS via `20 * log10(amplitude / 32767.0)`. Emit via `EventChannel`.

### 3.2 Dart-side consumer

In `lib/kernel/audio_service.dart`, expose:

```
Stream<double> get amplitudeStream;  // live dBFS values during recording
```

Stream is active only while recording. Before `startRecording` and after `stopRecording`, the stream produces no values. Pause/resume (workstream 3.4) pauses the stream during pause.

### 3.3 Wiring to Meeting Notes waveform

Update the Meeting Notes recording screen (from Handoff 1 work) to subscribe to `amplitudeStream` and drive the waveform from real values instead of the current mock data.

The color thresholds established in `MEETING_NOTES_ADDENDUM_V2.md` §1.2 (white below ~-30 dBFS, accent in healthy range, red above ~-3 dBFS) map directly to the dBFS values coming from this stream. Starting thresholds as documented; tune during device testing.

### 3.4 Pause/resume methods

While we're in the native audio module, add the missing pause/resume capability.

**Channel methods added to `kraken.kernel/audio`:**

- `pauseRecording` — pauses audio capture, keeps the file open for append on resume.
- `resumeRecording` — resumes capture, appending to the existing file.

**iOS:** `AVAudioRecorder` supports `pause()` and `record()` (the same method used to start) directly. Implementation is straightforward.

**Android:** `MediaRecorder` gained `pause()` and `resume()` methods in API 24 (Android 7.0). Since the app targets Android 7+, this is available.

**Dart-side:** expose `pauseRecording()` and `resumeRecording()` on `AudioService`.

### 3.5 Tests for Workstream 3

- Unit test: `amplitudeStream` emits at approximately 30 Hz during recording.
- Unit test: values emitted are within the -90 to 0 dBFS range.
- Unit test: stream is silent before recording starts, after stop, and during pause.
- Integration test: start recording with a known audio source (tone generator at a specific dBFS); verify the stream reports values within tolerance of the expected dBFS.
- Integration test: pause and resume produce a single continuous audio file with a clean boundary at the pause point.

---

## Workstream 4: Android Foreground Service for Background Recording

Android 14+ requires a foreground service with the `microphone` type for sustained background microphone access. Without this, the OS kills recording within minutes of the app backgrounding.

### 4.1 Service implementation

Create `android/app/src/main/kotlin/.../KrakenRecordingService.kt`:

- Extends `Service`
- Declares itself as a foreground service of type `microphone` (Android 14+ requirement)
- Holds the active `MediaRecorder` instance while recording
- Manages the persistent notification (§4.3)
- Released when recording stops

### 4.2 Manifest changes

In `android/app/src/main/AndroidManifest.xml`:

- Add permission: `<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />`
- Add permission: `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />`
- Add permission: `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` (required on Android 13+ for notifications)
- Add permission: `<uses-permission android:name="android.permission.RECORD_AUDIO" />` (likely already present)
- Register the service:
  ```xml
  <service
      android:name=".KrakenRecordingService"
      android:foregroundServiceType="microphone"
      android:exported="false" />
  ```

### 4.3 Persistent notification

The foreground service displays a persistent notification while recording. Specification per `MEETING_NOTES_ADDENDUM_V2.md` §12.2:

- **Title:** "Kraken — Recording"
- **Text:** "Started [relative time]. Tap to view."
- **Icon:** A small Kraken mark variant. Create at `android/app/src/main/res/drawable/ic_notification_kraken.xml` as a vector drawable; the Kraken mark SVG established in `MISSION_BRIEF_HOME_SCREEN_DESIGN.md` §2 can be adapted.
- **Priority:** default (persistent but not intrusive).
- **Actions:** primary "Stop" button. Pause is nice-to-have and deferred.
- **Tap behavior:** launches the app to the active recording screen (MainActivity with a deep-link intent parameter).
- **Non-dismissible while recording.** Cleared when recording stops.
- **Notification channel:** create a dedicated channel `kraken_recording` with `IMPORTANCE_DEFAULT` and user-visible name "Recording Status."

### 4.4 Integration with audio capture

The current audio recording path in `MainActivity.kt` (or wherever it lives) must be moved to the foreground service. When `startRecording` is invoked from Dart:

1. Start the foreground service.
2. Service acquires `MediaRecorder`, begins recording.
3. Service emits amplitude events (§3.1) and accepts pause/resume/stop commands.
4. On stop: release `MediaRecorder`, dismiss notification, stop service.

The Dart-facing `MethodChannel` for audio operations stays the same; implementation moves from the activity to the service.

### 4.5 Stop action handling

The notification's "Stop" button posts an intent to the service. The service must:

1. Stop the active `MediaRecorder` cleanly (flush, finalize file).
2. Emit a stop event back to Dart so Meeting Notes can update its state.
3. Dismiss the notification, stop the service.

Tapping Stop from the notification is an explicit user action. No confirmation dialog.

### 4.6 Tests for Workstream 4

- Unit test: service starts and stops cleanly when commanded.
- Integration test: start recording, lock screen, wait 2 minutes, unlock — recording continues and the audio file contains the full 2 minutes.
- Integration test: start recording, switch to another app, wait 5 minutes, return to Kraken — recording continues, notification was visible throughout.
- Integration test: tap Stop from notification while app is backgrounded — recording ends, app opens to the completed recording on next launch.
- Device testing: verify on at least one Pixel device and one Samsung device. Samsung's aggressive battery management may require additional handling (documented as a should-have, not a must-have).

---

## Workstream 5: iOS Background Audio Configuration

iOS requires explicit declaration of the `audio` background mode and proper `AVAudioSession` configuration for sustained background recording.

### 5.1 Info.plist changes

In `ios/Runner/Info.plist`, add:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Also verify microphone usage description is present (required since iOS 10):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Kraken records audio for meetings. Audio stays on your device — nothing is sent anywhere.</string>
```

### 5.2 AppDelegate.swift audio session configuration

In `ios/Runner/AppDelegate.swift`, configure the `AVAudioSession` at app launch:

```swift
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure audio session for recording + background capability.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)
    } catch {
      // Log but don't crash. Recording will fail if session isn't configured,
      // but the app itself should still launch.
      NSLog("Failed to configure AVAudioSession: \\(error)")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

Note: `.playAndRecord` rather than `.record` because Meeting Notes will eventually play back recorded audio (future handoff); using the combined category avoids having to switch sessions. `.defaultToSpeaker` ensures playback uses the loudspeaker rather than the earpiece. `.allowBluetooth` permits AirPods or Bluetooth headsets as recording input.

### 5.3 Audio session interruption handling

Register for `AVAudioSession.interruptionNotification` to handle phone calls, Siri, and other interruptions. The handler emits interruption events to Dart so Meeting Notes can pause/resume per `MEETING_NOTES_ADDENDUM_V2.md` §12.3.

This is the should-have tier per §12.0 priority rules. Implement the notification registration and event channel in this mission so Meeting Notes can hook into it, but full auto-pause/resume UI behavior in Meeting Notes is a Handoff 1.5 follow-up.

### 5.4 Persistent notification on iOS

iOS's OS-provided red-pill status indicator is automatic — no implementation needed. Additionally, Meeting Notes should post a `UNNotificationRequest` showing "Kraken — Recording" with a Stop action button. The infrastructure for this (the notification category and action handling) belongs in the kernel so any spoke can use it.

Add to the kernel a `RecordingNotificationService`:

```
abstract class RecordingNotificationService {
  Future<void> showRecording({required String spokeName, required DateTime startedAt});
  Future<void> updateElapsedTime();
  Future<void> dismiss();
  Stream<RecordingNotificationAction> get actionStream;  // emits Stop when user taps Stop
}

enum RecordingNotificationAction { stop, pause, resume, tap }
```

On iOS, implemented via `UNUserNotificationCenter`. On Android, it's the foreground service notification from Workstream 4. Same Dart interface, different platform implementations.

### 5.5 Tests for Workstream 5

- Manual verification: `Info.plist` contains `UIBackgroundModes` with `audio`.
- Manual verification: `NSMicrophoneUsageDescription` is present and reads correctly.
- Integration test: start recording on iOS device, lock screen, wait 2 minutes, unlock — recording continues.
- Integration test: start recording on iOS device, switch to another app, wait 5 minutes, return — recording continues, red-pill indicator was visible.
- Integration test: phone call during recording triggers interruption event emitted to Dart.

---

## Cross-Workstream Integration

After the five workstreams complete, verify end-to-end:

1. **Spoke contract migration:** Mock Spoke and Meeting Notes load and render using the new `SpokeModule` contract with no errors.
2. **Entitlement-aware routing:** a paid-tier spoke registered in `entitlements.dev.json` is accessible; one not listed is locked.
3. **Real amplitude stream:** Meeting Notes recording screen's waveform responds to actual microphone input, with color states triggering correctly as the user speaks at different volumes.
4. **Background recording — Android:** lock screen during recording, recording continues, notification visible and functional.
5. **Background recording — iOS:** lock screen during recording, recording continues, red-pill indicator visible, Kraken notification functional.
6. **Pause/resume:** pause during recording, resume, single continuous audio file with clean boundary.

## Priority Tiers

Not all of this has to ship in a single pass, but some of it must. Tiers:

**Must-have (block Meeting Notes Handoff 1 resumption):**
- Workstream 1 fully (spoke contract must be stable before any other work continues)
- Workstream 2 minimum: EntitlementService interface and dev JSON mechanism. Platform integration stubs can return empty results for now.
- Workstream 3 §3.1–3.3 (amplitude stream) and §3.4 (pause/resume)
- Workstream 4 fully (Android foreground service)
- Workstream 5 §5.1–5.2 (Info.plist and AVAudioSession basic config)

**Should-have (ship in this mission if time permits; otherwise fast-follow):**
- Workstream 5 §5.3 (interruption handling)
- Workstream 5 §5.4 (RecordingNotificationService full implementation on iOS)

**Nice-to-have (v1.1 or later):**
- Samsung/Xiaomi-specific battery optimization workarounds on Android
- Pause action on recording notification (stop action is must-have)

## Hard Constraints

Do not:

- Introduce any code that transmits audio data off-device or logs it to external services.
- Implement StoreKit or Play Billing integrations in this mission — they're specified in `MISSION_BRIEF_RECOVERY_AND_RESTORATION.md` and belong to that mission. This mission builds only the kernel-side interface and stub implementations.
- Break Mock Spoke while migrating it to the new contract. Mock Spoke is still needed for regression testing.
- Silently adopt a divergent pattern if you discover the codebase has drifted further than this brief anticipates. Stop and flag.
- Expand scope beyond the five listed blockers without approval. If you find a sixth gap, report it rather than fixing it.

## Required Output at Mission End

Provide:

1. **Phase Completion Checklist** covering each workstream.
2. **What was built** — per workstream, with specific files changed or added.
3. **What was intentionally deferred** — any should-have or nice-to-have work not completed.
4. **Tests run** — unit, integration, device testing.
5. **Known risks / incomplete items**.
6. **Any additional kernel gaps discovered** — even if not fixed, flag them.
7. **Confirmation that Mock Spoke still works** after the contract migration.
8. **Real-device verification status** — iOS and Android background recording verified on which specific devices, at which OS versions.
9. **Whether Meeting Notes Handoff 1 can now resume cleanly** — your honest assessment, not a checkbox tick.

## Return Path to Meeting Notes

After this mission completes and real-device verification passes, return to Meeting Notes Handoff 1. The work already done in Handoff 1 (recording UI, state machine, session markers, transcription view, speaker labeling) stays. The remaining work becomes:

- Migrate `MeetingNotesSpoke` to the new SpokeModule contract.
- Wire the waveform to `amplitudeStream` instead of mock data.
- Wire pause/resume UI to the new native methods.
- Remove the hardcoded `_isFreeTier = true` and query the EntitlementService instead.
- Verify background recording works on real devices for both platforms.
- Verify the 5-hour safety cap and warning ladders fire correctly under real conditions.

Then Handoff 1 is genuinely complete and ready for human review before advancing to Handoff 2.
