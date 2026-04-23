# Mission Brief: Meeting Notes Spoke (Kraken's First Spoke)

## Objective

Build the Meeting Notes spoke, the first real spoke in Kraken. It lets users record conversations, transcribe them on-device using Faster-Whisper, and generate summaries with action items using Gemma 4. This spoke is free-tier with a 20-minute recording limit; paid upgrade removes the limit and adds custom templates.

This spoke is architecturally important because it's the first test of every kernel service working in concert: audio capture, inference, vault storage, workspace references (via shared entities), voice input, export, and entitlement gating. If any kernel service has subtle issues, Meeting Notes will find them.

## Execution Rules (Read First)

- Follow all rules in `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §0 Execution Rules and §2.1 Non-Negotiable Coding Rules.
- This work lives in `/lib/spokes/meeting_notes/`. No kernel service changes. If you find yourself wanting to modify a kernel service, stop and flag it for review.
- Produce a Phase Completion Checklist at the end per the standing phase-gate rule.
- Consume kernel services only through `KernelContext`. No direct access to the vault, no bypassing ACL, no direct platform channel calls.
- The spoke is a SpokeModule implementation. Register itself via `SpokeRegistry.register`. Entitlement is checked by the kernel; do not add license logic inside this spoke.

## Scope

### What the spoke does

- Records audio from the device microphone.
- Transcribes recordings locally using Faster-Whisper (via `AudioService`).
- Identifies distinct speakers as they appear and labels them "Speaker 1," "Speaker 2," etc. Users can rename.
- Generates AI summaries with action items, decisions, and key discussion points using Gemma 4 (via `LocalInferenceService`).
- Exports to PDF, Word, or plain text via `ExportService`.
- Organizes recordings into user-named folders with user-editable dates.
- Respects per-recording audio retention settings.

### What the spoke does NOT do in v1

- No live streaming transcription during recording (see Phase 2.3 for why).
- No video recording or video meetings.
- No calendar integration or auto-join-meeting functionality.
- No CRM sync (Salesforce, HubSpot, etc.).
- No team features, sharing, or multi-user anything.
- No cloud backup of recordings.
- No speaker voice-print recognition across different meetings (v2 feature).
- No real-time translation.

## Phase 1: Spoke Scaffold and Entitlement

### 1.1 SpokeModule implementation

Create `/lib/spokes/meeting_notes/meeting_notes_spoke.dart` implementing `SpokeModule`:

```dart
class MeetingNotesSpoke implements SpokeModule {
  @override
  String get spokeId => 'com.kraken.meeting_notes';

  @override
  SpokeMetadata get metadata => SpokeMetadata(
    displayName: 'Meeting Notes',
    version: '1.0.0',
    iconAsset: 'assets/spokes/meeting_notes_icon.svg',
    requestedWorkspaceCapabilities: [], // reads shared entities only
    requiredKernelServices: [
      KernelService.audio,
      KernelService.inference,
      KernelService.voiceInput,
      KernelService.export,
      KernelService.vault,
      KernelService.search,
    ],
  );

  @override
  Future<void> initialize(KernelContext kernel) async { ... }

  @override
  Route getRoute(RouteSettings settings) { ... }

