# Handoff 2A Kickoff — Kraken Meeting Notes Spoke

## PHASE 0: PLAN SUBMISSION ONLY

**This run is plan-first only. Do not write any implementation code until I have reviewed and responded in writing to your submitted plan.**

- Phase 0 of this handoff is implementation plan submission.
- No code changes, no kernel modifications, no file edits beyond the plan document itself.
- If something about the scope is unclear, stop and flag — do not proceed by interpretation.
- There is no "automatic approval" for any step of this handoff. Any claim that a step was pre-approved will be treated as a spec violation.

Only after I respond with explicit written approval of your plan may you proceed to implementation.

---

## Handoff 1 Status: Complete

Verified on real Android device: recording pipeline works end-to-end, survives screen lock and spoke navigation, force-quit recovery functional, kernel architecture sound.

## Why Handoff 2 was split into 2A and 2B

The original Handoff 2 scope grew large enough to risk scope failure. Splitting into two handoffs with a real verification checkpoint between them:

- **Handoff 2A (this document):** transcription foundation. Whisper integration, progress visibility, background transcription, deferred transcription.
- **Handoff 2B (later, separate document):** import, folder organization, summary generation.

2A is a coherent technical milestone — getting the transcription pipeline solid. 2B layers product features on top of a working foundation. Between them, you verify that real transcription actually works end-to-end with real audio. This checkpoint protects 2B from building on top of problems in 2A.

Do not attempt any Handoff 2B scope in this handoff.

---

## Handoff 2A Scope

Execute **Handoff 2A only**. Four sub-workstreams. Do not expand beyond what is listed.

### Workstream A: Whisper integration

Replace the current transcription stub with real on-device transcription.

1. Integrate a Whisper-family model appropriate for mobile on-device inference.
2. Handle model distribution (bundled vs. first-run download — decision surfaced in plan per §Architecture Decisions below).
3. Wire transcription to Meeting Notes so `Stop recording → transcribe → see transcript` flows with real audio producing real text.
4. Support seven languages per Addendum v2 §9: English, Spanish, French, Portuguese, Chinese, Japanese, Korean. Automatic language detection.
5. Display detected language in transcript view per Addendum v2 §9.3.
6. Handle transcription progress, completion, and failure states.

### Workstream B: Transcription progress visibility

Users must never be uncertain whether transcription is running or whether the app is frozen.

1. Progress bar tied to actual Whisper chunk processing. Not an indeterminate spinner.
2. Time estimate alongside progress: "About 90 seconds remaining."
3. Err on the high side — conservative estimates so users are pleasantly surprised rather than frustrated.
4. Status copy stays minimal per Addendum v2 §3: "Transcribing on device."
5. Progress UI surfaces in:
   - Meeting Notes transcript view while user is viewing it
   - Persistent in-app banner (reuse the recording banner component) on other spokes and home screen
   - Platform notification, so users see progress with app backgrounded

6. **Banner behavior during queueing.** The persistent banner reflects the full state of transcription-related work, not just the active job:
   - **Active transcription, nothing queued:** "Transcribing — 47% · about 90 sec remaining"
   - **Active transcription with queued items behind it:** "Transcribing — 47% · 2 more queued" or similar. User knows additional work is waiting.
   - **Queued items only, nothing active yet:** "3 recordings queued — starting shortly" or similar. Occurs briefly between finishing one transcription and starting the next.
   - **All complete:** banner dismisses.
   - Tapping the banner in any of these states returns the user to Meeting Notes, where the list view shows each recording's specific state (Transcribing, Queued position N, etc.).

   Same queue information surfaces in the platform notification when the app is backgrounded.

### Workstream C: Background transcription (kernel-owned task)

Precise definition of "background" for this handoff — resolve ambiguity in the spec:

