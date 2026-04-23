# Meeting Notes Agent Handoff Rules (v2)

This file packages the universal wrapper plus all four Meeting Notes handoff prompts.

---

# Agent Handoff Wrapper — Kraken Meeting Notes Spoke

Read these documents in this exact order before doing any work:

1. `MEETING_NOTES_BUILD_PLAN.md`
2. `MEETING_NOTES_ADDENDUM_V2.md`
3. `MISSION_BRIEF_MEETING_NOTES_SPOKE.md`

## Required first step before any implementation

Before beginning any work in a given handoff, read **`MEETING_NOTES_ADDENDUM_V2.md` §0 in full**. It contains:

- §0.1 Explicit override map — which sections of the mission brief are superseded
- §0.2 How to handle conflicts outside the override map (stop and flag)
- §0.3 Standing references (Library terminology, design tokens)
- §0.4 Intentional product rules that must not be softened
- §0.5 Implementation priority tiers for background recording and force-quit recovery

These rules apply across every handoff, not just Handoff 1.

## Authority and interpretation rules

Use the documents with this precedence:

- **For sequencing, checkpoints, and handoff boundaries:** follow the **Build Plan**.
- **For overrides, clarified product decisions, and non-softenable rules:** follow the **Addendum v2**.
- **For base spoke architecture, scope, and detailed feature behavior not overridden elsewhere:** follow the **Mission Brief**.

If any conflict exists that is **not explicitly resolved** by the Addendum's override map, **stop and flag it for human review**. Do not guess, reinterpret, or silently choose one document over another.

## Standing rules that apply to every handoff

The following rules apply to all work across all handoffs. Re-verify these even when the handoff prompt doesn't explicitly name them:

- **User-facing terminology:** "library" / "libraries" in user-facing copy per `MISSION_BRIEF_RENAME_LIBRARIES.md`. Code-level `WorkspaceService` and `workspaces` table names are unchanged. "Spoke outputs" in user-facing copy are called "Drafts."
- **Visual design:** all styling comes from the home screen design tokens per `MISSION_BRIEF_HOME_SCREEN_DESIGN.md`. No hardcoded color, spacing, or typography values. Every widget imports from the token system.
- **Brand voice:** "Kraken" is the product name. "The Kraken" appears only in attribution contexts per Addendum v2 §5 — do not extend this pattern.
- **Privacy model:** no data ever leaves the device. No network calls for inference. No telemetry by default.

## Hard constraints

Do not:

- attempt the full spoke in one pass
- begin work outside the current handoff
- modify kernel services unless a true blocking issue is found and explicitly flagged
- bypass `KernelContext`
- call platform channels directly from the spoke
- soften, reinterpret, or "improve" intentional product rules from the Addendum
- implement should-have or nice-to-have background/reliability work ahead of must-have work
- refactor unrelated architecture
- add scope outside the current handoff
- introduce hardcoded styling values instead of design tokens
- reintroduce "workspace" terminology in user-facing copy

Reliability beats feature breadth.

## Required output at the end of the handoff

Stop at the end of the assigned handoff and provide:

1. **Phase Completion Checklist**
2. **What was built**
3. **What was intentionally deferred**
4. **Tests run**
5. **Known risks / incomplete items**
6. **Any spec conflicts found**
7. **Any kernel blockers discovered**
8. **What still needs real-device verification**
9. **Whether this handoff is ready for human review**

Do not continue into the next handoff without human review.

---

# Agent Handoff Prompt — Kraken Meeting Notes Spoke — Handoff 1

## Scope for this run

Execute **Handoff 1 only**. Do not begin Handoff 2, 3, or 4.

Build only the Handoff 1 scope from the Build Plan:

- Meeting Notes spoke scaffold
- `SpokeModule` implementation
- entitlement registration / dev entitlement setup
- routing and spoke visibility
- recording UI (including status text, multicolor waveform, timer)
- microphone permission handling
- free-tier 20-minute recording limit with full warning ladder at 15:00, 18:00, 19:30, 19:45, and clean stop at 20:00
- **Background recording must-haves (per Addendum v2 §12.0 priority tiers):**
  - recording continues when screen locks and when app is backgrounded
  - iOS: background audio mode configured; OS-provided microphone indicator verified
  - Android: foreground service with microphone type and persistent notification
  - persistent notification on both platforms with a Stop action that cleanly stops recording
  - tapping notification body opens the app to the active recording screen
- **Force-quit recovery must-haves (per Addendum v2 §8):**
  - incremental audio flush to disk during recording (every 3–5 seconds)
  - session marker written on recording start, updated on each flush, cleared on normal stop
  - recovery dialog on next app launch if an unclosed session marker is found
  - captured audio never lost silently
- **Five-hour safety cap (per Addendum v2 §12.4):** warnings at 4:45:00, 4:55:00, 4:59:00, and clean stop at 5:00:00 with audio preserved. Applies to all tiers.
- transcription flow after recording stops ("Transcribing on device" status copy)
- speaker labeling and rename behavior
- transcript view
- inline transcript segment editing

## Addendum rules that apply in Handoff 1

Apply these Addendum v2 sections that fall in this handoff's scope:

- §0 — all of it, including override map, intentional product rules, and priority tiers
- §1 — recording screen visual language (status text, multicolor waveform, design principle)
- §2 — expanded time-limit warning ladder
- §3 — shortened transcription status copy
- §8 — force-quit recovery (must-have items only for this handoff; nice-to-have edge-case polish deferred)
- §9 — multi-language support scoping (transcription layer; summary layer is Handoff 2's concern)
- §11 — audio encoding specification (64 kbps AAC-LC, mono, 16 kHz, m4a container)
- §12 — background recording and persistent indicators (must-have tier only per §12.0 priority rules)

## Priority guidance for background and reliability work

Per Addendum v2 §0.5 and §12.0, implement must-have items only in this handoff:

- Must-have (required for Handoff 1 completion): core background recording, persistent notification, Stop action, force-quit recovery basics, five-hour cap.
- Should-have (defer to fast-follow if not stable in this handoff): phone call auto-pause/resume, 30-minute battery disclosure.
- Nice-to-have (do not attempt in this handoff): Pause action on notification, device-specific handling for aggressive battery optimization, recovery polish for very short partial recordings.

If must-have items are unstable at the end of this handoff, stop and flag. Do not advance to should-have or nice-to-have work.

## Success definition for Handoff 1

A reviewer should be able to:

- launch Kraken
- open Meeting Notes
- record audio with visible multicolor waveform and clear status text
- lock the screen during recording and confirm recording continues
- switch to another app during recording and see the persistent notification
- tap Stop from the notification and confirm the recording ends cleanly
- force-quit the app during recording, relaunch, and see the recovery dialog with captured audio available
- observe the 20-minute warning ladder fire correctly
- confirm clean stop at the 20-minute limit with audio preserved
- stop recording cleanly via the in-app button
- wait through transcription with "Transcribing on device" status visible
- view transcript segments with speaker labels and timestamps
- rename speakers and see every segment update
- edit transcript text inline

Do not implement summary generation, organization/export, retention system expansion, entity linking, or intelligence-layer features in this handoff.

## Stop rule

When Handoff 1 is complete, stop.

---

# Agent Handoff Prompt — Kraken Meeting Notes Spoke — Handoff 2

## Preconditions

Assume Handoff 1 has already been completed and reviewed by a human.

If Handoff 1 is not stable — if recording doesn't survive the screen lock, if force-quit recovery doesn't work, if transcription is unreliable — stop and flag it rather than layering summary generation on top of unstable recording/transcription behavior.

## Scope for this run

Execute **Handoff 2 only**. Do not begin Handoff 3 or 4.

Build only the Handoff 2 scope from the Build Plan:

- default summary template (TL;DR, key points, decisions, action items, open questions)
- summary prompt implementation as a versioned file
- structured summary generation with streaming tokens
- JSON parsing and graceful fallback for malformed model output
- regenerate summary action
- refine summary action (text input from user, with voice input deferred to Handoff 4)
- summary version history (keep last 5 versions per recording; users can step back)
- summary UX on top of completed transcript flow

## Addendum rules that apply in Handoff 2

Apply these Addendum v2 sections:

- §0 — standing rules, override map, intentional product rules
- §4 — user-initiated summary generation (including §4.1 flow state impacts)
- §5 — "The Kraken" attribution scope (applies to any generated summary attribution; verify export footer copy if relevant)
- §9 — multi-language support scoping (summary layer is gated by acceptance test per §9.0; apply bright-line criteria)

## Important implementation rules

- **Summary generation is user-initiated.** Do not auto-start summary generation after transcription.
- **Transcript must be reviewable and editable before summary generation.** The completion state after transcription is "transcript ready, awaiting user action."
- **"Generate summary" button is always present** after transcription completes. Becomes "Regenerate" after first generation.
- Do not assume the original mission brief's older summary flow where it conflicts with Addendum v2 §4.
- Keep summary generation grounded in the transcript. Favor fidelity over polish.
- Per Addendum v2 §9.0, apply the acceptance test to each language. English must pass. Any other language that fails has its summary generation held for v1.1 — do not ship with obviously weak summaries.

## Success definition for Handoff 2

A reviewer should be able to:

- open a completed transcript
- edit the transcript segments freely
- tap **Generate summary** and watch tokens stream in
- receive a structured summary with TL;DR, key points, decisions, action items, and open questions
- tap Regenerate and get a new summary reflecting any transcript edits
- tap Refine, enter an adjustment instruction, and receive a revised summary
- step backward and forward through summary versions (up to 5 kept)
- confirm that if Gemma produces malformed output, the fallback UX is clear rather than showing a raw error

Do not implement organization/folders, retention expansion, export system, voice input for refinement, or entity linking in this handoff.

## Stop rule

When Handoff 2 is complete, stop.

---

# Agent Handoff Prompt — Kraken Meeting Notes Spoke — Handoff 3

## Preconditions

Assume Handoffs 1 and 2 have already been completed and reviewed.

If the recording/transcription/summary flow is not stable, stop and flag it rather than layering organization and retention behavior on top.

## Scope for this run

Execute **Handoff 3 only**. Do not begin Handoff 4.

Build only the Handoff 3 scope from the Build Plan:

- AI-suggested display names for recordings (with fallback to timestamp if inference fails)
- inline renaming from any surface where the name appears
- meaningful-date editing separate from system creation dates
- folder creation, renaming, deletion, and moving recordings between folders
- AI-suggested folder assignment (user-confirmed, never auto-moved)
- list view with sort (recent, oldest, A–Z, Z–A) and filter (folder, date range, entity)
- search within Meeting Notes (names, summary content, transcript content)
- retention settings UI and per-recording retention state
- retention enforcement behavior: 90-day auto-delete, delete-after-transcription, keep-until-delete
- **total audio storage cap with silent auto-delete** per Addendum v2 §6.3 (this is an intentional product rule, do not soften)
- export system: PDF, Word (.docx), plain text, audio, transcript-only, multi-format selection
- branded export settings for paid tier (logo, header, footer, brand color)

## Addendum rules that apply in Handoff 3

Apply these Addendum v2 sections:

- §0 — standing rules, override map, intentional product rules (especially silent auto-delete)
- §5 — "The Kraken" attribution (export footer: "Generated by The Kraken" on free tier, removed on paid tier)
- §6 — full retention and storage cap behavior, including §6.4 settings explanation copy and §6.6 microcopy

## Important implementation rules

- **Silent auto-delete is an intentional product decision.** Do not add pre-cap warnings. Do not add notifications during recording when the cap is hit. Do not let "keep until I delete" override the cap. If you believe these rules conflict with implementation constraints, stop and flag rather than modifying the rules.
- **Transcripts and summaries are always preserved** even when their associated audio is auto-deleted. Storage cap enforcement affects audio blobs only.
- **Settings explanation copy must be prominent and clear** per Addendum v2 §6.4. Users who read it understand the rule; users who don't experience smooth behavior.
- **Retention microcopy must distinguish deletion causes** per Addendum v2 §6.6: 90-day auto-delete, user deletion, storage cap deletion, delete-after-transcription all have distinct microcopy.
- **Exports go through the platform share sheet.** Do not build custom export destinations.

## Success definition for Handoff 3

A reviewer should be able to:

- see sensible AI-generated recording names (should be usable ~80% of the time without editing)
- rename recordings, folders, and speakers inline from any surface
- edit meaningful dates separately from creation dates
- create, rename, delete, and reorganize folders
- accept or reject AI-suggested folder assignments (never auto-moved)
- sort, filter, and search a library of 20+ test recordings
- configure retention settings per-recording and set spoke-level defaults
- see correct retention-state microcopy reflecting actual state
- export PDF, Word, plain text, audio, transcript-only — individually or in multi-format selections
- confirm "Generated by The Kraken" footer on free-tier PDF exports
- verify branded export behavior (logo, header, footer, brand color) for paid tier
- see storage-cap settings with current usage and clear explanation copy
- trigger storage-cap behavior (e.g., by lowering the cap below current usage) and verify silent auto-delete preserves transcripts and summaries

Do not implement voice input for refinement/renaming or entity reference intelligence in this handoff.

## Stop rule

When Handoff 3 is complete, stop.

---

# Agent Handoff Prompt — Kraken Meeting Notes Spoke — Handoff 4

## Preconditions

Assume Handoffs 1, 2, and 3 have already been completed and reviewed.

If core recording, summary, retention, or export behavior is unstable, stop and flag it rather than adding the intelligence layer.

## Scope for this run

Execute **Handoff 4 only**.

Build only the Handoff 4 scope from the Build Plan:

- voice input for summary refinement (mic button in refine text field)
- voice input for inline renaming of recordings, folders, and speakers
- AI-inferred entity references after summary generation (people, companies, topics)
- fuzzy matching against the kernel's shared entity store
- create-new-entity confirmation flow (user-confirmed, never silent)
- entity reference view within a recording's detail screen
- manual add/remove/merge of entity references

## Addendum rules that apply in Handoff 4

Apply these Addendum v2 sections:

- §0 — standing rules, intentional product rules (still apply at the intelligence layer)
- §9 — multi-language support (ensure voice input works for all shipped languages)
- Any late-stage product rules relevant to inference behavior or export attribution that apply when intelligence-layer features produce user-visible output

## Important implementation rules

- **This handoff adds intelligence on top of an already-working product.** Do not destabilize the spoke's core workflow. If adding entity references breaks summary generation, stop and flag rather than patching the break.
- **Shared-entity behavior must remain user-controlled and reviewable.** No invisible or surprising data-linking behavior.
- **Fuzzy matching prefers asking the user over auto-linking** when confidence is ambiguous. False links ("this Mike is that Mike") damage trust more than asking for confirmation.
- **Entity creation requires explicit user confirmation.** A chip offering "Create new contact 'Sarah Chen'?" is acceptable; silently creating entities is not.
- **Voice input uses the kernel's `VoiceInputService`.** Do not call platform speech APIs directly from the spoke.

## Success definition for Handoff 4

A reviewer should be able to:

- tap the mic in the refine field, speak a refinement instruction, and see it transcribed and applied to summary generation
- use voice input to rename a recording, folder, or speaker
- open a completed recording and see inferred entity chips (people, companies, topics)
- confirm that entities with clear matches are linked to existing shared entities automatically
- confirm that ambiguous matches surface a user prompt rather than auto-linking
- accept or reject "Create new contact?" prompts for new entities
- navigate from an entity chip to the shared entity page and see other recordings that reference it
- manually add an entity reference the AI missed
- manually remove an entity reference the AI got wrong
- merge two duplicate entities and confirm all cross-references update correctly

This handoff completes the v1 Meeting Notes spoke as defined by the current document set.

## Stop rule

When Handoff 4 is complete, stop and provide final readiness status for the full Meeting Notes spoke.