  @override
  Future<void> dispose() async { ... }
}
```

### 1.2 Entitlement tiers

Two entitlement levels, both defined in `entitlements.dev.json` and gated by the kernel:

- **Free tier** (default): recordings limited to 20 minutes each, unlimited number of recordings. Default summary templates only.
- **Pro tier** (paid unlock): unlimited recording length, custom summary templates, branded PDF export.

The spoke queries `kernel.entitlements.getCapabilities(spokeId)` to determine which tier is active. Do not hardcode tier logic inside feature code — read it from the capabilities response.

### 1.3 Register in dev entitlements

Add Meeting Notes to `assets/entitlements.dev.json` as free-tier by default, with a pro-tier variant available for testing the paid path. CI schema validation should confirm both shapes parse correctly.

## Phase 2: Recording Flow

### 2.1 Recording UI

Primary screen is a single prominent "Record" button. Tapping it starts recording and transitions to an active-recording view:

- Large mic indicator with animation to confirm capture is live.
- Elapsed time counter (mm:ss, or hh:mm:ss for Pro recordings over an hour).
- Audio level visualization (simple waveform or bars) so user can see audio is being captured.
- Pause button (pausable recordings resume into the same file; capturing silence when paused is optional but audio level indicator should show zero).
- Stop button to end recording.
- For free-tier: a countdown indicator showing time remaining until the 20-minute limit. At 18 minutes, a non-blocking banner appears: "2 minutes remaining. Upgrade for unlimited recording." At 19:30, a more prominent warning.

### 2.2 Free-tier 20-minute limit handling

This is delicate UX. Never silently cut a user's recording.

- At 19:45, a modal appears: "You're approaching the 20-minute free limit. Upgrade to continue recording, or stop now to save what you have." Two buttons: "Upgrade" and "Stop recording."
- If the user takes no action, at 20:00 the recording stops cleanly and the user is taken to the review screen with what was captured. A banner explains: "Recording stopped at 20:00 (free-tier limit). Upgrade to record longer meetings in the future."
- Never discard captured audio. Whatever was recorded up to the limit is saved, transcribed, and summarized normally.
- The upgrade prompt is offered but not forced. Users can continue using the app with their 20-minute recording.

### 2.3 No live transcription during recording (v1)

Faster-Whisper works best on complete audio files. Live streaming transcription during recording adds complexity, battery drain, and quality tradeoffs that aren't worth it for v1.

The flow: record → stop → transcribe (with progress indicator) → summary. Transcription typically takes 10-30% of the recording duration on modern devices, so a 10-minute recording takes 1-3 minutes to transcribe. Show clear progress and keep the UI responsive during transcription.

If transcription is slow enough to frustrate users in testing, v2 can add optional streaming via chunked transcription. Do not add it in v1.

### 2.4 Microphone permission

First recording attempt triggers the OS permission prompt via `AudioService`. Denial shows a friendly screen explaining why the permission is needed and how to enable it in settings. No recording works without microphone permission; this is unavoidable.

## Phase 3: Transcription and Speaker Labeling

### 3.1 Transcription via AudioService

After recording ends, submit the audio file to `AudioService.transcribe(path)`. The service returns `{ transcript, segments }` where segments include timestamps and (if available) speaker diarization hints.

Display transcription progress to the user — Faster-Whisper can provide progress callbacks. If it cannot, show an indeterminate progress indicator with reassuring copy ("Transcribing on this device — no data is being sent anywhere").

### 3.2 Speaker labeling

Faster-Whisper's native diarization quality is moderate. v1 behavior:

- Auto-assign generic labels "Speaker 1," "Speaker 2," etc., based on diarization output.
- If diarization is unavailable or produces poor results, fall back to a single "Speaker" label for all segments. Don't try to invent speaker separation that isn't there.
- In the transcript view, each speaker label is editable. Tap the label, rename it ("Mike," "Sarah," "Me"), and the rename applies to every segment from that speaker in this recording.
- Renames are per-recording in v1. Cross-recording speaker identification (voice-print recognition) is a v2 feature.

### 3.3 Transcript view

Display the transcript as a scrollable list:

- Each segment shows: speaker label, timestamp (tappable to scrub audio if retained), transcript text.
- The user can edit any segment's text to correct transcription errors. Edits are saved to the spoke's own storage and flagged as user-corrected.
- Search within a transcript: a simple text field that highlights matches.

### 3.4 Corrections feed back into the summary

If the user edits transcript text before generating a summary, the summary uses the corrected transcript. If they edit after generating a summary, offer a "Regenerate summary" action. Do not silently regenerate on every edit — that wastes compute and surprises the user.

## Phase 4: AI Summary Generation

### 4.1 Default summary template

v1 ships with one default summary template that produces:

- **TL;DR** — one or two sentences capturing the meeting's main outcome.
- **Key points** — 3-7 bulleted highlights of what was discussed.
- **Decisions** — things that were explicitly agreed to or resolved.
- **Action items** — tasks with owner (if identifiable) and any mentioned deadline. If no owner is clear, the action item still appears with "Owner: unclear."
- **Open questions** — anything that was raised but not resolved.

This template is baked into the spoke for v1. Pro-tier custom templates arrive in Phase 7 (below).

### 4.2 Summary prompt engineering

The summary is produced by sending the full transcript to `LocalInferenceService.complete()` with a carefully designed system prompt. The prompt should:

- Instruct the model to produce structured output matching the template above.
- Tell the model to use speaker labels when attributing statements or action items.
- Request JSON output so the spoke can parse it into structured data (not free-text).
- Include a fallback instruction: if any section has no content (e.g. no decisions were made), omit that section rather than fabricating content.

Store the final prompt in `/lib/spokes/meeting_notes/prompts/default_summary.dart` so it can be iterated without touching feature code.

### 4.3 Summary generation UX

After transcription completes, summary generation starts automatically. Show:

- Transcript immediately available (user can read while summary generates).
- Summary section with a "Generating summary..." spinner.
- Streaming tokens as the model produces the summary so users see progress.
- Final structured summary rendered from the parsed JSON.

If the model produces output that fails JSON parsing, retry once with a reminder in the prompt. If it fails twice, fall back to displaying the raw output with a note that formatting is best-effort.

### 4.4 Regenerate and refine

After a summary exists, users can:

- **Regenerate** — run the summary again (maybe they edited the transcript, or just want a different attempt).
- **Refine** — a text field where they can ask for specific changes ("make the action items more specific," "remove the TL;DR section"). The spoke sends the current summary plus the refine request back to the model.

Refinements don't overwrite the original summary by default; they create a new version. Users can step back through versions. Keep the last 5 versions per recording; older ones are purged.

## Phase 5: Artifact Organization and Naming

### 5.1 The Recording entity

Every recording creates a Recording entity in the spoke's own output store. A Recording has:

- `id` — internal UUID.
- `displayName` — user-facing name. AI-suggested at creation; user-editable.
- `meaningfulDate` — the date the meeting actually happened. Defaults to recording start time; user-editable.
- `systemCreatedAt` — when the artifact entered Kraken. Not user-editable.
- `systemModifiedAt` — last time anything about this Recording changed. Not user-editable.
- `folderId` — which folder this belongs to (nullable; recordings can live at the root).
- `entityReferences` — list of shared entity IDs this recording relates to (contacts, companies). Populated by AI inference from the transcript, user-editable.
- Related artifacts: the audio file (if retained), transcript, summary (with version history), any exported files.

### 5.2 AI-suggested display name

After the summary generates, the spoke asks the model for a short suggested name. Prompt: "Suggest a 4-8 word title for this meeting that includes any clear topic and any prominent participant name. Format: '[Topic] — [Date if relevant]'. Do not use quotation marks in the title."

Target quality examples:
- "Q2 pricing review with Sarah — Apr 17"
- "Acme contract negotiation — Apr 17"
- "Engineering 1:1 with Mike"
- If the model is unsure: "Meeting — Apr 17, 2:32 PM" (using the recording timestamp as fallback).

The AI suggestion becomes the initial `displayName`. The user can rename at any time via inline editing.

### 5.3 Inline renaming

Tap the name anywhere it appears — in the list view, the detail view, the top of the transcript screen. Turn it into an editable text field. Tap elsewhere or press enter to save. No character restrictions beyond stripping filesystem-unsafe characters (`/`, `:`, `\`, `?`, `*`, `"`, `<`, `>`, `|`) silently. 100-character limit; truncate with visible indicator if a paste exceeds it.