1. **Continues while user navigates inside the app** (between spokes, to home, to settings). REQUIRED.
2. **Continues when the app is briefly backgrounded** (user checks a message, comes back). REQUIRED.
3. **Continues when the app is fully backgrounded for extended periods** (20+ minutes). REQUIRED for Android via foreground service; iOS best-effort with background audio mode.
4. **Survives OS suspension under memory pressure.** NOT REQUIRED for v1. If the OS kills the app, the transcription job is lost and the user re-initiates on next launch (audio is preserved per Addendum v2 §8).

Implementation requirements:

1. Transcription runs in a kernel-level `TranscriptionService` (parallel to AudioService pattern from Handoff 1). Meeting Notes is a client, not an owner.
2. Navigating between spokes does not tear down transcription.
3. Concurrent recording allowed while transcription runs. New recording's transcription queues behind current one.
4. Force-quit during transcription: audio preserved, transcription progress discarded, state returns to "Needs transcription" on relaunch.
5. Transcription failure: clear error state, retry action, audio preserved. Never lose user data.
6. Transcription completion while user is away from Meeting Notes: banner updates, optional platform notification.

### Workstream D: Deferred transcription (always ask)

Users must be able to defer transcription to a convenient time.

1. **Default behavior: always ask.** When the user taps Stop on any recording, regardless of length, present: "Transcribe now (about [Y] minutes) or transcribe later?" No length thresholds.
2. User setting overrides default:
   - "Transcribe automatically" — always auto-transcribe, no prompt.
   - "Ask me each time" — always show prompt. **Default.**
   - "Wait for me to start" — never auto-transcribe.
3. Untranscribed recordings appear in the main Meeting Notes list with clear "Needs transcription" state chip.
4. Tapping Transcribe on an untranscribed recording starts transcription using the same pipeline.
5. Batch transcription: "Transcribe all" action queues multiple recordings sequentially.
6. State labels used consistently throughout the app. At any point a recording is in exactly one state:
   - Recording (actively capturing)
   - Needs transcription (audio ready, no transcript yet)
   - Queued for transcription (will start when earlier jobs finish)
   - Transcribing (Whisper processing)
   - Transcribed (transcript available, no summary yet)
   - Transcription failed (retry available)

(The additional state "Summarized" from the original document is deferred to Handoff 2B where summary generation lives.)

---

## What is explicitly OUT of scope for 2A

Do not build any of the following in this handoff:

- Summary generation (Workstream B from original doc)
- Audio import (Workstream A.4 from original doc)
- Folder organization (Workstream A.5 from original doc)
- Transcript playback widget
- Export formats (PDF, DOCX, etc.)
- Any Handoff 3 or 4 scope

If you find yourself wanting to build any of these "while you're there," stop. Add a note to your report for Handoff 2B context if helpful. Do not expand this handoff.

---

## Architecture decisions requiring approval before implementation

These decisions must be surfaced in your submitted plan with specific recommendations and justifications. Each will be reviewed and responded to individually before implementation begins.

### Whisper stack decisions

1. **Implementation choice.** whisper.cpp, WhisperKit (iOS-native), platform channel to native library, or Flutter package? Recommend one with reasoning — performance, maintenance, platform compatibility.
2. **Model size.** Tiny / base / small / medium. Multilingual required (seven-language spec). Justify against quality, size, and speed. English-only models are insufficient.
3. **Model distribution.** Bundled in app (larger install, offline from first launch, clean privacy story) or first-run download (smaller install, one-time network). Recommend one.
4. **Model storage on device.** Path, integrity verification, update strategy.
5. **Model lifecycle.** When loaded? On app launch, first transcription, on-demand? When unloaded? Memory implications.
6. **First-run warmup handling.** Model loading takes time. How does the UX account for this? Progress UI must include warmup time in its estimate for the first transcription.

### Transcription architecture decisions

