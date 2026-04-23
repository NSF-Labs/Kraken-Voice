# Mission Brief: Kraken Onboarding Flow and Home-Screen Privacy Affordances

## Objective

Build the first-launch onboarding experience and the persistent home-screen patterns that make Kraken's privacy-first story feel real to users rather than just claimed. This mission produces the first 60 seconds of the app and the small, persistent UI patterns that reinforce the story during daily use.

This work lives primarily in `/lib/shell/` (new `onboarding/` subdirectory and updates to `home/`, `settings/`). It consumes existing kernel services (`ModelAssetService`, `Authenticator`, `VaultService`, `LocalInferenceService`, `VoiceInputService`) but adds no new kernel services.

## Execution Rules (Read First)

- Follow all rules in `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §0 Execution Rules and §2.1 Non-Negotiable Coding Rules.
- This is a shell-only mission. No kernel service changes. If you find yourself wanting to modify a kernel service to support an onboarding feature, stop and flag it for review instead.
- Produce a Phase Completion Checklist at the end per the standing phase-gate rule.
- No signup, no account creation, no email collection, no remote analytics. The absence of these is the feature.
- No "rate us" prompts, no growth-hack popups, no mandatory feature tours on updates. Restraint is part of the product.
- All copy in this mission must be honest. If the app cannot do something, do not imply it can. If a limitation is real, name it.
- **Terminology:** user-facing strings use "Library" / "libraries" (per `MISSION_BRIEF_RENAME_LIBRARIES.md`) and "draft(s)" for AI-generated artifacts. Code-level names (`WorkspaceService`, `spoke_outputs`, etc.) remain unchanged. Capitalization is context-sensitive — capitalized for proper-noun uses and headings, lowercase for sentence-style body and action copy. See the rename brief for detailed rules.

## Phase 1: Onboarding Flow (Screens 1–5)

### 1.1 Screen 1 — Welcome

**Route:** `/onboarding/welcome` (first-launch only; detected via vault-not-yet-initialized state).

**Layout:** Full-screen, minimal. Centered vertically.

**Content:**
- Kraken logo (vector asset — kraken motif with central head representing the kernel and tentacles representing spokes; keep the shape simple and recognizable at small sizes).
- Headline (H1): **"AI that works entirely on your device."**
- Body (single line): "No cloud. No accounts. No uploads. Your data stays yours."
- Primary button: **"Get started"**

**Behavior:**
- No text fields on this screen.
- No links to terms of service or privacy policy in the body (those live in a small footer link; onboarding does not gate on them).
- Tapping "Get started" advances to `/onboarding/overview`.

### 1.2 Screen 2 — What You Get (Overview)

**Route:** `/onboarding/overview`.

**Layout:** Three cards stacked vertically on mobile, centered. Minimal iconography; each card has one line.

**Content:**
- Card 1: **Meeting notes** — "Record, transcribe, and summarize meetings. Up to 20 minutes free."
- Card 2: **Document summaries** — "Photos, PDFs, and docs become searchable, summarized, and organized."
- Card 3: **Quick capture** — "Dictate or type a thought; Kraken routes it where it belongs."
- Quiet subline below cards: "Expand with optional tools when you need them. No subscription."
- Primary button: **"Set up Kraken"**

**Behavior:**
- Cards are display-only; no interaction.
- Tapping "Set up Kraken" advances to `/onboarding/download`.

### 1.3 Screen 3 — Model Download (the Privacy Moment)

**Route:** `/onboarding/download`.

**Important context:** The model download infrastructure already exists in the kernel. The 1.5 GB Gemma 4 E2B model can be downloaded once and persists on device. This onboarding screen is a UI layer over the existing download service — it displays progress and messaging. Do not reimplement download logic, resumable transfer, checksum verification, or storage management. Consume the existing service.

**Two possible states on first reach:**

**State A — Model not yet downloaded (fresh install, user has not yet triggered download):**

Display the pre-download UI and initiate the existing download service on user consent.

- Headline: **"Kraken needs to download its AI engine."**
- Body paragraph 1: "About 1.5 GB, one time. After this, Kraken's core AI works offline."
- Body paragraph 2: "The AI engine runs on your device. Your meetings, notes, and documents never leave."
- Body paragraph 3 (only if on cellular): "Downloads work best on Wi-Fi."
- Primary button: **"Download now"**
- Secondary button (only on cellular): **"Wait for Wi-Fi"** (returns user to background; app resumes download when Wi-Fi detected and user reopens).

**State B — Model already present and verified (user is re-completing onboarding, or download happened earlier):**

Skip this screen entirely. Advance directly to `/onboarding/secure`. Do not show "model already downloaded" messaging — users don't need to be told something that is working is working.

**Content during download (State A active):**

- Large progress bar with: percentage, bytes downloaded / bytes total, current download speed, estimated time remaining. These values come from the existing download service's progress stream; do not recalculate.
- Below the progress bar, a single line of rotating honest facts (change every ~6 seconds):
  - "The AI engine is Gemma 4 E2B, from Google DeepMind."
  - "After download, no internet is required for core features."
  - "Kraken cannot read your files on any server — because there is no server."
  - "Audit logs track every AI operation locally."
  - "Your vault is encrypted with keys that never leave this device."
- Do not include promotional or marketing copy in this rotation. Only verifiable facts.

**Content after download completes (model verified and warming):**

- Progress bar replaced by a simple "Preparing your AI engine..." with a subtle spinner.
- Once `LocalInferenceService` reports `Warm` state, automatically advance to `/onboarding/secure`.

**Behavior:**

- The onboarding screen subscribes to the existing download service's progress stream and the `LocalInferenceService` state machine. It does not own download state.
- If download fails (network loss, insufficient storage, checksum mismatch), display the appropriate error message from the service and a "Retry" button that re-invokes the service. Error messaging is human-readable, not raw error codes.
- If the user backgrounds the app during download, the existing download service handles resumable transfer. Re-opening the app returns to this screen with progress restored from the service's current state.
- User cannot skip this screen in State A. The app is not functional without the model.
- Exit criterion: verify both State A (fresh install) and State B (model already present) paths behave correctly. A user whose model is already downloaded should never see the download UI.

### 1.4 Screen 4 — Passphrase Setup

**Route:** `/onboarding/secure`.

**Layout:** Full-screen, centered, simple.

**Content:**
- Headline: **"Secure your Kraken."**
- Body: "Your data is encrypted on this device. Only you can unlock it — not even we can."
- Passphrase entry field with strength indicator (weak / fair / strong).
- Passphrase confirmation field.
- Toggle: "Also unlock with Face ID / biometrics" (default: on if device supports; hidden if device does not).
- A prominent, boxed disclosure:
  > **Important:** If you lose this device or forget your passphrase, your data cannot be recovered. We can't reset it. You'll be able to export encrypted backups later.
- Checkbox (not pre-checked): **"I understand."**
- Primary button: **"Set passphrase"** (disabled until passphrase meets minimum strength, confirmation matches, and understanding checkbox is ticked).

**Behavior:**
- Passphrase minimum: 10 characters, at least one non-alphabetic character. Show strength indicator as user types.
- On submit: derive vault key via the existing two-factor derivation (passphrase + device-bound secret per `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §3.4), initialize vault, register biometric fast-unlock if toggled.
- Failure modes: if platform keystore is unavailable (rare), show error and allow passphrase-only setup with an extra disclosure that data is less recoverable on theft. This path is a defensive fallback, not a default.
- On success, advance to `/onboarding/demo`.

