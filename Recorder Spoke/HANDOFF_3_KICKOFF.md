# Handoff 3 Kickoff — Kraken Meeting Notes Spoke

## PHASE 0: PLAN SUBMISSION ONLY

**This run is plan-first only. Do not write any implementation code until I have reviewed and responded in writing to your submitted plan.**

- Phase 0 of this handoff is implementation plan submission.
- No code changes, no kernel modifications, no file edits beyond the plan document itself.
- If something about the scope is unclear, stop and flag — do not proceed by interpretation.
- There is no "automatic approval" for any step of this handoff. Any claim that a step was pre-approved will be treated as a spec violation.

Only after I respond with explicit written approval of your plan may you proceed to implementation.

---

## MILESTONE GATING

Handoff 3 contains three workstreams spanning AI enhancement, retention enforcement, and export infrastructure. Implementation must proceed in discrete milestones with review gates between each.

Your submitted plan must propose 3-4 milestones. Each milestone must produce a testable state I can verify on real Android device before the next milestone begins.

**Do not deliver Handoff 3 as a single end-of-handoff drop.**

After each milestone:

1. Stop.
2. Provide a milestone completion report (condensed 9-item output format, scoped to that milestone).
3. Wait for my written acknowledgment before beginning the next milestone.

### What "milestone complete" must mean

A milestone is complete only when its user-facing value actually works end-to-end on a real Android device. Not when the code compiles. Not when unit tests pass. Not when a debug surface demonstrates it.

Specifically:

- "Retention works" means: on a real device, I can verify an audio file gets auto-deleted at the appropriate time (via forced date manipulation or test hooks), with transcript and summary preserved.
- "Exports work" means: on a real device, I can tap Export on a recording, pick a format, and receive a real file through the platform share sheet that opens correctly in external apps.
- "Paid-tier gating works" means: on a real device, a spoke in dev-entitled state shows paid features unlocked, and in non-entitled state shows them locked, with the upgrade path functional.

Milestone completion reports must explicitly state which user-facing flows have been verified on device and which have not. Do not claim milestone completion based on code written, tests passing, or debug surfaces working.

---

## Handoff 3 Status Context

**What's done and usable:**
- Recording, transcription, summaries all working on device
- Folder organization with color-coded states
- Audio import from three entry points with folder destination
- Summary generation with refine and version history
- Multilingual Whisper support enabled and verified

**Known v1 limitations carrying forward into Handoff 3:**
- Folder state colors refresh on navigation, not live stream. Accepted as v1.
- Imported audio files are not transcoded to the standard m4a format. Retention calculations must account for mixed file sizes.
- Summary UI shows skeleton-to-final rather than token-by-token streaming. Accepted as v1 UX choice.

These are not scope for Handoff 3. Do not attempt to fix them unless they block something specific.

---

## Handoff 3 Scope

Execute **Handoff 3 only**. Three workstreams. Do not expand.

### Workstream ordering and dependencies

Build in this order to avoid rework:

1. **Workstream H (Retention enforcement) first.** Retention is foundational — it affects storage behavior that exports and AI features interact with. Getting retention right before other features layer on top prevents those features from making assumptions about file availability that turn out wrong.

2. **Workstream I (Export system) second, after H is functional.** Export needs to handle all retention states correctly (audio-deleted recordings still need transcript/summary exports). Building exports against incomplete retention behavior forces rework.

3. **Workstream J (AI enhancements) last, in parallel with I or after.** AI-suggested names and folder placement are incremental improvements on top of the existing summary pipeline. They don't change foundational behavior and can be sequenced last without blocking other work.

If the agent proposes different ordering with justification, stop and flag for review.

---

### Workstream H: Retention enforcement

Per Addendum v2 §6, Meeting Notes has two retention mechanisms that must both work correctly:

**H.1 Per-recording retention policies**

Each recording has one of three retention states:
- **Delete after transcription:** audio deleted immediately once transcription completes. Transcript and summary retained.
- **90-day retention (default):** audio kept until 90 days past last access. Auto-deleted on the daily retention sweep.
- **Keep until I delete:** audio retained until user manually deletes.

Requirements:

