# Handoff 2B Kickoff — Kraken Meeting Notes Spoke (HOLD UNTIL 2A COMPLETES)

**DO NOT hand this off until Handoff 2A has completed and verified on real device. This document exists so scope is clear when 2A finishes, not to be worked on in parallel.**

---

## PHASE 0: PLAN SUBMISSION ONLY

**This run is plan-first only. Do not write any implementation code until I have reviewed and responded in writing to your submitted plan.**

Same Phase 0 rules as 2A apply.

---

## Preconditions

- Handoff 2A is complete and verified on real Android device.
- Real Whisper transcription works end-to-end: record → transcribe → see real transcript.
- TranscriptionService (kernel-level) is functional and stable.
- Progress visibility, background transcription, and deferred transcription all work as specified.

If any of these are unstable, stop and flag rather than layering 2B features on top of instability.

---

## MILESTONE GATING

Because 2B contains three substantial workstreams, implementation must proceed in discrete milestones with review gates between each. Your submitted plan must propose 3-4 milestones. Each milestone must produce a testable state I can verify on real device before the next milestone begins.

**Do not deliver 2B as a single end-of-handoff drop.** That would eliminate the ability to catch problems before they compound across workstreams.

After each milestone:

1. Stop.
2. Provide a milestone completion report (a condensed version of the 9-item output format, scoped to what the milestone covered).
3. Wait for my written acknowledgment before beginning the next milestone.

There is no automatic progression between milestones. The review gate at each milestone is as real as the Phase 0 plan gate.

---

## Handoff 2B Scope

Execute **Handoff 2B only**. Three sub-workstreams. Do not expand.

### Workstream ordering and dependencies

The three workstreams have real dependencies. Build them in this order to avoid rework:

1. **Workstream F (Folders) first.** Folders are a prerequisite for E because import needs a folder destination picker. They're also needed for any state UI that groups recordings. Do not begin E or G until F's data model and basic folder operations (create, list, pick destination) are working.

2. **Workstream E (Import) second, after F is functional.** Import's destination picker uses real folders created in F. Building E before F would either hardcode "Unfiled" as the only destination (punting the problem) or build a throwaway picker UI that has to be rebuilt later.

3. **Workstream G (Summary generation) can start in parallel with E once F is done.** G depends on the transcription state machine from 2A and doesn't meaningfully depend on folders or import. If you have capacity to parallelize, E and G together after F is fine. If sequential execution is cleaner, F → E → G works too.

Do not start G before F. Summary generation UI has to exist within the folder-organized navigation structure, and building it against a placeholder structure will force rework.

If the agent proposes a different ordering with justification, stop and flag for review rather than silently reordering.

### Workstream F: Folder organization

Folders are prominent in Meeting Notes' primary navigation. Users manage larger libraries by organizing into folders.

**Data model confirmed with user:** Folders are organizational containers. Recordings are atomic units bundling their audio + transcript + summary. Each recording lives in exactly one folder.

**Folder hierarchy:**

1. Flat in v1. No nested folders.
2. Default "Unfiled" folder exists and cannot be deleted. May be renamed.
3. User can create, rename, delete custom folders freely.
4. Deleting a folder with recordings: prompt to move to another folder or delete everything. Never silent data loss.

**Main Meeting Notes screen:**

1. Organized around folders, with recording counts per folder.
2. "Unfiled" pinned at top or bottom for easy access.
3. Tapping a folder opens it to see recordings inside.
4. Search and sort work across entire library or within a specific folder.

**Color-coded folder states (use design tokens, not hardcoded colors):**

1. **Neutral (text_muted or similar):** all recordings transcribed and summarized. Nothing needs attention.
2. **Pending (accent color):** one or more recordings inside need transcription. Draws user's eye to folders with incomplete work.
3. **Attention (danger color):** one or more recordings inside have "Transcription failed" state. Distinct from pending — needs action, not waiting.

Color states update reactively as child recording states change.

**Folder creation:**

1. "New folder" action on main screen. Prompts for name.
2. Voice input for folder naming — defer to Handoff 4.

**Moving recordings:**

1. From detail view: "Move to…" action.
2. From list view: long-press or swipe reveals move action.
3. Batch move: select multiple recordings, move together.

**AI-suggested folder placement:** deferred to Handoff 3. All new recordings in 2B land in "Unfiled" by default.

**Folder sort options:** name (A-Z, Z-A), recent activity, recording count.

### Workstream E: Audio import

Users may have audio from external sources — hardware voice recorders, conference systems, recordings received from colleagues, archives. Meeting Notes must import these as first-class recordings.

**Precondition:** Workstream F is functional. Folder data model exists, destination picker UI can use real folders.

**Entry points (three ways to import, one destination):**

1. "Import audio" action on the Meeting Notes main screen.
2. "Import audio" action on the Home screen (kernel-level, top-level visibility).
3. Platform share sheet integration — sharing an audio file from Files, email, or cloud storage offers Kraken as a destination.

All three entry points lead to the same import flow. Imports are first-class recordings regardless of entry point.

**Import flow:**

1. User initiates import.
2. File picker or share intent provides the audio file.
3. Folder destination prompt: existing folder, create new folder, or Unfiled. Uses the real folder system from Workstream F. Remember last-used destination per session for batch imports.
4. Transcoding progress screen briefly shown.
5. Imported file appears in chosen folder with state "Needs transcription."

**Format support:**

