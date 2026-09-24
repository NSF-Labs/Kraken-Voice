# Krak-EN Voice — Agent Brief (v5, FINAL)

A standalone, on-device voice & meeting recorder with diarization, AI summary, AI chat, and exports. Built by lifting the Kraken Hub kernel + meeting_notes spoke and dropping the hub-and-spoke abstraction.

## Product positioning

**Private meeting intelligence that stays on your device.** Not a recorder. Not a transcription app. A private, local-first meeting memory app.

## Core privacy rule (non-negotiable)

**No audio, transcript, summary, chat history, embeddings, speaker labels, tags, or calendar-linked metadata leaves the device unless the user explicitly exports or shares them.** This is both the marketing promise and a hard engineering constraint. No analytics, no telemetry, no cloud sync, no "anonymous" model improvement, no error reporting that includes user content. Crash reports are local-only. This rule forecloses any future "convenience" cloud feature without an explicit product decision and user opt-in.

**All decisions locked. No open questions remain.**

- Workspaces removed entirely. Folders only.
- Per-recording folder structure on disk under `Past Recordings/`. SQLCipher remains source of truth for metadata.
- Paid tier: free capped at 20 min; paid unlocks **unlimited duration**, **custom export branding**, and **export content toggles** (timestamps / speaker names / summary / action items on/off). Cross-recording AI chat stays free — it's the killer feature.
- AI chat bar on dashboard. Search icon on left, **Saved Chats icon on right**. Chat mode has full read access across all recordings, transcripts, summaries, titles, tags. Retrieval uses keyword search + top-N snippet injection in v1; embedding-based retrieval is v2 (§Appendix A).
- Calendar via `device_calendar` only. No OAuth. Manual link/unlink available per recording.
- Tap record stays on dashboard. No separate fullscreen recording screen.
- Free-tier countdown always visible during recording (combined with the main timer).
- **Microphone input device selection** — built-in, Bluetooth, wired, or USB.
- No migration of dev recordings — clean DB start.
- Existing test/benchmark/quality screens preserved for reference under `lib/screens/dev/`.
- **Recording reliability is a first-class concern** (§12). Persist state, recover from crashes, handle phone calls and BT disconnects gracefully.
- **Model readiness is gated** (§13). User cannot record if a recording-blocking precondition fails; a banner appears if a transcription model is missing.
- **Job queue is formal and visible** (§14). Each recording has a status; failures show retry buttons.

---

## 1. What to keep, what to drop

### Keep (lift directly from `kraken_hub/lib/`)

**`kernel/`** — entire directory, minus parts noted below:
- `audio/` — `AudioEngine` (MethodChannel `kraken.kernel/audio`, amplitude EventChannel, recording state, duration timer, notification stop/pause hooks, stale-state cleanup), `NemoDiarizer`, `Diarizer` interface, `EmbeddingCache`, `WhisperSegment`, `transcription_engine.dart`, `permission_helper.dart`, `share_intent_handler.dart`
- `auth/` — `AuthBloc`, `SecureKeyStore`, `KeyDerivation`
- `vault/` — `VaultService` (SQLCipher), `PreferencesService`
- `inference/` — `LocalInferenceService` (Gemma) with `generate(prompt, maxTokens) → Stream<String>`. Reuse for summaries AND chat bar.
- `voice_input/` — `VoiceInputService`, `FasterWhisperVoiceInput`, `VoiceInputBloc`
- `retention/` — `RetentionService`
- `entitlements/` — `EntitlementService` and `EntitlementServiceImpl`. Preserve free/paid logic. The 20-min timer at `recording_screen.dart` lines 221–228 reads `_isFreeTier` from this — preserve that read path.
- `notifications/` — `KrakenNotificationService`
- `context/kernel_context.dart` — keep, drop `workspace` field

**`spokes/meeting_notes/data/`** — three files lifted and renamed:
- `folder_repository.dart` → `lib/data/recording_repository.dart`
- `kraken_export_service.dart` → `lib/data/export_service.dart`
- `summary_prompt.dart` → `lib/data/summary_prompt.dart`

**Models:** `recording_session.dart` → `lib/models/recording_session.dart`

### Drop entirely
- `kernel/spoke_contract.dart`
- `kernel/spoke_registry/`
- `kernel/workspaces/`
- `spokes/mock/`
- `spokes/meeting_notes/meeting_notes_spoke.dart`
- `shell/ui/shell_layout.dart`, `kraken_shell_frame.dart`, `dashboard_screen.dart` (hub version), `activity_panel.dart`, `activity_screen.dart`, `library_picker_sheet.dart`, `workspace_detail_screen.dart`, `kraken_search_delegate.dart`
- `spokes/meeting_notes/ui/meeting_notes_main_screen.dart`

### Keep, reworked from `shell/`
- `shell/design/tokens.dart`, `kraken_mark.dart` → `lib/design/`
- `shell/onboarding/welcome_screen.dart`, `secure_screen.dart`, `download_screen.dart`, `overview_screen.dart` → `lib/screens/onboarding/`. Drop `demo_screen.dart` if hub-marketing.
- `shell/inference/model_manager.dart` → `lib/inference/model_manager.dart`
- `shell/home/unlock_screen.dart` → `lib/screens/unlock_screen.dart`
- `shell/app/app_lifecycle_bloc.dart` → `lib/app/app_lifecycle_bloc.dart`
- `shell/router/app_router.dart` → rewrite (§4)
- `shell/ui/splash_screen.dart` → `lib/screens/splash_screen.dart`
- `shell/ui/settings_screen.dart` + `meeting_notes_settings_screen.dart` → merged (§5)
- `shell/ui/model_downloader_screen.dart` → `lib/screens/model_downloader_screen.dart`