### 1.5 Screen 5 — The Offline Demo

**Route:** `/onboarding/demo`.

**Design intent:** This screen demonstrates Kraken's independence from network connectivity. Users who try the demo will have a memorable moment; users who skip should not feel they missed something important. Both paths complete onboarding successfully.

**Layout:** Full-screen, centered. Two options presented with equal visual weight.

**Content before airplane mode is enabled:**

- Headline: **"Try it offline."**
- Body: "Turn on airplane mode, then tap Try it below. Or skip and start using Kraken — the demo is just a moment of proof, not a required step."
- Secondary hint with platform-specific instruction: "Swipe down from the top-right and tap the airplane icon" (iOS) / "Swipe down and tap the airplane icon" (Android).

**Two buttons, equal visual treatment (side-by-side on wide screens, stacked on narrow):**

- **"Try it"** — disabled (grayed out) until airplane mode is detected, activates when it is.
- **"Skip and start using Kraken"** — always active.

Neither button carries a "primary" vs "secondary" styling. Do not make the skip button smaller, lighter, or buried. Both are legitimate paths.

**Content once airplane mode is detected (user chose Try it):**

- "Try it" button activates with a subtle transition.
- Tapping it opens a simple modal with:
  - Voice input button (mic icon; consumes `VoiceInputService`).
  - Text input field as alternative.
  - Below: "Ask anything. Kraken works without internet."