- Accepted: m4a, mp3, wav, aac, flac, ogg, mp4 (audio track extracted), mov (audio track extracted).
- Rejected: formats that cannot be processed. Clear error message directing user to convert.
- Transcoding: all imports become standard m4a per Addendum v2 §11 (64 kbps AAC-LC, mono, 16 kHz).

**Limits:**

- Max file size: 500 MB.
- Max duration: 5 hours (matches Addendum v2 §12.4 recording safety cap).
- Files over either limit: rejected on import with clear message.

**Multi-channel:** stereo files downmixed to mono during transcoding. Multi-track files use first audio track with one-time notice to user.

**Metadata preservation:**

- Meaningful date: from file metadata if present, else import date.
- Display name: filename minus extension, user can rename.
- Duration: derived from file.

**Provenance indicator:** recording detail view shows "Imported from [filename]" for imported files.

**Privacy:** read from source, transcode, store encrypted. Original file not modified or referenced after. No network activity during import.

**Use same deferred transcription model from 2A:** imports default to "Needs transcription" state. User decides when to transcribe.

### Workstream G: Summary generation

The AI summary layer on top of transcripts.

**Core flow:**

1. Default summary template: TL;DR, key points, decisions, action items, open questions.
2. Summary prompt as a versioned file in the repo so prompts can iterate without code changes.
3. Streaming token-by-token display as output arrives from Gemma.
4. JSON parsing with graceful fallback for malformed model output. Users see clean UX, not raw errors.
5. Regenerate summary action.
6. Refine summary action (text input; voice input for refinement deferred to Handoff 4).
7. Summary version history: last 5 versions per recording, user can step backward/forward.

**Addendum v2 rules:**

- §0 — standing rules, intentional product rules.
- §4 — user-initiated summary generation. Do not auto-start after transcription.
- §4.1 — flow state impacts. Transcript review is the completion state after transcription.
- §5 — "The Kraken" attribution applies to any generated summary attribution (e.g., export footers, deferred to Handoff 3).
- §9.0 — multi-language acceptance criteria. English must pass. Other languages either pass acceptance test or hold summary for v1.1.

**Prompt engineering expectation:** ship with a single well-tested prompt. Test against at least 5 realistic meeting transcripts of varied types (sales call, standup, 1-on-1, interview, support call). If quality is weak on any, iterate before completion. Do not accept the first working version.

**State transitions:** when transcription completes, state moves to "Transcribed." When user taps Generate Summary, state becomes "Summarizing." When complete, state becomes "Summarized." These integrate with the state system from 2A's Workstream D.

---

## Architecture decisions requiring approval before implementation

Submit recommendations in your plan.

### Import decisions

1. **Transcoding implementation.** ffmpeg-mobile, Flutter package, native platform APIs? Justify.
2. **Share sheet integration strategy.** Platform-specific UI, receive handler, error handling for failed shares.
3. **Folder destination UI pattern.** Sheet, modal, inline picker?
4. **Rejecting files over limits.** Pre-transcode check (fast) or during transcode (may fail later)?

### Folder decisions

5. **Folder data storage.** Where do folders live? Vault table, spoke storage, kernel-level?
6. **Folder-to-recording relationship.** How is "recording belongs to folder X" stored and queried efficiently for color state?
7. **Color state computation.** Computed on demand or cached per folder? Invalidation strategy.

### Summary decisions

8. **Default prompt text.** Show me the actual prompt text you plan to use. Not a description — the full text.
9. **Streaming token UI implementation.** How does the UI re-render progressively without flickering?
10. **JSON schema for structured output.** Exact shape, handling of empty sections (no decisions made, no action items).
11. **Malformed output recovery.** Reprompt, partial parse, raw text fallback?
12. **Summary storage.** Where do summary versions live? Vault, spoke storage, recording-attached?

---

## Required plan format

1. Architecture decisions — recommendation and justification for each item above.
2. Default summary prompt — actual full text, not a description.
3. Implementation milestones within 2B. Propose 3-4 milestones with testable states.
4. Testing plan — import, folder states, summary quality across realistic transcripts.
5. Specific risks.
6. Estimated duration per milestone. Honest.

---

## Hard constraints

Do not:

- Begin implementation before written plan approval.
- Describe any step as pre-approved or auto-approved.
- Expand scope beyond Workstreams E, F, G.
- Ship summaries that transmit transcript data off-device.
- Accept the first working summary prompt as done — iterate against varied transcripts.
- Soften or skip intentional product rules.
- Declare completion without real-device verification.

---

## Required output when Handoff 2B completes

Same 9-item format.

---

## Stop rules

Stop and wait for written response after:

1. Plan submission (Phase 0 gate).
2. **Each milestone proposed in your plan.** Deliver a milestone completion report and wait for explicit written acknowledgment before starting the next milestone.
3. Handoff 2B completion — before any Handoff 3 work.

Milestone gates are not optional. Proceeding past a milestone without acknowledgment is the same spec violation as proceeding past the Phase 0 plan gate.

---

## Relationship to other handoffs

- **Builds on 2A:** uses TranscriptionService, state machine, deferred transcription, progress system.
- **Sets up for Handoff 3:** AI-suggested folder placement, rich export formats, entity references.
- **Sets up for Handoff 4:** voice input for refinement and folder naming.

Handoff 2B is the "Meeting Notes feels like a real product" milestone. After 2B, a user can record a meeting, transcribe it, organize it into folders, import external audio, and get AI-generated summaries. That's the v1 core value proposition.