### Lift and rework from `spokes/meeting_notes/ui/`
- `recording_screen.dart` → mostly obsolete (no fullscreen recording). **Salvage:** 20-min free-tier limit (lines 221–228), 5-hour safety limit (lines 215–219), warning/upgrade modals, amplitude/waveform visualizer, transcription handoff `engine.queueJobWithDefaultLanguage(vault, audioPath)` (line ~499). Move into dashboard + `widgets/recording_controls.dart` + `widgets/amplitude_visualizer.dart`.
- `transcript_screen.dart` → `lib/screens/recording_detail_screen.dart`
- `folder_detail_screen.dart` → `lib/screens/files_screen.dart`
- `recording_state_chip.dart` → `lib/widgets/`

### Test / benchmark / quality artifacts → preserve under `lib/screens/dev/`
Per user direction, all prior testing scaffolding stays for reference:
- `action_items_screen.dart` → `lib/screens/dev/action_items_screen.dart`
- `language_benchmark_screen.dart` → `lib/screens/dev/language_benchmark_screen.dart`
- `summary_quality_test_screen.dart` → `lib/screens/dev/summary_quality_test_screen.dart`

Plus: search the original Kraken Hub repo (outside the lib/ archive examined here) for any `integration_test/` or `test/` directories with diarization regression tests, sike tests, or quality benchmarks — copy them over verbatim into `krak_en_voice/integration_test/` and `krak_en_voice/test/` as reference. Don't try to make them run on day one; they're reference material.

Access dev screens via Settings → Developer (gated behind `kDebugMode` OR a 7-tap easter egg on the version number in About).

---

## 2. Per-recording folder layout on disk

Each recording owns a folder. SQLCipher remains source of truth for metadata; the folder is the file home.

```
<app_documents>/
└── Past Recordings/
    ├── <recording_id>/
    │   ├── audio.m4a                  # original audio (or .wav per AudioEngine output)
    │   ├── transcript.json            # whisper segments + speaker labels
    │   ├── summary.json               # AI summary + version history
    │   ├── diarization.json           # raw + merged diarization segments
    │   └── exports/
    │       ├── <safe_title>_<timestamp>.pdf
    │       ├── <safe_title>_<timestamp>.docx
    │       └── ...
    └── <recording_id>/
        └── ...
```

**Implementation:**
- Add `folder_path TEXT NOT NULL` column to `recordings` table. Populate as `<docs>/Past Recordings/<recording_id>` on insert.
- **No migration of existing dev recordings** — clean DB start. New schema applies from first install.
- All file writes (export, transcript persistence, summary versioning) use the recording's `folder_path` rather than a global temp dir.
- `KrakenExportService.exportPdf` / `exportDocx` currently write to a temp dir at line 392. Redirect to `<folder_path>/exports/`. Keep `cleanupTempExports()` for legacy temp leftovers.
- Files screen navigates: list of recordings → tap → recording detail screen with audio player, transcript, summary, AND `exports/` contents inline.
- Hard-delete (purgeRecording, §6) removes the entire `<recording_id>/` folder.
- Soft-delete leaves the folder intact; only the DB row is flagged.

**Logical folders (separate concept).** The existing `folders` table stays for grouping (e.g., "Client A," "Standups"). Each recording belongs to one logical folder via `folder_id`. Default `'unfiled'` folder preserved. Logical folders are metadata only — they do not change the on-disk per-recording structure.

---

## 3. Package rename
- `name: kraken_hub` → `name: krak_en_voice` in `pubspec.yaml`
- Find/replace `package:kraken_hub/` → `package:krak_en_voice/`
- Native MethodChannel `kraken.kernel/audio` — leave as-is.

---

## 4. Front-facing dashboard

The entire app's primary surface. No separate recording screen.

**App bar:** Kraken mark + "Krak-EN Voice" wordmark on the left. No right-side actions.

**Vertical stack:**

### Hero — pulsing red record button
- Centered, ~220–260dp diameter, circular, glassmorphic ring
- Microphone icon at center
- **Idle:** soft pulsing red glow, ~1.4s breathe via `AnimationController.repeat(reverse: true)`. Reads as "ready, waiting."
- **Recording:** brighter base, faster pulse driven by `AudioEngine.amplitudeStream`. Outer ring scale = base + (amplitude * gain). Real reactive pulse.
- **Paused:** static glow, pause-bar overlay, no animation
- **Tap behavior:**
  - Idle → start recording. Button morphs: icon swaps to stop square; small pause pill appears beside it.
  - Recording → stop, kicks off transcription via `engine.queueJobWithDefaultLanguage(vault, audioPath)`
- All recording controls live on this screen. Never push a new route.

### Timer + countdown (combined)
- Directly under button, monospaced, 32–40sp
- Bound to `audioEngine.recordingDuration`
- Format: `HH:MM:SS` past one hour, otherwise `MM:SS`
- **Free tier during recording:** display as `MM:SS / 20:00` from second 1, so the limit is always visible
- **Paid tier:** just `MM:SS` or `HH:MM:SS`. The 5-hour safety limit warning still triggers at 4:59 with the existing modal.
- At 19:45 (free tier) → existing `_showUpgradeModal()` from `recording_screen.dart`
- At 20:00 (free tier) → existing auto-stop with toast "Recording stopped at the 20-minute free limit. Your audio has been preserved."