- When user submits (via voice or text), response streams token-by-token to the screen, clearly visible. Airplane mode indicator in status bar is visible throughout.
- After the response completes, a subtle affirmation: **"That just happened without an internet connection."**
- Primary button: **"Enter Kraken"** (advances to the home screen and marks onboarding complete).

**Content if user chose Skip:**

- No apology copy. No "are you sure?" dialog. Onboarding marks complete and advances to the home screen immediately.
- The offline demo remains available from the settings screen afterward as "See Kraken work offline" for users who want to try it later.

**Behavior:**

- Airplane mode detection: use `connectivity_plus` or platform-native connectivity APIs to poll every 2 seconds. Activate the "Try it" button when no network connectivity is present.
- If user turns airplane mode *off* while the demo is in progress, do not fail — the app still works. The demo is about proving independence from network, not enforcing it.
- User reaches this screen only once per install. The optional "See Kraken work offline" in settings is the re-entry point afterward.

**Conversion note for future analysis:** Track (privately, on-device only, per the audit log pattern) how many users choose Try it vs. Skip. This is useful product information — not for behavioral targeting, but for understanding whether the demo is doing its job. If >80% of users skip, the screen is friction without value. If <10% skip, it may be over-weighted. Neither datapoint requires sending anything off-device; the audit log already captures onboarding events locally.

### 1.6 Onboarding Completion State

- On successful completion of Screen 5 (Try it or Skip) or a valid skip from earlier screens (e.g. airplane-restricted device), set `isOnboarded = true` in the shell's app-lifecycle state (not kernel auth state — onboarding is a shell concern, not an auth concern).
- The flag is persisted via the shell's existing preferences storage, which itself is backed by the encrypted vault for consistency with the overall privacy model. Uninstalling and reinstalling the app triggers onboarding again. This is correct behavior.
- No "welcome back" screen on second launch. Authenticated users land directly on the unlock screen.
- The kernel has no knowledge of onboarding state. Kernel auth state concerns only vault initialization and unlock — two distinct lifecycle stages. This separation keeps each layer's responsibilities clean.

## Phase 2: Home Screen Updates

### 2.1 Home screen structure

Update the existing home screen at `/home` to show:

- **Top section:** A compact library selector or "Your Libraries" summary. Tapping opens the library management screen.
- **Spoke grid:** Three cards for the free-tier spokes (Meeting Notes, Document Summaries, Quick Capture). A fourth card labeled "Expand" with a subtle "+" icon; tapping opens a spoke marketplace screen (placeholder acceptable in this mission — the real marketplace is a later feature).
- **Activity section:** A brief "Recent Activity" feed showing the last 5 AI operations (e.g. "Summarized meeting_2026-04-18.m4a — 2 min ago"). Tapping an entry opens the relevant spoke or its output.

### 2.2 First-session home banner

On the first visit to home after onboarding completes, show a dismissible banner at the top:

> Your data lives in Libraries. Tap here to create your first one, or jump straight into a spoke.

- Banner dismisses on tap or on first spoke launch.
- Does not reappear on subsequent sessions.
- No other banners or promotional content on the home screen, ever.

### 2.3 Persistent offline indicator

Add a small, non-alarming dot to the app's top bar (beside the library indicator):

- **Green dot:** AI engine is warm and idle, ready for inference.
- **Blue pulsing dot:** AI engine is actively processing (during inference).
- **Gray dot:** AI engine is loading or unloading.
- **Red dot:** AI engine error state (tapping opens diagnostic info).

Tooltip on long-press: "On-device AI — no internet used."

This is passive reassurance. It does not demand the user's attention. It's simply present.

### 2.4 "Where does this live?" microcopy

Throughout spoke UIs, add small inline disclosures at the appropriate points:

- When a user views a document in Document Summaries: beneath the title, "Stored in 'Client Work' library. Encrypted on this device."
- When a user views an AI-generated summary or quote draft: beneath the output, "Generated by Gemma 4 on-device. No data transmitted."
- When a user views a meeting recording in Meeting Notes: beneath the title, "Transcribed on this device." followed by a second line reflecting the user's actual audio retention setting for this recording. See §2.4.1.