1. Per-recording retention setting accessible in recording detail view. User can change any recording's policy at any time.
2. Default retention for new recordings is configurable in Meeting Notes spoke settings.
3. Applying a new default to existing recordings requires confirmation (may delete audio files).
4. "Last access" is defined as: playback, scrubbing, or export of the audio file. Viewing transcript or summary does NOT reset the clock. This definition is intentional and should not be softened.
5. Retention state microcopy per Addendum v2 §6.6:
   - Delete-after-transcription: "Audio was deleted after transcription. Transcript and summary are kept."
   - 90-day with audio present: "Audio retained until [date]."
   - Keep-until-delete: "Audio retained until you delete it."
   - Audio deleted per 90-day: "Audio was deleted on [date]."
   - Audio deleted by user: "Audio was deleted on [date]."
   - Audio deleted by storage cap: "Audio was deleted to free up space."

**H.2 Background retention sweep**

A background task runs daily to enforce retention policies:

1. On app launch and once per day thereafter, scan all recordings.
2. For any recording past its retention threshold (90 days since last access, or delete-after-transcription already triggered but not yet executed), delete the audio file.
3. Always preserve transcript, summary, and all metadata. Only the audio blob is deleted.
4. Update the recording's retention state and microcopy to reflect the deletion.
5. Log the deletion event to the audit log with reason ("retention_policy").

**H.3 Total storage cap with silent auto-delete**

Per Addendum v2 §6.3 — this is an **intentional product rule that must not be softened**:

1. Default cap: 2 GB across all retained audio for Meeting Notes.
2. User can configure the cap higher or lower in spoke settings.
3. When the cap is reached during recording or import, silently auto-delete oldest-first by last-access date until there's room.
4. **No pre-cap warnings. No notifications during recording. No interruption to active recording.** Silent means silent.
5. "Keep until I delete" does NOT override the cap. Documented in settings explanation copy.
6. Transcripts and summaries always preserved. Only audio blobs deleted.
7. Settings explanation copy per Addendum v2 §6.4 must be prominent and clear. Users who read it understand the rule; users who don't experience smooth behavior.

**H.4 Storage usage UI in settings**

1. Show current storage usage: "1.2 GB of 2 GB used" with a visual indicator.
2. List of recordings sorted by storage size, with "Export and delete audio" and "Delete audio" quick actions per recording.
3. Cap configurable as a settable value in the same settings section.

**H.5 Important: imported file storage consideration**

Imported audio files are not transcoded to m4a (per 2B limitation). They may be significantly larger per minute than recorded audio. The storage cap is enforced by byte count, not duration. A user importing a high-bitrate stereo file consumes more cap than an equivalent-duration recording. This is expected behavior and should not be worked around — just document it clearly in the settings explanation so users understand why imported files may fill storage faster.

---

### Workstream I: Export system

Users need to get their recordings, transcripts, and summaries out of Kraken and into other apps or people.

**I.1 Export formats**

The following formats must be supported:

- **PDF** — formatted document with recording name, date, speaker labels, full transcript, and summary. Visually clean, professional output. Free tier includes "Generated by The Kraken" footer per Addendum v2 §5.
- **Word (.docx)** — same content as PDF, editable format.
- **Plain text (.txt)** — minimal, good for pasting into other tools. No formatting.
- **Transcript only (.txt)** — transcript without summary, for users who want just the text.
- **Audio (.m4a for recordings, original format for imports)** — raw audio file if retention still has it. If audio was deleted, this option is grayed out with explanation.

**I.2 Export flow**

1. User taps Export action on a recording.
2. Format picker appears with all five options. Audio option is grayed out if audio has been deleted.
3. Multiple formats selectable at once (per Addendum v2).
4. User confirms. Files are generated in temp storage.
5. Platform share sheet opens with the files attached. User picks destination (email, Messages, Files, Drive, etc.).

**I.3 PDF formatting specifics**

- Cover area with recording name (large), meaningful date, duration.
- Optional branded header/footer for paid tier (see I.5).
- Summary section first (TL;DR, Key Points, Decisions, Action Items, Open Questions). Use clean typography, section headers distinct from body.
- Transcript section second with speaker labels and timestamps.
- Page numbers on multi-page exports.
- Free-tier footer: "Generated by The Kraken" in small text at the bottom of every page.