### Model status banner (conditional, top of dashboard above hero)
If any required AI model is missing or unusable (see §13), a non-dismissible banner appears at the top of the dashboard before the record button:
- Yellow warning style if a recording-time model (Whisper) is missing — recording stays available but transcription will fail
- Red blocker style if recording itself is impossible (e.g., mic permission denied)
- Banner CTA: "Set up models" → opens model downloader screen
- Hidden once all required models are present

### Amplitude visualizer ("synthesizer")
- Lifted verbatim from `recording_screen.dart`, placed below the timer/countdown
- Bound to `audioEngine.amplitudeStream`
- Idle: flat baseline or slow placeholder sinewave so the area isn't empty

### Language + microphone row (compact, one row)
A single horizontal row below the visualizer with two pill buttons sharing the space evenly:
- **[ 🌐 English ▼ ]** — opens the Language bottom sheet. The sheet header has an "Auto-detect" toggle at the top; when ON, the pill button shows "Auto" and the language list dims. This consolidates what was previously two separate dashboard pills.
- **[ 🎤 Phone ▼ ]** — opens the Microphone bottom sheet (see §6). Shows the friendly name of the active input device.

Language list source: lift `whisperLanguageLabel` map from `meeting_notes_settings_screen.dart` lines 11–23 into `lib/data/whisper_languages.dart`. Persist selection via `PreferencesService` under key `transcription_language` (ISO code or `'auto'`). Persist mic selection under `selected_input_device_id`.

### AI chat bar (bottom of dashboard, above bottom nav)
**Layout, left to right:**
1. **🔍 Search icon** (left edge) — toggles bar into Search mode
2. **Text input field** (center, fills available width)
3. **💬 Saved Chats icon** (right edge, opposite the search icon) — opens saved chats sheet
4. **Send button** (rightmost, inside the input field) — appears when text is entered. While generating, swaps to a stop square.

**Mode behavior:**

**Search mode** (default, search icon active):
- User types query → searches across recording titles, transcripts, summaries, tags via `RecordingRepository` search method
- Results slide up in a sheet from the bar; tap result → recording detail screen

**Chat mode** (engaged when user starts typing without the search icon explicitly active, OR via a small mode-toggle inside the field — suggest a single 🔍/💬 toggle on the left edge that flips between modes):
- Free-form Q&A streaming from `LocalInferenceService.generate`
- Opens conversation sheet covering most of screen
- Token-by-token rendering into the active assistant bubble
- Stop-generation button while streaming
- **Full read access across the app:** the chat agent can pull from titles, transcripts, summaries, diarization, tags, and saved chats. Implementation: when user submits a chat message, run a parallel keyword search via the existing `searchRecordings` LIKE-based query (folder_repository.dart line 466) against the message. Top 3–5 matched snippets get injected as system context into the LLM prompt with their source recording's title and date prepended. Cap injected context at ~2k tokens to fit Gemma's window. The user's question goes through verbatim.
- **Citations in answers.** The system prompt instructs the model to cite source recordings inline (e.g., "In your March 12 client call, John mentioned..."). When the assistant message is rendered, the UI scans for recording titles/dates that match the injected context and turns them into tap-targets that navigate to that recording's detail screen.
- **Search quality caveat (v1).** The existing search is `LIKE %query%`, not FTS5 or embeddings. This works fine up to ~hundreds of recordings. At scale, retrieval gets noisy. See Appendix A for the v2 plan (FTS5 → embeddings).
- "Save chat" button in the conversation sheet header → writes to `chats` table (see saved chats spec below)

**Saved Chats button (right edge):**
- Opens a sheet/screen listing saved chats, newest first
- Each row: title (auto-generated from first user message or user-edited), timestamp, snippet of last message
- Tap row → reopen that conversation, can continue
- Swipe-to-delete per row, "Clear all" in header

### Bottom navigation (4 tabs, IndexedStack to preserve state)
- 🎙 **Record** — the dashboard
- 📁 **Files** — `files_screen.dart`. Groups by logical folder. Each row: title, duration, date, transcription status. Tap → recording detail with audio player, transcript, summary, exports list (drawn from `<folder_path>/exports/`).
- 🗑 **Trash** — `trash_screen.dart` (§6)
- ⚙️ **Settings** — `settings_screen.dart` (§5)

`AudioEngine` at app scope — recording continues across tab switches.

---

## 5. Settings screen (merged)

One scrollable screen, sectioned:

**Recording**
- Default language (same picker as dashboard)
- Auto-detect language by default (toggle)
- Detect silence / auto-pause (toggle, wired to existing `detectSilence` arg)

**Microphone**
- Default input device — same device picker as dashboard
- Prefer Bluetooth when available (toggle) — when on, automatically switches to a Bluetooth mic if one connects between recordings. When off, the explicitly chosen device wins regardless of what's connected.
- Show device disconnect notifications (toggle, default on) — controls the toast that appears when a Bluetooth mic drops mid-recording or between recordings
- Test microphone (button) — opens a small modal that shows live amplitude bars from the currently selected device for 5 seconds, so the user can confirm the right mic is picking up audio before a real recording

**Diarization**
- Enable speaker diarization (toggle)
- Sensitivity threshold (slider 0.4–0.9, default 0.7). Subtitle: "Lower if speakers are being merged. Higher if one speaker is being split."
- Manage speaker labels (→ existing UI in transcript screen)

**AI Summary**
- Enable summaries (toggle)
- Summary style (Concise / Detailed / Bullet points) — wires into `summary_prompt.dart`
- Re-run summary on edit (toggle)

**AI Chat**
- Default chat mode (Search / Chat)
- Allow chat to access recordings (toggle, default ON — disabling makes chat purely conversational with no recording context injection)
- Save chat history (toggle, default off — chats are ephemeral unless this is on AND user taps Save in the conversation sheet)
- Show citations in chat answers (toggle, default ON — controls whether the model is prompted to cite sources)
- Clear all saved chats (button, confirm)