These are small. They appear once per relevant action, not as persistent clutter. They should feel like quiet honesty, not marketing.

### 2.4.1 Audio retention policy (Meeting Notes and any future spoke that captures audio)

Audio retention is a user choice with a sensible default. Three settings:

- **Auto-delete after transcription** — audio is deleted immediately after transcription completes. Smallest storage footprint, no playback available.
- **Auto-delete after 90 days** (default) — audio is retained so the user can re-listen or export, but is automatically purged after 90 days of no access. Balances utility and storage.
- **Keep until I delete** — audio is retained indefinitely. User manages deletion manually.

The setting is per-spoke, not global — a future voice-memo spoke might want different defaults than Meeting Notes. Meeting Notes ships with the 90-day default.

**Export is always available.** Regardless of retention setting, users can export any recording (audio file, transcript, summary, or all three) to device storage via the share sheet while the audio is still present. Once audio is deleted, only the transcript and summary remain — the export option for audio is greyed out with a clear "Audio has been deleted per your retention settings" note.

**Microcopy reflects actual state, not a generic promise.** Depending on the user's setting and the recording's current state, the "where does this live?" line reads as:

- If auto-delete-after-transcription: "Audio was deleted after transcription. Transcript and summary are retained."
- If 90-day retention and audio still present: "Audio retained until [date]. Transcript and summary are kept."
- If keep-until-delete: "Audio retained until you delete it."
- If audio has been deleted: "Audio deleted. Transcript and summary remain."

Never show a retention claim that doesn't match the user's actual setting for the specific recording. If in doubt, say less — "Transcribed on this device" is always true and always safe.

**Settings surface.** In Meeting Notes' own settings (accessed from within the spoke, not kernel settings), show:

- Current default retention policy.
- Option to change the default for future recordings.
- Option to apply the new default to existing recordings (with a confirmation dialog explaining that this may delete audio files).
- Storage used by audio files, with a "Review and delete" shortcut.

**The kernel does not enforce audio retention.** This is a spoke-level policy, not a kernel-level one. The kernel's vault stores the audio blobs and honors deletion requests; the Meeting Notes spoke is responsible for tracking retention rules and issuing deletes. Document this separation in the Meeting Notes spoke's own design brief, not in kernel docs.

## Phase 3: Activity Panel

### 3.1 Purpose

Surface the kernel's audit log in a human-friendly way. Users should be able to see exactly what the app has been doing with their data.

### 3.2 Route and access

- Accessible from settings as "Activity" and from the home screen's "Recent Activity" section as "View all activity."
- Read-only view onto the kernel's `audit_log` table.

### 3.3 Content

