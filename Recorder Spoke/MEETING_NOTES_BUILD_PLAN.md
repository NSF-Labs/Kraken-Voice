# Build Plan: Meeting Notes Spoke

## Purpose of This Document

This is the **plan for building** the Meeting Notes spoke — the sequence, the checkpoints, what to test at each stage, what to hand to the agent when. It sits above the detailed mission brief (`MISSION_BRIEF_MEETING_NOTES_SPOKE.md`), which is the full specification.

Plan first, brief second. Read this document to understand the shape of the build; hand the brief (or pieces of it) to the agent to do the work.

## Prerequisites (Confirm Before Starting)

Before beginning Meeting Notes, confirm each of these is true. If any are not, complete them first — Meeting Notes depends on all of them.

1. **Library rename has shipped** (`MISSION_BRIEF_RENAME_LIBRARIES.md`). All user-facing "workspace" strings say "library." Code-level `WorkspaceService` is unchanged.
2. **Home screen design tokens are in place** (`MISSION_BRIEF_HOME_SCREEN_DESIGN.md`). Colors, typography, spacing, radii are defined in a single file and every shell widget imports from it.
3. **Device test fixes are applied** (`MISSION_BRIEF_DEVICE_TEST_FIXES.md`). Activity feed filters by user-visibility, snake_case strings are purged, skip button on the airplane mode demo works.
4. **Passphrase recovery is shipped** (`MISSION_BRIEF_RECOVERY_AND_RESTORATION.md`). Users can generate recovery codes and restore purchases.
5. **Audio service is solid**. Real Faster-Whisper integration works reliably end-to-end, not just on stub data. This is the biggest prerequisite — Meeting Notes will stress-test the audio pipeline harder than any hub phase did.
6. **Voice input service works** (`MISSION_BRIEF_VOICE_INPUT_SERVICE.md`). Mock spoke's voice test button produces transcribed text successfully.
7. **Inference service handles cancellation cleanly**. If a user navigates away mid-summary, the inference job gets cancelled cleanly. Test this specifically before starting Meeting Notes.

If you're missing any of these, address them first. Building Meeting Notes on top of soft foundations is how small bugs become architectural headaches.

Also verify the existing `MISSION_BRIEF_MEETING_NOTES_SPOKE.md` has been updated to use Library terminology and reference the design tokens. If not, request an update before handoff (I can draft the update as a small patch mission if needed).

## The Build, in Four Handoffs

Meeting Notes is too large for a single agent cycle. The mission brief has 11 phases and covers roughly 3-4 weeks of agent work. Breaking it into four handoffs gives you checkpoints where real-device testing can catch issues before they compound.

Each handoff produces a working, testable state. You should not move to the next handoff until the previous one passes real-device testing on both iOS and Android.

---

### Handoff 1: Skeleton and Recording (Mission Brief Phases 1-3)

**What the agent builds:**
- Spoke scaffold: SpokeModule implementation, entitlement registration in `entitlements.dev.json`, routing so Meeting Notes appears as a spoke card on the home screen.
- Recording UI: tap to record, see live timer and audio level, tap to stop.
- Free-tier 20-minute limit with proper warnings at 18:00 and 19:30, graceful stop at 20:00 with captured audio retained.
- Microphone permission handling on first launch.
- Transcription after recording stops, with progress indicator.
- Speaker labeling (Speaker 1, Speaker 2 auto-assigned) with inline rename capability.
- Transcript view: scrollable list of segments with speaker label + timestamp + text.
- Inline segment editing to correct transcription errors.

**What the agent does NOT build yet:**
- Summary generation (handoff 2).
- Artifact organization (handoff 3).
- Retention, export, voice refinement (handoff 3 or 4).

**What "done" looks like for this handoff:**
You tap Record, have a conversation for 3 minutes, tap Stop. You see a transcript with speakers labeled and editable segments. You can rename "Speaker 1" to "Sarah" and watch every Sarah segment update. You can tap a segment and fix a transcription error. You hit the 20-minute limit on a separate test recording and confirm the warnings fire correctly and the audio is preserved when recording stops.

**Real-device testing before moving on:**
- Fresh install, complete onboarding, tap Meeting Notes.
- Record three recordings of varying length (30s, 5min, 22min to hit the limit).
- Rename speakers, edit transcript segments.
- Force-quit mid-recording, reopen — confirm state handled gracefully (either recovered or cleanly abandoned with user notified).
- Lock phone during recording, unlock — confirm recording continued.
- Low-battery scenario: record with battery under 10%. Confirm no surprises.
- Background the app during transcription — confirm it completes when foregrounded.