**I.4 Word (.docx) formatting**

- Same content structure as PDF.
- Styled using Word's built-in heading styles (Heading 1 for recording title, Heading 2 for sections) so users can re-theme easily.
- Editable — no locked content or password protection.

**I.5 Branded export settings (paid tier)**

In Meeting Notes spoke settings, paid-tier users can configure:

1. **Logo** — upload a PNG or JPG. Appears in header on PDF and Word exports.
2. **Header text** — custom text (e.g., company name, user name).
3. **Footer text** — custom text. Replaces "Generated by The Kraken."
4. **Brand color** — accent color applied to section headers and dividers in exports.

Preview of branded export shown in settings so users can verify it looks right before sending real exports.

For free-tier users, branded export settings are visible but gated behind upgrade prompt.

**I.6 Export file naming**

Files are named using the recording's display name, sanitized for filesystem safety, with appropriate extension. A recording titled "Q2 Pricing Call with Sarah" exports as:
- `Q2 Pricing Call with Sarah.pdf`
- `Q2 Pricing Call with Sarah.docx`
- `Q2 Pricing Call with Sarah — Transcript.txt`
- `Q2 Pricing Call with Sarah.m4a`

If multiple formats exported at once, they use the same base name with appropriate suffixes/extensions.

**I.7 Platform share sheet integration**