Each entry shows:
- Timestamp (relative: "2 min ago" / "yesterday at 3:14 PM" / absolute after 7 days).
- Operation description, plain English: "Summarized document: PriceSheet_Q2.xlsx" or "Transcribed audio: 14-minute recording" or "Created library: Client Work."
- Spoke or shell origin: "Meeting Notes" / "Document Summaries" / "Kraken Shell."
- Data-flow note: **"Processed on-device. No data transmitted."** (This line is constant across every entry. It's the point.)
- Optional expand control: shows the raw audit log record (inference job ID, library ID, etc.) for users who want technical detail.

### 3.4 Filtering and search

- Filter by spoke, by date range, by operation type.
- Search by document name or entity name.
- Export button: produces a CSV of the audit log via `ExportService` for users who want a record (e.g. compliance reviews).

### 3.5 Purge

A "Clear activity history" button at the bottom with a confirmation dialog. Consistent with the 90-day retention policy in `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §14, this lets users manually purge earlier.

## Phase 4: Settings Additions

Add to the existing settings screen:

### 4.1 Privacy section (new, top-level)

- Static description: "Kraken processes all data on this device. Details below."
- Link: "View activity log" (opens Activity panel).
- Link: "Security protocol" (opens an in-app viewer for `KRAKEN_SECURITY_PROTOCOL.md`).
- **AI engine updates** — a section with a manual **"Check for updates"** button and one sentence of explanation: "Tap to see if a newer AI engine is available. Kraken only contacts the update server when you tap this button — never automatically. Update checks download version information only; they do not upload anything about you or your data."
  - Tapping the button makes a single request to the allowlisted CDN endpoint to fetch the current model manifest. Shows result: "You have the latest AI engine" or "Update available (version X.Y, N MB)."
  - If an update is available, the user decides whether to download it via a second explicit action ("Download update"). Nothing happens automatically.
  - No "auto-check" toggle. The trade would be convenience for loss of the clear "Kraken only reaches the network when you tell it to" story. Not worth it.
- Button: "Export encrypted backup of my vault" (placeholder — feature not in v0; button shows a friendly "coming soon" state).
- Button: "Purge all data" (destructive; triple-confirmation: warning dialog → typed "DELETE" confirmation → final confirmation). Destroys vault, all libraries, all spoke data. Cannot be undone.
- Button: "See Kraken work offline" (opens the optional offline demo from onboarding Screen 5, usable anytime).

### 4.2 Voice input settings (existing, per previous mission)

Keep as previously specified. One toggle for "Enable voice input across Kraken." No expansion.

## Phase 5: Restraint Requirements (What NOT to Build)

These are as important as what to build. Do not add any of the following to the app, now or incidentally:

- Rate/review prompts. Kraken does not ask for App Store ratings.
- Feature announcement popups after updates. Changelog in settings is fine; blocking modals are not.
- Mandatory feature tours. Users discover the app by using it.
- "Discover" or "What's new" sections on the home screen.
- Push notifications for engagement (reminders, re-activation prompts, promotional content). Push is reserved for user-scheduled alarms only (e.g. meeting reminders if a future spoke adds them).
- Badges encouraging specific actions.
- Analytics SDKs, crash reporters, or any third-party telemetry. Crashes are reported via the platform's native crash reporting (App Store Connect / Play Console) only, with no additional SDK.
- A "Powered by" footer anywhere. Keep the app clean.

If at any point the build feels like it needs one of these to "drive engagement," stop and flag it. The restraint is the product.

## Phase 6: Tests

### 6.1 Unit tests

- Onboarding state machine: Welcome → Overview → Download → Secure → Demo → Home. Each transition is gated by the prior completing successfully. State persists correctly across app backgrounding.
- Passphrase strength calculator: weak/fair/strong thresholds behave as specified.
- Airplane mode detection: polls at correct interval; updates button state; handles edge cases (airplane mode toggled off mid-demo).

### 6.2 Integration tests

- First-launch fresh install: user completes all 5 screens and lands on home. Vault initialized. Model downloaded and warm. Passphrase successfully unlocks on relaunch.
- Background/resume during download: user backgrounds during download; download continues; re-opening shows correct progress.
- Passphrase-wrong relaunch: correct passphrase on relaunch unlocks; wrong passphrase fails with clear error; no lockout in v0 (revisit in future mission).
- Demo-skip path: user taps "Skip this demo" on Screen 5; onboarding completes successfully; home renders correctly.
- Activity panel: a test operation (document summarization on stub data) appears in Activity with correct metadata and "Processed on-device" note.

### 6.3 Visual/UX checks (manual, with screenshots attached to PR)

- Each onboarding screen at default font size, largest accessibility font size, and both light/dark mode.
- Home screen at fresh-install and with-data states.
- Activity panel with zero entries, few entries, and many entries.
- Verify no placeholder lorem ipsum, no TODO strings, no debug text reaches user-visible surfaces.

### 6.4 Copy review

Before merging, a human must review every user-facing string in this mission against these criteria:
- Honest: claim only what the app actually does.
- Specific: "Gemma 4 on-device" not "advanced AI."
- Plain: no marketing language, no exclamation points, no adjectives without reason.
- Respectful: no guilt-tripping, no dark patterns, no fake urgency.

## Phase 7: Exit Criteria

All must pass on iOS simulator and Android emulator:

1. Fresh install launches to `/onboarding/welcome`; each subsequent screen reachable only after the prior completes.
2. Model download screen correctly handles State A (model not present; shows download progress from existing service) and State B (model already present; skips the screen entirely).
3. Passphrase setup derives vault key using the two-factor model (passphrase + device-bound secret).
4. Passphrase disclosure checkbox must be ticked before setup can proceed.
5. Biometric unlock correctly gated to the same key material; disabling biometrics does not lock the user out.
6. Airplane mode demo: "Try it" button is disabled without airplane mode, activates when airplane mode detected, inference runs with no network. "Skip and start using Kraken" is equally accessible and styled — both paths complete onboarding cleanly without guilt copy.
7. Offline demo is accessible from settings afterward as "See Kraken work offline."
8. `isOnboarded` flag lives in shell app-lifecycle state (not kernel auth state); onboarding completes exactly once per install; second launch goes directly to unlock screen.
9. Home screen shows three free-tier spoke cards, an expand slot, and recent activity feed.
10. Persistent offline indicator reflects AI engine state correctly across idle/inference/loading/error.
11. Microcopy appears in the expected places in spoke UIs. Meeting Notes microcopy correctly reflects the per-recording audio retention state rather than showing a generic "audio deleted" claim.
12. Audio retention settings (auto-delete after transcription / 90-day default / keep-until-delete) are implementable and exposed in the Meeting Notes spoke's own settings. (Implementation itself is in the Meeting Notes mission — this mission verifies the microcopy integration point works.)
13. Activity panel displays audit log entries in plain English with data-flow notes; filter/search/export functions work; purge requires confirmation.
14. Settings Privacy section includes all specified entries. AI engine update is a manual "Check for updates" button — never an automatic background check. Purge-all-data requires triple confirmation.
15. No prohibited elements (rating prompts, analytics, automatic update checks, popups) exist anywhere in the codebase — verified by grep for known package names and by code review.
16. All user-facing copy reviewed by a human for honesty, specificity, plainness, and respect.
17. Phase Completion Checklist produced and committed.

## Out of Scope (Do Not Build)

- Spoke implementations themselves. This mission is shell and onboarding only. Spokes are separate missions.
- Cross-device sync or any cloud feature.
- Account systems, email capture, signup flows.
- In-app purchase wiring for paid spokes (handled in a separate monetization mission).
- Vault backup/export beyond the "coming soon" placeholder.
- The spoke marketplace screen beyond a placeholder. Real marketplace is a later mission.
- Advanced activity analytics (trends, usage reports). v1 Activity is a timeline, not a dashboard.
- Multi-language support for onboarding copy. v1 ships English only; localization is a future mission.

## Execution Order

1. Phase 1.1–1.6 (all onboarding screens) in sequence, each passing its own mini-verification before the next begins.
2. Phase 2 (home screen updates) — some pieces can start alongside Phase 1 since they're independent.
3. Phase 3 (Activity panel) — consumes audit log; verify audit log integrity before surfacing it.
4. Phase 4 (settings additions) — isolated; can be done last.
5. Phase 5 (restraint requirements) — this is a grep/audit phase, not new code. Run it before exit criteria.
6. Phase 6 (tests) alongside each phase, not at the end.
7. Phase 7 (exit criteria) — final gate. Do not declare done with any criterion unverified.

Stop at the end with a Phase Completion Checklist and wait for human review before any spoke work begins.

## Design Reference Notes

- The onboarding flow is designed to be **memorable**, not fast. Do not optimize for conversion percentage; optimize for "users who complete onboarding have understood what this product is."
- The airplane mode demo is the keystone moment for users who engage with it. The skip path is equally legitimate — a user who skips should feel they made a fine choice, not that they missed out. Treat both paths as first-class.
- Every piece of microcopy in this mission should read as if written by a person who would be embarrassed to overpromise. Understate rather than oversell. The product is unusual enough that honest plain language is more powerful than marketing.
- If something in this brief feels awkward or unusual compared to "normal" app design, that's likely intentional. Kraken is not trying to be a normal app. Confirm before smoothing out friction that may be deliberate.

## A Practical Note on Prerequisites

This mission assumes the model download service is already built and working (which it is, per current project state). Screen 3 is a UI layer over that service, not a reimplementation.

This mission also assumes `VoiceInputService` is built and available, since Screen 5's airplane-mode demo uses it. If voice input is not yet implemented, either complete that mission first or temporarily fall back Screen 5 to text-only input with a TODO to add voice once the service lands.

Post-completion, verify the onboarding flow against a realistic "fresh install" scenario: uninstall the app, reinstall, and go through onboarding from zero. This is the only way to catch subtle state-dependency bugs that pass unit tests but fail in real use.