**Common issues to watch for:**
- Transcription latency surprising users (a 10-minute recording transcribing for 2 minutes is fine if the UI tells the user; silent 2-minute wait is bad).
- Speaker labels misbehaving when diarization quality is poor — make sure fallback to "Speaker" (no number) is graceful.
- Audio level visualization flickering or lagging the UI.
- The 20-minute limit warning being more jarring than informative — this is freemium UX that matters a lot.

---

### Handoff 2: Summary Generation (Mission Brief Phase 4)

**What the agent builds:**
- Default summary template producing TL;DR, key points, decisions, action items, open questions.
- Summary prompt (stored as a versioned file so it can be iterated) that instructs Gemma 4 to produce structured JSON output.
- Streaming summary generation: tokens appear as they generate, not after full completion.
- JSON parsing with graceful fallback if the model produces malformed output.
- Regenerate summary action (run the summary again on the current transcript).
- Refine summary action (user provides a text instruction to adjust the summary; model produces a revised version).
- Version history for summaries (keep last 5 versions per recording; users can step back).

**What the agent does NOT build yet:**
- AI-suggested recording names (handoff 3).
- Custom templates for paid tier (out of v1 scope per the brief).
- Audio retention logic (handoff 4).

**What "done" looks like for this handoff:**
From a completed recording with transcript, tap Generate Summary. Watch tokens stream in. See a structured summary with clearly formatted sections — TL;DR, key points, decisions, action items, open questions. Edit a segment in the transcript, tap Regenerate Summary, see a new summary reflecting the correction. Use the Refine action to ask "make the action items more specific" — see a new summary version. Step back to the prior version.

**Real-device testing before moving on:**
- Generate summaries for recordings of 1 minute, 10 minutes, and 20 minutes. Compare quality.
- Test with recordings that have little structure (casual conversation) vs. recordings with clear structure (meeting with agenda). The summary should handle both.
- Test the malformed-output fallback by temporarily giving Gemma a prompt that's likely to break — confirm the fallback UX is clear rather than showing a raw error.
- Refine with ambiguous requests ("make it better") and specific requests ("remove the open questions section"). Both should produce sensible output.
- Step back and forward through version history.

**This is where prompt engineering matters most.** The default summary template is the single highest-leverage piece of Meeting Notes. Budget real time for iteration:

- Record 5-10 test meetings of different types (sales call, team standup, 1-on-1, interview, phone support call).
- Review each summary critically. Does it capture what actually happened?
- Iterate on the prompt until summaries are consistently useful.
- The agent will likely produce a working but mediocre prompt on first attempt. Expect to spend 2-3 iteration cycles getting it right.

**Common issues to watch for:**
- Model fabricating action items that weren't in the transcript (hallucination).
- Model attributing statements to the wrong speaker.
- Summaries that are too short or too long — find the right density.
- JSON parsing failures more common than expected.
- Streaming tokens appearing too slowly and feeling laggy (usually a token batching issue).

---

### Handoff 3: Organization and Retention (Mission Brief Phases 5-7)

**What the agent builds:**
- AI-suggested display names for each recording (short, specific, dated). Fallback to timestamp if inference fails.
- Inline renaming from any surface where the name appears.
- Meaningful-date editing separate from system dates.
- Folder creation, renaming, deletion within Meeting Notes.
- Recording organization: drag to folder, "Move to…" action.
- AI-suggested folder assignment for new recordings (with user confirmation, never auto-move).
- List view with sort (recent/oldest/A-Z/Z-A) and filter (folder, date range).
- Search within Meeting Notes (names, summary content, transcript).
- Audio retention settings: delete after transcription, 90-day default, keep-until-delete. Per-recording and per-spoke default.
- Background retention task: on launch and once daily, identify and delete audio past 90 days since last access.
- Export: PDF, Word, plain text, audio (if retained), transcript-only.
- Branded export settings for paid tier (logo, header, footer, brand color).

**What the agent does NOT build yet:**
- Voice input integration (handoff 4).
- Entity references and cross-spoke surfacing (handoff 4).

**What "done" looks like for this handoff:**
Meeting Notes feels like a real product you'd use daily. You record a meeting, it gets a sensible name automatically ("Q2 planning with Sarah — Apr 17"). You organize 10-20 test recordings into a few folders ("Client calls," "Internal," "Interviews"). You search for "Sarah" and see all relevant recordings. You tap a recording, change its retention to "keep until I delete," export a PDF for a colleague. The PDF is cleanly formatted with your test branding applied if you're on paid tier.