**Branding & Export Customization** — 🔒 paid only
- Logo, header, footer, brand color picker — lift from `meeting_notes_settings_screen.dart` lines 38–67 verbatim
- **Export content toggles** (new):
  - Include AI summary (toggle, default on)
  - Include action items (toggle, default on)
  - Include speaker names (toggle, default on)
  - Include timestamps (toggle, default off)
  - Include raw transcript (toggle, default on)
- Free users see grayed-out section with "Unlock with paid" CTA → existing entitlement upgrade flow

**Speaker labels**
- Default labeling style ("Speaker 1, 2, 3" / "S1, S2, S3" / "Speaker A, B, C")
- "Edit speaker names" link → opens speaker management sheet (see §15)
- Apply renamed speakers to all future recordings of the same voice — **disabled in v1** (requires voice fingerprinting). Show as "Coming soon."

**Calendar**
- Auto-link recordings to calendar events (toggle, default off)
- "Use event title as recording title" (toggle, default on when auto-link is on)
- When on: at recording start, query `device_calendar` for events overlapping `now ± 15min`. One match → silent attach + use event title. Multiple → bottom sheet picker. None → no-op.
- Schema: `calendar_event_id TEXT NULL`, `calendar_event_title TEXT NULL` on `recordings`
- Permission requested on first toggle-on
- **Manual override per recording** (in Recording Detail screen, not Settings): "Linked event" row with three actions — Change linked event (opens event picker for events ±7 days), Unlink, Rename to event title. If no event linked, the row shows "Link to calendar event →"

**Storage & Retention**
- Default retention policy (90 day / Delete after transcription / Keep forever)
- Storage cap slider
- Manage trash → opens Trash tab

**Security**
- Change passphrase
- Biometric unlock (toggle, wired to `local_auth`)
- Auto-lock timeout

**About / Support**
- **Suggest a feature** — `mailto:` with prefilled subject + device-info body
- **Rate Krak-EN Voice** — `url_launcher` to Play Store / App Store. Placeholder URLs until store listings exist; show "Coming soon" toast if URL is placeholder.
- **Share app** — `share_plus` with download-link string (placeholder until store live)
- App version + build number (7-tap to unlock Developer section)
- Open source licenses (`showLicensePage`)

**Developer (debug-only or 7-tap easter egg)**
- Language benchmark, summary quality test, action items extractor

---

## 6. Microphone selection — native channel work

The current `AudioEngine` (Dart) only exposes `start/stop/pause/resume/transcribe/getDuration` over the `kraken.kernel/audio` MethodChannel. There is **no device enumeration or selection** today — the native side picks whatever the OS routes audio to. Adding a mic picker requires both Dart and native changes.

### Dart side — extend `AudioEngine`

Add to `lib/kernel/audio/audio_channel.dart`:

```dart
class AudioInputDevice {
  final String id;            // platform-specific stable identifier
  final String name;          // user-friendly name ("AirPods Pro", "USB Audio Device")
  final AudioInputType type;  // builtin / bluetooth / wired / usb / unknown
  final bool isDefault;       // OS-default device
  final bool isConnected;     // currently available

  const AudioInputDevice({...});
}

enum AudioInputType { builtin, bluetooth, wired, usb, unknown }

// New methods on AudioEngine:
Future<List<AudioInputDevice>> getAvailableInputDevices();
Future<void> setInputDevice(String deviceId);
Future<AudioInputDevice?> getCurrentInputDevice();

// New EventChannel for hot-plug events:
final EventChannel _devicesEventChannel =
    const EventChannel('kraken.kernel/audio/devices');
Stream<List<AudioInputDevice>> get inputDevicesStream;
```

The `inputDevicesStream` fires whenever the device list changes (Bluetooth pair/unpair, headset plug/unplug). The dashboard mic-picker bottom sheet listens to this stream so the list stays live.

`startRecording` now optionally accepts a `deviceId` parameter; if null, uses the persisted selection from `PreferencesService`, falling back to OS default.

### Android side (Kotlin)

Use `android.media.AudioManager` and `AudioDeviceInfo`:

- **Enumerate:** `audioManager.getDevices(GET_DEVICES_INPUTS)` → filter by `type` to map to `AudioInputType` (`TYPE_BUILTIN_MIC`, `TYPE_BLUETOOTH_SCO`, `TYPE_WIRED_HEADSET`, `TYPE_USB_DEVICE`, `TYPE_USB_HEADSET`)
- **Select:** call `setPreferredDevice(AudioDeviceInfo)` on the `MediaRecorder` (API 28+) **before** `start()`. Below API 28, fall back to `AudioManager.startBluetoothSco()` for BT, and accept that wired/USB selection isn't programmatically controllable.
- **Hot-plug:** register `AudioDeviceCallback` via `audioManager.registerAudioDeviceCallback()`. Push the updated device list through the new EventChannel.
- **Bluetooth permission:** add `BLUETOOTH_CONNECT` to `AndroidManifest.xml` (Android 12+). Request at runtime when user first opens the mic picker, not on app launch.

### iOS side (Swift)

Use `AVAudioSession`:

- **Enumerate:** `AVAudioSession.sharedInstance().availableInputs` returns `[AVAudioSessionPortDescription]`. Map `portType` to `AudioInputType` (`.builtInMic`, `.bluetoothHFP`, `.bluetoothA2DP`, `.headsetMic`, `.usbAudio`).
- **Select:** `try session.setPreferredInput(portDescription)` before activating the session.
- **Hot-plug:** observe `AVAudioSession.routeChangeNotification`. Push updates through the EventChannel.
- iOS doesn't require a runtime permission for input enumeration beyond the existing microphone permission.