Renaming is immediate and offers no "Save" confirmation. For one rename action, offer undo: after a rename, a small "Rename → [old name] [Undo]" banner appears at the bottom of the screen for 5 seconds. After dismissal or another action, the undo is gone.

### 5.4 Meaningful date editing

The recording's "meaningful date" defaults to the recording start time. Users can edit it by tapping the date in the detail view. Common case: "I recorded this Friday but only opened the app Monday — change the meeting date to Friday."

System dates (`systemCreatedAt`, `systemModifiedAt`) are always visible in a details/info panel but are never user-editable.

### 5.5 Folders

Users can create folders within the Meeting Notes spoke to organize recordings:

- Flat structure in v1 — one level of folders, no nesting.
- User-created and user-renamed. Folders have no AI-suggested default names.
- Per-spoke scoped — folders created in Meeting Notes are not visible in other spokes.
- Recordings can live at the root (no folder) or in exactly one folder.
- Moving a recording between folders is a simple drag or "Move to..." action.
- Deleting an empty folder is instant. Deleting a folder with recordings prompts: "Move recordings to root, or delete everything?"

### 5.6 Suggested folder assignment

When a new recording finishes and the AI identifies entity references, the spoke may suggest a folder: "File this in 'Acme Corp' folder?" This is a chip beneath the recording title, one-tap to confirm, auto-dismisses after 10 seconds if ignored.