**Real-device testing before moving on:**
- Build a library of 20-30 test recordings covering different topics, speakers, lengths.
- Verify AI-suggested names are consistently useful (should be ~80%+ good-to-great, not just "not terrible").
- Organize into folders, move recordings between folders, delete a folder with recordings in it.
- Sort by each method, filter by folder and date range, search by various terms.
- Test retention: set one recording to "delete after transcription" and confirm audio is deleted while transcript/summary remain. Set another to "keep until I delete" and confirm it persists. Simulate 90+ days since last access (may need a dev flag to override the real date) and confirm auto-delete runs cleanly.
- Export each format. Open each exported file. Verify PDF and Word look professional, not like debug output.

**Common issues to watch for:**
- AI-suggested names being technically accurate but unhelpful ("Meeting about business things" rather than "Acme pricing discussion").
- Folder management feeling more complex than it should.
- Exports looking like debug output — extra line breaks, markdown syntax showing through, broken formatting.
- Search being slow on larger libraries (over 100 recordings).
- Retention auto-delete running at unexpected times or on recordings the user has been actively using.

---

### Handoff 4: Intelligence Layer (Mission Brief Phases 8-9)

**What the agent builds:**
- Voice input for summary refinement: tap mic in refine field, speak, submit.
- Voice input for inline renaming of recordings, folders, speakers.
- AI-inferred entity references after summary generation: extract contacts, companies, topics.
- Fuzzy matching against the kernel's shared entity store.
- User confirmation for creating new shared entities ("Create new contact 'Sarah Chen'?").
- Entity reference view within a recording's detail screen.
- Manual add/remove/merge of entity references.

**What the agent does NOT build:**
- Cross-meeting speaker voice-print recognition (v2).
- CRM integrations, calendar integrations, team features (not v1).
- A future Quote spoke reading from Meeting Notes' entity references (that wiring happens when Quote spoke is built).

**What "done" looks like for this handoff:**
Meeting Notes is now feeding the shared entity store. After a recording summarizes, you see "Mentioned: Sarah, Acme Corp, Q2 planning" as entity chips. You can tap a chip to see the entity in the shared store, along with other recordings that reference it. You can merge duplicates ("this Sarah and that Sarah Chen are the same person"). Voice input lets you dictate refinement requests and new names without typing.

**Real-device testing before moving on:**
- Record meetings that mention 3-5 distinct people and companies each.
- Verify fuzzy matching correctly links "Sarah" mentioned in one meeting to "Sarah Chen" already in the store.
- Create new entities via user confirmation, confirm they appear in the shared store.
- Test voice input for refining a summary. Transcription accuracy matters here — garbled refinement requests produce worse summaries.
- Dictate a folder name with punctuation or unusual characters; confirm it lands cleanly.
- Merge two duplicate entities, confirm references update across all recordings.

**Common issues to watch for:**
- Fuzzy matching being too aggressive (linking unrelated "Mikes" together) or too conservative (treating "Sarah" and "Sarah C." as different people).
- Privacy surprise: user didn't realize an entity was being created, feels like surveillance. The confirmation prompt copy matters here.
- Voice refinement producing worse summaries because the refinement itself was mis-transcribed.

---

## Final Verification (Before Declaring v1 of Meeting Notes Done)

After all four handoffs land and individually pass testing:

**End-to-end user journey test:**
Someone who has never used Kraken, on a fresh install, should be able to:
1. Complete onboarding.
2. Tap Meeting Notes on the home screen.
3. Record a 5-minute meeting with you.
4. See the transcription.
5. Read the summary.
6. Export it as a PDF.
7. Send it to you.

…without needing help. Watch them do this silently. Note where they hesitate, where they tap the wrong thing, where their face indicates confusion. Fix those specific issues.

**Competitive comparison:**
Record the same meeting in Otter or Fireflies (cloud) and Kraken (on-device). Compare the transcripts and summaries side by side.
- Kraken's transcript should be competitive with theirs.
- Kraken's summary quality should be in the same ballpark, not obviously worse.
- Kraken's UX should feel comparable or calmer.
- Kraken's privacy story is the differentiator, not feature parity. But if Kraken is significantly worse at the core function, the privacy story won't save it.

If the comparison reveals quality gaps in transcription or summarization, invest more time in prompt engineering (handoff 2) before shipping.

**The honest "would I use this?" test:**
Use Meeting Notes yourself for a week. Record real meetings (not test recordings). Try to rely on it as your actual meeting notes tool.