### Constraints to flag in code comments

- **Mid-recording switch is not supported in v1.** Both `MediaRecorder` (Android) and the active recording session (iOS) require stop-and-restart to change input. Doing it transparently risks dropped audio or corrupted files. Brief decision: snackbar telling user the change applies to next recording.
- **Bluetooth SCO mic quality on Android is mono 8kHz** in many cases. This is fine for transcription (Whisper handles it) but a user expecting "studio quality from my AirPods" will be disappointed. Surface no warning; just let the recording happen. Document it in the Settings → Microphone section subtitle: "Bluetooth mics may use compressed audio. For best quality, wired or USB recommended."
- **USB-C / Lightning adapters** show up as `TYPE_USB_DEVICE` (Android) or `.usbAudio` (iOS). They work fine.

### Test plan
On user's primary test device (Galaxy S24 Ultra):
1. Built-in mic → record → confirm
2. Pair Bluetooth headset → switch via picker → record → confirm audio comes from BT mic
3. Unplug BT mid-recording → confirm graceful fallback toast and recording continues with whatever the OS routes to
4. Wired 3.5mm headset (via USB-C adapter) → confirm enumeration and selection
5. USB audio interface (e.g., a Scarlett or Rode interface) → confirm it shows up as USB type and can be selected for interview-quality recording

---

## 7. Trash (recoverable deletes)

Current `FolderRepository.deleteRecording` (line 426) is a hard delete. Must change.

**Schema** (migration in `RecordingRepository`):
- `deleted_at INTEGER NULL` — millisecondsSinceEpoch when trashed
- `delete_after INTEGER NULL` — auto-purge timestamp (deleted_at + 30 days)

**New methods on `RecordingRepository`:**
- `softDeleteRecording(String id)` — sets `deleted_at = now()`, `delete_after = now() + 30d`. Files and related rows untouched.
- `restoreRecording(String id)` — clears both fields.
- `purgeRecording(String id)` — what `deleteRecording` does today PLUS `rm -rf` the entire `<recording_id>/` folder from disk.
- `getTrashedRecordings()` — `SELECT * WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC`
- All existing read queries get `WHERE deleted_at IS NULL` appended

**Auto-purge sweep:** add to `RetentionService` — on app startup and once per day, call `purgeRecording` for any rows where `delete_after < now()`.

**Trash screen:**
- List view, newest-first
- Each row: title, original logical folder, "Deleted X days ago", "Auto-removes in N days"
- Per-row actions: Restore, Delete forever
- Top bar: "Empty trash" (confirm → purge all)

---

## 8. Calendar integration (`device_calendar` only)

- Add `device_calendar: ^4.x` to `pubspec.yaml`
- Permissions: Android `READ_CALENDAR`, iOS `NSCalendarsUsageDescription`
- First toggle-on in Settings → request permission via package
- On recording start (toggle on): query events overlapping `now ± 15min`
- One match → silent attach, default title to event title
- Multiple → bottom sheet picker
- None → no-op
- Store `calendar_event_id`, `calendar_event_title` on recording row

---

## 9. Bootstrap (`main.dart`) — new version

Existing `main.dart` (33–92) is mostly correct. Changes:
1. Drop `SpokeRegistryBloc` and `RegisterSpoke(MeetingNotesSpoke())` block
2. Drop `kraken_hub/spokes/...` imports
3. Drop `WorkspaceService` instantiation and `workspace` field from `KernelContext`
4. Rename `KrakenHubApp` → `KrakEnVoiceApp` (file `lib/app/app.dart`)
5. Keep everything else: audio engine, vault, inference, voice input, auth, retention, lifecycle, notifications, stale-state cleanup, secure key store

---

## 10. New `lib/` layout

```
lib/
├── main.dart
├── app/
│   ├── app.dart                          # KrakEnVoiceApp
│   └── app_lifecycle_bloc.dart
├── kernel/                               # lifted from kraken_hub, workspaces removed
│   ├── kernel.dart                       # barrel; spoke_contract & registry exports removed
│   ├── audio/
│   │   ├── audio_channel.dart            # extended with device enumeration + selection
│   │   ├── audio_input_device.dart       # NEW — AudioInputDevice model + enum
│   │   └── ... (other audio files)
│   ├── auth/
│   ├── vault/
│   ├── inference/
│   ├── voice_input/
│   ├── retention/
│   ├── entitlements/
│   ├── notifications/
│   └── context/kernel_context.dart       # workspace field dropped
├── data/
│   ├── recording_repository.dart         # was folder_repository.dart, with soft-delete + per-recording folder paths
│   ├── export_service.dart               # was kraken_export_service.dart, writes into per-recording exports/
│   ├── summary_prompt.dart
│   ├── chat_repository.dart              # NEW — saved chats table
│   └── whisper_languages.dart            # NEW — extracted language map
├── models/
│   └── recording_session.dart
├── design/
│   ├── tokens.dart
│   └── kraken_mark.dart
├── inference/
│   └── model_manager.dart
├── router/
│   └── app_router.dart
├── screens/
│   ├── splash_screen.dart
│   ├── unlock_screen.dart
│   ├── model_downloader_screen.dart
│   ├── onboarding/
│   │   ├── welcome_screen.dart
│   │   ├── secure_screen.dart
│   │   ├── download_screen.dart
│   │   └── overview_screen.dart
│   ├── dashboard_screen.dart             # NEW
│   ├── files_screen.dart                 # was folder_detail_screen.dart
│   ├── recording_detail_screen.dart      # was transcript_screen.dart
│   ├── trash_screen.dart                 # NEW
│   ├── settings_screen.dart              # merged
│   └── dev/                              # preserved test/benchmark scaffolding
│       ├── action_items_screen.dart
│       ├── language_benchmark_screen.dart
│       └── summary_quality_test_screen.dart
└── widgets/
    ├── pulsing_record_button.dart        # NEW — amplitude-driven pulse
    ├── recording_controls.dart           # NEW — pause/stop + 20-min countdown + 5-hour safety logic
    ├── amplitude_visualizer.dart         # lifted from recording_screen.dart
    ├── language_picker_sheet.dart        # NEW
    ├── microphone_picker_sheet.dart      # NEW — input device selection
    ├── ai_chat_bar.dart                  # NEW — search + chat dual mode, saved chats button
    ├── saved_chats_sheet.dart            # NEW — saved chat list with restore/delete
    └── recording_state_chip.dart
```