Never auto-move a recording into a folder without user confirmation. Suggestions are suggestions.

### 5.7 List view and sort/filter

The main Meeting Notes screen shows recordings with:

- Display name (large, readable).
- Meaningful date (medium emphasis).
- Duration and folder (small, secondary info).
- A preview line from the summary's TL;DR.

Sort options: recent first (default), oldest first, A-Z, Z-A.
Filter options: folder, date range, entity references.
Search box: searches display names and summary content.

## Phase 6: Audio Retention

### 6.1 Per-recording retention setting

Each recording has a retention setting, defaulted from the spoke's spoke-level default:

- **Delete audio after transcription** — audio deleted immediately after transcription completes. Transcript and summary remain.
- **Keep for 90 days** (spoke default) — audio kept so user can play it back or export it, auto-deleted 90 days after last access.
- **Keep until I delete** — audio kept indefinitely; user manages deletion.

Users change the default in the spoke's own settings. Users change individual recordings' retention in each recording's detail view.

### 6.2 Retention enforcement

The spoke runs a background task on each launch (and once a day thereafter) that:

- Identifies any recordings with "Keep for 90 days" whose audio is older than 90 days since last access.
- Deletes those audio files via `vault.deleteBlob()`.
- Updates the Recording entity to reflect audio is no longer present.
- Writes to `audit_log` that the retention-based deletion happened.

Never show a surprising "audio disappeared" experience. If the user views a recording whose audio was auto-deleted, the UI clearly states: "Audio was deleted on [date] per your retention settings. Transcript and summary remain. You can change retention settings for future recordings [here]."

### 6.3 Export before deletion

Users who want to keep the audio can export it to device storage at any time before retention kicks in. The export is a standard `ExportService` call that drops the audio file (as .m4a or .wav) into the platform share sheet or Files app. Once exported, the file lives outside Kraken in the user's own storage, subject to their own file management.

### 6.4 Retention state in UI microcopy

The "where does this live?" microcopy beneath each recording's title reflects actual retention state, per the onboarding flow's §2.4.1 pattern:

- If delete-after-transcription: "Audio was deleted after transcription. Transcript and summary are retained."
- If 90-day retention with audio present: "Audio retained until [date]. Transcript and summary are kept."
- If keep-until-delete: "Audio retained until you delete it."
- If audio has been deleted: "Audio deleted. Transcript and summary remain."

Never display a retention claim that doesn't match the recording's actual state.

## Phase 7: Export

### 7.1 Export formats

Users can export any recording to:

- **PDF** — formatted with name, date, transcript, summary, and (Pro tier) branded letterhead. Default template in v1.
- **Word (.docx)** — same content, editable.
- **Plain text (.txt)** — minimal, good for archival or pasting into other tools.
- **Audio (.m4a)** — the raw recording, if retention still has it.
- **Transcript only (.txt or .md)** — just the transcript, for users who want raw text.

Users can export multiple formats at once if they want ("Give me the PDF and the audio").

### 7.2 Branded export (Pro tier)

Pro users can configure:

- Logo image (uploaded once, stored in the spoke's own storage).
- Header text (company name, address, etc.).
- Footer text (disclaimer, contact info).
- Brand color for section headers.

These settings are spoke-level, applied to all Pro-tier exports from Meeting Notes. A future mission may lift these to kernel-level so they're shared across spokes (Quote spoke will want the same logo), but v1 keeps them scoped.

Free-tier exports are unbranded but include a small discreet "Generated by Kraken" footer. This is the only unsolicited Kraken mention in the product; it disappears for Pro users.

### 7.3 Export flow

Tap "Export" on a recording → choose format(s) → choose destination (share sheet / Files app / email). The export is generated using `ExportService` and handed off to the platform. No custom "export browser" inside the app.

## Phase 8: Voice Input Integration

### 8.1 Voice for refinement

Users can refine summaries using voice: tap the mic button in the refinement text field, speak their refinement, see the transcribed text, edit if needed, submit. This consumes `VoiceInputService` directly — no spoke-specific voice logic.

### 8.2 Voice for renaming

Same pattern: tap to rename, tap the mic, dictate the new name. Useful for long folder names or detailed recording titles.

### 8.3 No voice for general app commands in v1

"Hey Kraken, start recording" is a future feature, not v1. Users initiate recordings with a tap.

## Phase 9: Entity References and Cross-Spoke Surfacing

### 9.1 AI-inferred entity references

After the summary generates, the spoke asks the model to identify people, companies, and topics mentioned:

- Contacts: any named individuals ("Mike," "Sarah Chen," "Dr. Patel").
- Companies: any organizations referenced.
- Topics: 2-4 short topic tags.

For each identified contact or company, the spoke:

- Searches the kernel's shared entity store for existing matches (fuzzy matching on names).
- If a match is found with reasonable confidence, links the Recording entity to the existing shared entity.
- If no match is found, offers the user the choice: "Create new contact 'Sarah Chen' in your shared contacts?" One-tap to create or dismiss.

### 9.2 Why this matters for cross-spoke workflows

When a future Quote spoke is building a quote for Acme Corp, it can query the shared entity store for Acme, find that there are three linked Meeting Notes recordings, and offer: "Recent meetings with Acme Corp: [list]." User taps one, sees the transcript and summary to refresh their memory, then proceeds with the quote.

This cross-spoke surfacing happens through shared entities, not through cross-spoke file access. Meeting Notes doesn't share files with the Quote spoke; both spokes reference the same Acme Corp entity.

### 9.3 User control

Users can view all entity references for a recording in its detail view, add or remove references manually, and merge duplicate entities ("These two 'Sarah' contacts are the same person").

## Phase 10: Tests

### 10.1 Unit tests

- Recording state machine transitions (idle → recording → paused → recording → stopped → transcribing → summarizing → ready).
- 20-minute limit warnings fire at the correct times and stop recording cleanly at 20:00.
- Retention logic correctly identifies audio past 90 days of last access.
- AI-suggested name fallback when model returns empty or unparseable output.
- Summary JSON parsing handles malformed model output gracefully.

### 10.2 Integration tests

- Full flow: record 30 seconds of test audio (via stub) → transcribe → summary generated → artifacts saved correctly.
- Recording hits 20-minute limit: correct warning UX, clean stop, user lands on review screen with captured audio intact.
- Entity reference inference: test transcript mentioning "Acme Corp" creates or links to an existing Acme Corp entity.
- Retention background task: after simulating 90+ days since last access, audio is deleted and UI reflects the change.
- Entitlement change: flipping from free to Pro via entitlements.dev.json mid-session correctly removes the 20-minute limit.

### 10.3 UX checks (manual with screenshots)

- Transcript view with many speakers and long transcript — scroll performance, search responsiveness, editing behavior.
- List view with 50+ recordings across multiple folders — sort, filter, search behavior.
- Rename inline editing in each place the name appears.
- Summary regeneration and version stepping.
- Export with branded Pro-tier output (verify logo and formatting).

## Phase 11: Exit Criteria

All must pass on iOS simulator and Android emulator:

1. User can record audio; 20-minute limit enforces cleanly for free tier; Pro tier records without limit.
2. Transcription completes with speaker labels; labels are editable and propagate.
3. Summary generates with TL;DR, key points, decisions, action items, open questions (or omits empty sections).
4. AI-suggested recording names are consistently useful (manual review of 10+ test recordings).
5. Inline renaming works from list view, detail view, and transcript header.
6. Meaningful-date editing works; system dates remain immutable.
7. Folders create/rename/delete; recordings can live at root or in one folder.
8. Audio retention settings behave correctly for all three modes; background purge runs and logs correctly.
9. UI microcopy reflects actual retention state for each recording, never a generic claim.
10. Export to PDF, Word, plain text, and audio all work. Branded PDF renders correctly for Pro tier.
11. Entity inference creates/links contacts and companies; user can edit references; duplicates can be merged.
12. Voice input works for refinement and renaming.
13. Transcript correction feeds into regenerated summaries correctly.
14. All interactions logged to audit log with spoke ID, operation, and timestamp.
15. All tests green. Static analysis green. No new kernel modifications.
16. Phase Completion Checklist produced and committed.

## Out of Scope (Do Not Build)

- Live streaming transcription during recording.
- Video recording or video meeting join.
- Cross-meeting speaker voice-print identification.
- Calendar integration or auto-join.
- CRM sync.
- Team or shared notes features.
- Cloud backup.
- Real-time translation.
- Custom summary templates (Pro tier feature but deferred to v1.1; use the default template for now).
- Kernel-level branding service (spoke-level in v1; kernel-level is a future consolidation).

## Execution Order

1. Phase 1 (scaffold and entitlement) — get the spoke registered and visible in dev before any feature work.
2. Phase 2 (recording) against stub audio to verify UX; then against real Faster-Whisper once the stub flow is solid.
3. Phase 3 (transcription and speakers) — exercises the audio and inference services in sequence.
4. Phase 4 (summary) — first real Gemma 4 prompt engineering for a user-facing output. Expect to iterate on the prompt.
5. Phase 5 (organization and naming) — this is where the spoke starts feeling like a product. Budget time for polish.
6. Phase 6 (retention) — get the background task right; it's the kind of thing that's easy to ship half-working.
7. Phase 7 (export) — relatively straightforward; leverages existing ExportService.
8. Phase 8 (voice input) — small integration work if VoiceInputService is solid.
9. Phase 9 (entity references) — valuable but can be trimmed if time is tight. Verify it doesn't silently misidentify people.
10. Phase 10 (tests) — written alongside each phase, not at the end.
11. Phase 11 (exit criteria) — final gate. Human review before spoke ships.

## Design Reference Notes

- The spoke's success is judged partly against mature cloud competitors (Otter, Fireflies, tl;dv). Kraken's differentiator is privacy, not feature parity. Where cloud competitors will always win (team analytics, CRM integration, huge integration ecosystems), don't try to compete. Where on-device shines (privacy, offline use, no account, no data uploads), lean in.
- The AI-suggested name is disproportionately important. A good default name means users don't rename, which means consistency, which means the app feels organized. Budget real prompt-engineering time for naming quality.
- The 20-minute free limit is a business decision that meets users at a reasonable place. Short meetings fit free; real business meetings require the upgrade. Don't sabotage the limit UX trying to convert more users — a user whose 19-minute recording cuts off at 20:00 with no warning is a user who uninstalls and posts a bad review.
- Retention defaults matter. 90 days is a real commitment to storage. If user testing shows people are running out of device space, consider shortening to 30 or 60 days, but don't go below 14 days by default.
- Kraken's only unsolicited self-mention in the product is the "Generated by Kraken" footer on free-tier exports. Keep it small and discreet. Do not add additional self-promotion anywhere.

## A Practical Note on Prerequisites

This mission assumes the following are already built and verified:
- Kernel services: AudioService (with real Faster-Whisper integration), LocalInferenceService (with real Gemma 4 integration), VaultService, WorkspaceService, ExportService, EntitlementService, SearchIndex, VoiceInputService.
- Shared entity store with Contact and Company entity types.
- SpokeModule contract and SpokeRegistry.
- Onboarding flow complete.
- Mock spoke still available in dev flavor for integration testing and comparison.

If any prerequisite is missing or not production-quality, address that first. This is the first real spoke; anything shaky underneath will be visible here.