If you catch yourself opening another app to take notes because Kraken isn't working for you, note what's missing or broken. Fix those things before shipping. You are the most demanding early user Kraken has; if it passes the "I genuinely used it this week" test, it will pass most real-world tests.

## What This Build Plan Enables After Shipping

Once Meeting Notes ships well, it unlocks:

- The visual and interaction patterns that every future spoke inherits. Your Documents spoke, future Quote spoke, future Personal Notes spoke all become 60% easier because Meeting Notes established how recording → processing → artifact generation → organization → export should feel.
- The competitive position. "Privacy-first meeting notes that work entirely on your device" is a sentence that sells. You can put it in App Store copy, marketing materials, and conversations with users.
- Real usage data that informs every subsequent decision. Watching what users actually do with Meeting Notes will surface things your roadmap is missing and things your roadmap contains that users don't actually need.

## Risks and Mitigations

**Risk: Transcription quality disappoints on real-world audio.**
Faster-Whisper is genuinely good, but on-device constraints (lower-tier models than cloud Whisper) plus noisy real meetings plus accents plus overlapping speakers will produce lower-quality transcripts than users expect from cloud competitors.
Mitigation: Set expectations honestly in UI. ("Transcription quality depends on audio conditions" below the transcript.) Invest in letting users correct segments easily. Make speaker labeling accurate enough that even imperfect transcripts are usable.

**Risk: Summary hallucinations damage trust.**
Gemma 4 may occasionally produce summaries that reference things not in the transcript. On a meeting summary, this is a trust-destroying bug — one fabricated action item that "you committed to deliver X by Friday" is worse than no summary at all.
Mitigation: Prompt engineering to prioritize fidelity over polish. Never invent content if a section has no source material. Add a small "Generated summaries may occasionally miss or misremember details — verify against the transcript for anything important" disclosure somewhere non-obtrusive.

**Risk: The 20-minute free limit feels like a bait-and-switch.**
If users feel tricked by the limit — start recording a 45-minute meeting, don't notice the warnings, lose 25 minutes of content — they will rate-one-star the app immediately.
Mitigation: The warning UX in handoff 1 must be genuinely prominent and clear. Test this with people who don't know the limit exists; do they hit 20 minutes in surprise or expectation?

**Risk: The agent gets stuck iterating on prompt engineering forever.**
Prompt quality is subjective and there's always a "but what about this edge case" to chase.
Mitigation: Define "good enough" for handoff 2 explicitly. My suggestion: if 7 out of 10 test meetings produce summaries you'd send to a colleague without editing, the prompt is good enough to ship. Pursuing 9 out of 10 is worth doing in a v1.1 update, not blocking v1.

**Risk: Meeting Notes exposes kernel issues you thought were solved.**
The first real spoke is where hub bugs that hid in the mock spoke come out. Some audio service edge case, some entitlement check race condition, some vault concurrency issue.
Mitigation: Treat any kernel issue discovered during Meeting Notes as a hub bug, not a Meeting Notes bug. Fix in the kernel, not in the spoke. Resist the urge to work around kernel bugs in spoke code.

## Scheduling Reality

Meeting Notes is 3-4 weeks of agent work, plus 1-2 weeks of real-device testing, polish, and prompt iteration cycles. Budget 5-6 weeks from handoff 1 to "v1 Meeting Notes is ready to ship" if you're moving carefully. Faster is possible if you skip phases or cut corners on testing, but you'll pay it back in bug fixes later.

Between handoffs, build in 2-3 days of personal testing. This isn't wasted time — it's where you catch the issues that would otherwise turn into user-reported bugs or 1-star reviews.

## Next Action

If you're ready to start:

1. Confirm all prerequisites from the list at the top are met.
2. Update `MISSION_BRIEF_MEETING_NOTES_SPOKE.md` to use "library" terminology and reference the design tokens (I can draft this update if you want).
3. Hand handoff 1 scope to the agent (mission brief phases 1-3 only — be explicit about the phase boundaries).
4. Come back when the agent produces its Phase Completion Checklist for handoff 1.

Good luck. This is the spoke that will make or break early impressions of Kraken. Worth doing carefully.

## Pinned for Later

**Personal Note-Taking Spoke** — a lightweight, personal spoke for quick thoughts, daily journaling, tagged notes, and personal reference. Distinct from Meeting Notes (conversation-focused) and Quick Capture (routing-focused). Build after v1 lineup ships and you've seen real usage patterns that inform what makes this spoke useful rather than redundant with Quick Capture.