Plus, copy any existing `integration_test/` and `test/` directories from the original Kraken Hub repo to the new project root for reference.

---

## 11. Build order & MVP cut line

The full feature set is large. Ship in phases. **MVP must work end-to-end before any post-MVP work begins.**

### MVP (must ship)
1. **Scaffold** — new `krak_en_voice` Flutter project. Copy `pubspec.yaml`, change `name`, add `device_calendar` and `url_launcher`. Drop `receive_sharing_intent` unless share-in stays. Drop `archive` unless export uses it.
2. **Lift kernel** — copy `kernel/` directory. Fix imports. Remove `spoke_contract`, `spoke_registry`, `workspaces` from barrel.
3. **Lift data layer** — copy and rename three data files. Add `folder_path` column to recordings table. Update export service to write into `<folder_path>/exports/`. Add soft-delete columns.
4. **Lift design + onboarding + auth + unlock** — get app booting to unlock screen.
5. **Model readiness gating (§13)** — model status check on launch, banner on dashboard if any required model missing, gate Record button on minimum preconditions (mic permission + storage available).
6. **Build new dashboard** — `pulsing_record_button.dart`, `dashboard_screen.dart`, `amplitude_visualizer.dart`, `recording_controls.dart`. Wire AudioEngine, combined timer/countdown, 5-hour safety limit. Compact language+mic row (single row).
7. **Recording reliability (§12)** — state persistence, crash recovery on launch, phone call interruption, BT mid-recording disconnect handling. **This is MVP-critical.**
8. **Microphone selection (native + Dart, §6)** — Android `AudioManager` + `setPreferredDevice` + hot-plug callback. iOS `AVAudioSession.availableInputs` + `setPreferredInput` + route change observer. Dashboard pill + Settings section. Test on Galaxy S24 Ultra: built-in / Bluetooth / wired / USB.
9. **Job queue & status (§14)** — formalize transcription/diarization/summary state machine, surface status + retry buttons in Files screen.
10. **Bottom nav** — IndexedStack with Record / Files / Trash / Settings.
11. **Trash** — schema migration, update read queries with `WHERE deleted_at IS NULL`, build trash screen, wire purge sweep into `RetentionService`.
12. **Cross-recording AI chat** — keyword search via existing `searchRecordings`, top-N snippet injection, citations in answers. **This is MVP — it's the differentiator. Ship without saved chats; save feature is post-MVP.**
13. **Settings merge** — every section from §5 into one screen. Gate branding + export-content toggles behind `EntitlementService.isUnlocked`.
14. **Speaker label management (§15)** — rename Speaker 1/2/N flow on transcript screen. MVP-critical because diarization without rename is unusable for multi-speaker recordings.
15. **Basic export with paid content toggles** — paid users get logo/header/footer/color + per-export toggles for summary/action items/speaker names/timestamps/transcript.
16. **Suggest / Rate / Share** — URL launcher polish.

### Post-MVP (v1.1+)
- **Saved chats** — `chat_repository.dart`, save button in conversation sheet, saved chats sheet from right-side icon
- **Calendar auto-linking** — `device_calendar`, auto-link on recording start, manual override per recording in detail screen
- **Developer benchmark/quality screens** — preserve files in `lib/screens/dev/` from MVP, but don't surface in UI until v1.1
- **Export templates** — Meeting Notes / Sales Call / Interview / Sermon / Legal templates (the toggles in MVP are 80% of the value)
- **Voice fingerprinting** — "remember this voice" for cross-recording speaker identity

### v2 (deferred but planned, see Appendix A)
- **FTS5 search index** to replace `LIKE %query%`
- **Local embedding-based retrieval** for chat context
- **Live mid-recording mic switching** (requires recording engine architecture change)

---

## 12. Recording reliability & recovery

A recorder app that loses a 90-minute meeting is dead on arrival. This section is MVP-critical and non-negotiable.

### State persistence
- `RecordingSession` (already exists in `models/recording_session.dart` with `id`, `startTime`, `outputFilePath`, `lastFlushed`) is written to `PreferencesService` every **5 seconds** during active recording
- Native side flushes audio buffer to disk on the same cadence (Android `MediaRecorder` is already streaming to file; iOS requires explicit buffer flush in the session config)
- On every state change (start/pause/resume/stop), session is written immediately

### Crash recovery on launch
- App startup checks for an active `RecordingSession` in PreferencesService
- If found and the audio file exists at `outputFilePath`:
  - Show a recovery dialog: "We found an unfinished recording from [timestamp]. Duration: ~MM:SS. Recover?"
  - On Recover → finalize the partial audio file (transcode if needed via existing FFmpeg), insert into `recordings` table with status `recorded`, queue for transcription
  - On Discard → delete the partial file and clear the session