1. Android: Use standard `Intent.ACTION_SEND` with `EXTRA_STREAM` for each file. For multi-file exports, use `ACTION_SEND_MULTIPLE`.
2. Files must be written to a location the share sheet can access (typically app's cache or external-files directory via FileProvider).
3. Clean up exported temp files after the share operation completes or is cancelled.

**I.8 Paid-tier gating for branded exports**

Branded export settings (logo, header, footer, brand color) are paid-tier features. Until the user is entitled, those settings show upgrade prompts rather than actual configuration. Upgrade path uses the EntitlementService (kernel) to check status.

For this handoff, dev entitlements via `entitlements.dev.json` are sufficient for testing. Real StoreKit/Play Billing integration stays in the recovery & restoration mission (separate scope).

---

### Workstream J: AI enhancements

Incremental intelligence features that layer on top of the existing summary pipeline. None of these are foundational — they polish the product.

**J.1 AI-suggested recording names**

1. After summary generation completes, Gemma produces a suggested display name for the recording.
2. Prompt instructs Gemma to produce a short, specific, dated name. Example: "Q2 Pricing Call with Sarah" rather than "Meeting 2026-04-17" or "Meeting about business things."
3. Suggested name auto-applies as the recording's display name if the user hasn't manually renamed it.
4. If the user previously renamed it, the AI suggestion does not override.
5. Fallback if inference fails: timestamp-based default name.

**J.2 Meaningful date editing**

1. Each recording has two dates: system creation date (immutable) and meaningful date (user-editable, defaults to creation date).
2. Meaningful date is what displays in lists and exports. Creation date is visible in detail view as secondary metadata.
3. Tap the meaningful date to edit. Date picker or inline edit.
4. Useful for: "I recorded this Friday but opened the app Monday; set the meeting date to Friday."

**J.3 AI-suggested folder placement**

1. After summary generation, Gemma evaluates the summary and transcript against the user's existing folder names.
2. If one folder seems like a strong match ("this mentions Acme Corp a lot; file in your Acme Corp folder?"), surface a suggestion chip near the recording.
3. User can tap to accept (moves the recording) or dismiss.
4. **Never auto-moved.** Always user-confirmed.
5. If no clear match, no suggestion shown.
6. If recording is already in a non-Unfiled folder, no suggestion shown (user has already decided).

---

## What is explicitly OUT of scope for Handoff 3

Do not build any of the following:

- Voice input for refine or renaming (Handoff 4)
- Entity references (Handoff 4)
- Real StoreKit or Play Billing integration (separate mission: `MISSION_BRIEF_RECOVERY_AND_RESTORATION.md`)
- Onboarding or passphrase recovery (separate missions, not yet scheduled)
- Any fixes for the three v1 limitations carrying forward from 2B
- Any other spoke work

If you find yourself wanting to build any of these "while you're there," stop. Add a note for future handoff context if helpful. Do not expand scope.

---

## Architecture decisions requiring approval before implementation

Surface these in your submitted plan with specific recommendations and justifications.

### Retention decisions

1. **Background sweep scheduling.** Android WorkManager, foreground service, or in-app-launch only? Battery implications.
2. **Daily cadence enforcement.** What happens if the user doesn't open the app for a week? The sweep catches up on next launch?
3. **Cap enforcement race conditions.** If a new recording is being written when the cap is hit, how is that handled without corrupting the new file?
4. **Storage cap UI update frequency.** Live-updated as deletions happen, or refreshed on settings open?

### Export decisions

5. **PDF generation library choice.** Flutter packages available (pdf, printing, etc.) — recommend one with justification. Quality matters for professional output.
6. **Word (.docx) generation.** More constrained library ecosystem than PDF. Recommend approach.
7. **Multi-format export UI.** Picker pattern — checkboxes, sequential flow, bottom sheet?
8. **Branded export preview rendering.** How is the preview generated in settings? Real PDF thumbnail or mockup?
9. **Temp file cleanup.** Cache vs. external files directory, cleanup timing.

### AI enhancement decisions

10. **AI naming prompt design.** Show me the actual prompt text you plan to use.
11. **AI folder placement prompt design.** Actual prompt text.
12. **When do AI enhancements run?** Inline with summary generation (extends summary time) or as a separate follow-up pass (faster perceived summary, second wait)?
13. **Quality testing approach.** How will you verify AI naming produces usable names ~80% of the time, and folder suggestions are sensible rather than random?

---

## Required plan format

1. Architecture decisions — recommendation and justification for each.
2. AI naming prompt text — actual full text.
3. AI folder placement prompt text — actual full text.
4. Implementation milestones within Handoff 3 (3-4 milestones with testable states).
5. Testing plan covering retention enforcement, export quality, and AI enhancement quality.
6. Specific risks you anticipate — real risks, not boilerplate.
7. Estimated duration per milestone. Honest.

---

## Standing rules (still apply)

From `MEETING_NOTES_AGENT_HANDOFF_RULES_V2.md`:

- Library terminology in user-facing copy.
- Design tokens from home screen design — no hardcoded colors, spacing, typography.
- "Kraken" product name; "The Kraken" only in attribution contexts per Addendum v2 §5.
- No data leaves the device. No network calls for inference. No telemetry.
- Stop and flag when in doubt.

From Addendum v2:

- §5 — "The Kraken" attribution applies to PDF export footer on free tier.
- §6 — full retention behavior. Intentional product rules in §0.4 apply especially to silent auto-delete.
- §9 — multilingual support is now enabled. AI features should handle all seven languages consistently.

---

## Hard constraints

Do not:

- Begin implementation before I've reviewed and responded to your plan in writing.
- Describe any step as pre-approved or auto-approved.
- Expand scope beyond Workstreams H, I, J.
- Soften the silent auto-delete rule in Workstream H.
- Ship exports that leak audio or transcript data off-device (inference stays local, file sharing is user-initiated only).
- Accept the first working AI naming prompt as done — test against varied recordings.
- Declare completion without real-device testing evidence.

---

## Required output when Handoff 3 completes

Same 9-item format:

1. Phase Completion Checklist
2. What was built (per workstream, with specific files)
3. What was intentionally deferred
4. Tests run (unit, integration, device)
5. Known risks / incomplete items
6. Any spec conflicts found
7. Any kernel blockers discovered
8. Real-device verification status — specific Android device, OS version, tested scenarios
9. Honest assessment of whether Handoff 3 is ready for human review and whether Handoff 4 can begin cleanly

---

## Stop rules

Stop and wait for written response after:

1. Plan submission (Phase 0 gate).
2. **Each milestone.** Deliver a milestone completion report and wait for explicit acknowledgment before starting the next.
3. Handoff 3 completion — before any Handoff 4 work.

Milestone gates are not optional.