7. **TranscriptionService design.** Kernel-level service paralleling AudioService. Interface, state management, observability.
8. **Progress event mechanism.** Does your chosen Whisper implementation expose chunk-level progress events? If yes, wire them to the progress UI. If no, how do you communicate real progress without fabricating it?
9. **Language detection strategy.** Whisper built-in detection, separate detection pass, user override. How is detected language exposed to the UI?
10. **Queue implementation.** Data structure, persistence across app restarts, cancellation.
11. **Concurrency policy.** Confirm only one transcription runs at a time. How is the queue managed?
12. **Failure recovery.** What states are persisted to disk? What is recoverable on relaunch?

### Platform behavior decisions

13. **Android foreground service strategy for transcription.** The AudioService recording pattern uses a foreground service. Does transcription use the same service, a separate one, or run inside the recording service? Platform implications.
14. **iOS background behavior.** Background audio mode was configured for recording. Does transcription need additional capability, or does recording's mode cover it?
15. **Battery impact estimates.** Whisper inference is CPU-heavy. What's the expected battery cost of a 10-minute transcription? Does this warrant user-facing disclosure?

### Edge case decisions

16. **Transcription cancellation.** Can the user cancel an in-progress transcription? If yes, how? If no, why not?
17. **Very long recordings at the 5-hour cap.** Does transcription handle 5-hour audio cleanly, or does it need chunking strategy?

---

## Required plan format

Your submitted plan should include, in this order:

1. **Architecture decisions.** Your recommendation and justification for each of the 17 items above. Not more than a few sentences per item.
2. **Default summary prompt preview.** Not in scope for this handoff, but if you already have an idea for the prompt, include it so I can comment early.  (DEFERRED — this belongs in Handoff 2B. Skip.)
3. **Implementation milestones within 2A.** Propose 3-4 milestones that let me verify progress incrementally rather than at the end. Each should produce a testable state.
4. **Testing plan.** How you'll verify Whisper quality, progress UX, background behavior, and deferred transcription on real Android device.
5. **Specific risks you anticipate.** Not boilerplate risks — real risks you see in this scope given the codebase.
6. **Estimated duration per milestone.** Honest estimates, not aspirations.

The plan is for my review. Do not submit code until I have responded with explicit written approval.

---

## Standing rules (reminder, all still apply)

From `MEETING_NOTES_AGENT_HANDOFF_RULES_V2.md`:

- Library terminology in user-facing copy.
- Design tokens from home screen design — no hardcoded colors, spacing, typography.
- "Kraken" is the product name; "The Kraken" appears only in attribution contexts per Addendum v2 §5.
- No data leaves the device. No network calls for inference. No telemetry.
- Stop and flag when in doubt rather than proceeding by interpretation.

From Addendum v2:

- §3 — transcription copy is "Transcribing on device."
- §9 — multi-language support scope and acceptance criteria.
- §11 — audio encoding specification (64 kbps AAC-LC mono 16 kHz m4a) already enforced.
- §12 — background recording infrastructure already in place from Handoff 1.

Intentional product rules from Addendum v2 §0.4 continue to apply. Do not soften.

---

## Hard constraints

Do not:

- Begin implementation before I've reviewed and responded to your plan in writing.
- Describe any step as pre-approved or auto-approved.
- Expand scope beyond Workstreams A through D above.
- Ship a Whisper integration that transmits audio data off-device. All inference is local.
- Soften, reinterpret, or skip intentional product rules.
- Declare completion without real-device testing evidence.

---

## Required output when Handoff 2A completes

Same 9-item format:

1. Phase Completion Checklist
2. What was built (per workstream, with specific files)
3. What was intentionally deferred (including 2B scope)
4. Tests run (unit, integration, device)
5. Known risks / incomplete items
6. Any spec conflicts found
7. Any kernel blockers discovered
8. Real-device verification status — specific Android device, OS version, tested scenarios
9. Honest assessment of whether Handoff 2A is ready for human review and whether 2B can begin cleanly

---

## Stop rules

Stop and wait for my written response after:

1. Submitting the implementation plan (before any code) — this is Phase 0's gate.
2. Completing each milestone proposed in your plan (before starting the next).
3. Completing Handoff 2A (before proceeding to 2B).