- If audio file is missing or zero-bytes → clear session silently

### Interruption handling
- **Incoming phone call:** AudioFocus loss on Android (`AUDIOFOCUS_LOSS_TRANSIENT`) / `AVAudioSession.interruptionNotification` on iOS → automatically pause recording, show toast "Recording paused: phone call." On focus regain → show "Resume recording?" snackbar with Resume button (manual, not automatic — user may have started a new call).
- **Bluetooth mic disconnect mid-recording:** detected via `AudioDeviceCallback` (Android) / `routeChangeNotification` (iOS). Behavior: continue recording with whatever mic the OS routes to (usually phone built-in). Show toast "Bluetooth mic disconnected, continuing with phone mic." Do NOT pause — losing audio mid-meeting because of a flaky BT connection is worse than degraded audio.
- **Another audio app starts recording** (e.g., user joins a Zoom call): on Android, our foreground service should hold mic; if mic is forcibly preempted, pause recording and show toast "Recording paused: another app is using the microphone." iOS handles this via interruption notification.
- **Low battery:** at 15% battery, show one-time toast "Low battery — your recording is being saved continuously." At 5%, force-stop with "Recording stopped: critical battery. Audio saved." Existing `audio.m4a` is already complete due to streaming.
- **OS kills the app:** Android foreground service with persistent notification (already exists per `AudioEngine` / `KrakenNotificationService`) prevents this in normal cases. If it happens anyway, crash recovery (above) handles the partial file.
- **User swipes app away:** foreground service keeps recording. The persistent notification has Stop and Pause actions (already wired via `onNotificationStop` / `onNotificationPause` in `AudioEngine`).

### Partial-file salvage
- All recordings stream to `<folder_path>/audio.m4a` from the start. Even if the app crashes, the file on disk is a valid (truncated) audio file thanks to `MediaRecorder` / iOS streaming behavior.
- `getDuration` MethodChannel call (already exists at line 142 of `audio_channel.dart`) computes from the file, not from in-memory state. Use this on recovery to determine actual recovered duration.

---

## 13. Local AI model management

The app cannot function without local models. This needs explicit gating.

### Required models
| Model | Purpose | Approx size | Required for |
|---|---|---|---|
| Whisper (ggml) | Transcription | ~150–500 MB depending on variant | Transcription (post-recording) |
| NeMo TitanNet Small | Diarization | ~30 MB | Speaker labeling (optional but on by default) |
| Sherpa segmentation model | Diarization preprocessing | ~10 MB | Diarization |
| Gemma (or equivalent) | Summaries + chat | ~1.5–4 GB | Summary generation, chat mode |

Existing `model_manager.dart` already handles downloads. Extend it with a `ModelStatusService` that exposes:

```dart
class ModelStatus {
  final bool whisperReady;
  final bool diarizationReady;
  final bool inferenceReady;     // Gemma
  final int totalDownloadedBytes;
  final int storageAvailableBytes;
  final List<String> missingRequired;     // user-facing names
}

Future<ModelStatus> checkAll();
Stream<ModelStatus> watch();           // for the dashboard banner
```

### Gating rules
- **Recording is ALLOWED if:** mic permission granted AND ≥500 MB free storage
- **Recording is BLOCKED with error if:** mic permission denied OR <100 MB free storage
- **Recording is ALLOWED with warning if:** Whisper model missing (recording saves; transcription deferred until model downloaded; banner stays visible)
- **Diarization is silently skipped if:** diarization model missing (recording + transcription proceed; recording detail screen shows "Speaker labels unavailable — download diarization model in Settings")
- **Chat / summary buttons are disabled if:** Gemma model missing (with inline "Download model" link)

### Storage estimate display
Settings → Storage shows: `Whisper: 244 MB · Diarization: 38 MB · Gemma: 2.1 GB · Total: 2.4 GB`

### Capability check (one-time, cached)
On first launch after install, run a 5-second Gemma inference test (`generate("Hello", maxTokens: 10)`). If it fails or takes >30 seconds, mark the device as "low-capability" in PreferencesService and:
- Default Summary style to "Concise"
- Disable real-time chat streaming UI affordances (still works, just no token-by-token render)
- Show a one-time info dialog explaining the device may be slow for AI tasks

### Battery / thermal
- Long inference jobs (transcribing a 90-min recording) check battery on start. If <30% AND not charging → show prompt: "This will take ~X minutes and may drain your battery significantly. Continue, or wait until charging?"
- iOS `ProcessInfo.thermalState` / Android `PowerManager` thermal listener: if device enters `severe`/`critical` thermal state, pause job queue, show banner "Processing paused: device is too hot. Will resume when cooler."

---

## 14. Job queue & processing status

Currently `transcription_jobs` and `summary_versions` tables exist but the state machine isn't formalized. Make it explicit and visible.

### Recording status state machine
```
recorded → transcribing → diarizing → summarizing → complete
                ↓             ↓            ↓
            tx_failed   diar_failed   sum_failed
                ↓             ↓            ↓
              (retry → back to source state)
```

Status values stored on `transcription_jobs` row (extend existing `status` column):
`recorded`, `queued`, `transcribing`, `transcribed`, `diarizing`, `diarized`, `summarizing`, `complete`, `tx_failed`, `diar_failed`, `sum_failed`, `cancelled`

Plus error detail columns: `error_code TEXT NULL`, `error_message TEXT NULL`, `failed_at INTEGER NULL`, `retry_count INTEGER DEFAULT 0`.

### Files screen status display
Each row shows status badge:
- 🔵 In progress (with current stage label: "Transcribing 45%")
- ✅ Complete
- ⚠️ Failed (with retry button)
- ⏸ Paused (queue paused due to thermal/battery)

Tapping a failed row opens a sheet with the error message and a "Retry" button. Retry resets `retry_count++`, clears error fields, re-enqueues at the failed stage (don't re-transcribe if only summary failed).

### Cancel
Long-running jobs can be cancelled. Add a cancel button to in-progress rows. Cancel sets status to `cancelled`, kills the inference isolate (`NemoDiarizer` already runs in a compute() isolate per the existing code), preserves the audio.

### Queue manager
Single-job-at-a-time on-device — running parallel Whisper + Gemma will cook the device. `JobQueueService` (new, in `lib/data/`) processes one job at a time, persists queue to SQLCipher so it survives app restarts, resumes on launch. Listens to thermal/battery state from §13.

---

## 15. Speaker label management

Diarization without easy renaming is unusable for multi-speaker meetings. Make this prominent.

### In recording detail screen
- Top of transcript: a chip row showing each detected speaker — `[Speaker 1: 8 segments] [Speaker 2: 14 segments] [Speaker 3: 3 segments]`
- Tap a chip → bottom sheet with text field "Rename Speaker 1 to..." → applies to ALL segments of that speaker in this recording
- Renamed names persist on the `speaker_labels` table (already exists)
- Inline rename also available — tap any speaker label in the transcript itself

### Cross-recording (deferred to post-MVP)
- Voice fingerprinting via TitanNet embeddings is theoretically possible (we already have the embedding extractor), but reliability across recording conditions (different mics, ambient noise) is poor without significant tuning. Mark as v2.
- v1.1 compromise: a "Frequent speakers" list in Settings where the user can predefine names ("Alex, Mom, Boss"). On a new recording, the rename UI offers these as quick-pick suggestions. No automatic identification.

### Export with speaker names
Already supported via the new export-content toggles in Settings. Default ON for paid; free tier exports always include speaker names (it's a standard feature, not a paid lever).

---

## 16. Saved chats data model

Concrete schema and rules so this isn't ambiguous.

### Table
```sql
CREATE TABLE chats (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,                  -- auto-generated from first user message, user-editable
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  recording_id TEXT NULL,               -- nullable FK; chat can be standalone or tied to a recording
  messages_json TEXT NOT NULL,          -- full conversation thread
  context_recording_ids TEXT NULL,      -- JSON array of recording IDs whose snippets were injected
  deleted_at INTEGER NULL,              -- soft delete, same pattern as recordings
  delete_after INTEGER NULL,
  FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE SET NULL
);
```

### Rules
- Stored in SQLCipher — encrypted at rest like everything else
- Included in global search (chat titles + message bodies are searchable from the chat bar's search mode)
- Exportable as Markdown or PDF — same export pipeline as recordings, simplified template
- Soft-delete with same 30-day trash recovery as recordings
- Hard-delete via "Delete forever" in trash purges the row
- A chat can be linked to a recording (`recording_id` set) — that recording's detail screen shows a "Related chats (N)" link
- Standalone chats (no `recording_id`) are accessed via the right-side Saved Chats icon on the dashboard
- "Save chat" button in the conversation sheet writes the current thread; subsequent messages in the same session update the existing row (continue editing)

---

## Appendix A: Future retrieval improvements (v2)

The MVP chat retrieval uses `LIKE %query%` against the existing `searchRecordings` query. Works fine to ~hundreds of recordings. Beyond that, retrieval gets noisy — common words match too much, semantically related content with different vocabulary doesn't match at all.

### v1.1 — FTS5 (cheap, big win)
- Migrate to SQLite FTS5 virtual table covering `title`, `transcription_text`, `summary_json`, `tag`
- Replace `LIKE` queries with `MATCH` queries — proper tokenization, BM25 ranking, snippet extraction
- ~1 week of work, no new model dependencies

### v2 — Local embeddings (the killer feature)
- Add a small on-device embedding model (e.g., `all-MiniLM-L6-v2` ONNX, ~80MB, runs on CPU comfortably)
- On transcription complete: chunk transcript into ~500-token windows with 100-token overlap, generate embeddings, store in a new `transcript_embeddings` table (`recording_id`, `chunk_text`, `chunk_start_ms`, `embedding BLOB`)
- On chat query: embed the query, top-K cosine similarity search via Dart-side computation (sqlite-vec extension is overkill for a personal device; brute-force cosine over <100K vectors is fast enough)
- Hybrid retrieval: combine FTS5 keyword scores with embedding similarity scores, return top-N
- Citations become much richer: "In your March 12 customer meeting, John said..." with actual semantic match, not just keyword match

### Why deferred
- Adds another model download (~80MB) and another inference step per recording
- Embedding computation on long transcripts is non-trivial (~30s per hour of audio on a Galaxy S24)
- v1's keyword approach is genuinely fine for the first hundreds of recordings
- Ship the product, see how people use chat, then invest in retrieval where it actually matters

---

## Appendix B: Files preserved for reference

Per user direction, these test/benchmark files from Kraken Hub are preserved in the new project for reference, gated behind dev mode:
- `lib/screens/dev/action_items_screen.dart`
- `lib/screens/dev/language_benchmark_screen.dart`
- `lib/screens/dev/summary_quality_test_screen.dart`

Plus, copy any `integration_test/` and `test/` directories from the original Kraken Hub repo to the new project root verbatim. Don't try to make them run on day one; they're reference.
