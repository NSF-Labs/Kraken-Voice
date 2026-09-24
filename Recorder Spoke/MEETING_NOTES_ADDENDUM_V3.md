# Meeting Notes Addendum v3 — Transcription Status Indicator Architecture

**Date:** April 24, 2026  
**Supersedes:** Handoff 2A Workstream B items B.5–B.6 (Mission Brief and Addendum v2 global banner specification); Build Plan audit items 2A-14 through 2A-20.  
**Reference:** Phase 2 Build Plan audit conducted April 23, 2026 (Conversation e0d47bf9).

---

## §1 — What Was Specified vs. What Was Built

**Original specification** (Mission Brief §Workstream B; Handoff 2A Kickoff §B.5–B.6): A persistent in-app banner visible on the home screen and all non-Meeting-Notes screens. The banner would display active transcription progress (percentage and time remaining), queue depth ("N more queued"), and tap-to-navigate behavior returning the user to Meeting Notes. The banner would dismiss when all transcription work completed.

**What was built:** Folder-level pulsing glow indicators on the Meeting Notes main screen (folder cards) and folder detail screen (recording cards). Each folder card renders an animated `BoxShadow` border whose color and pulse state reflect the aggregate processing state of its child recordings. Individual recording cards within folders display per-file status chips showing the full 6-state label set. The global `_ActiveTranscriptionBanner` widget was built, tested on-device, and then deliberately removed from the shell layout.

---

## §2 — Glow States

| State | Color | Animation | Where it appears |
|---|---|---|---|
| **Transcribing / Queued** | Accent (theme primary) | Pulsing glow, 1.5s cycle, `easeInOut`, repeats | Folder card on `MeetingNotesMainScreen`; recording card on `FolderDetailScreen` |
| **Actively recording** | Red | Pulsing glow, same timing | Folder card containing the active recording; embedded recorder widget border |
| **Idle / Complete** | None | No animation | Standard card border, no `BoxShadow` |

The glow state for each folder is derived from `_folderStates`, a map of `folderId → int` where `0 = Clear`, `1 = Processing`, `2 = Failed`. The animation controller runs continuously while any folder has `stateLevel > 0`.

---

## §3 — Per-Item Disposition of Superseded Audit Items

| ID | Original Spec | Disposition | Replacement Behavior |
|----|--------------|-------------|---------------------|
| **2A-14** | Persistent banner on home screen and non-Meeting-Notes screens | **Superseded** | Folder-level glow on `MeetingNotesMainScreen` folder cards. Processing state is visible when the user is in Meeting Notes, which is the only context where the information is actionable. Not replicated on non-Meeting-Notes screens — this is an intentional narrowing of scope. |
| **2A-15** | Progress notification during transcription | **Retained independently** | Completion notification fires when transcription finishes. The banner removal did not affect this — it was never part of the glow replacement. Live progress during transcription (percentage in notification shade) was not built and remains an open gap (classified 🟡 UNCERTAIN in the audit). |
| **2A-16** | Banner with % and time remaining | **Partially superseded** | Per-recording progress percentage is shown inline on recording cards via status chips within `FolderDetailScreen`. The "time remaining" estimate is not surfaced at the folder level — only the binary "processing / not processing" state is visible via glow. |
| **2A-17** | "N more queued" banner text | **Superseded** | Queue depth is visible implicitly: each recording card in the folder shows its individual status chip ("Queued," "Transcribing," etc.). The user sees exactly which recordings are queued and in what order, rather than an aggregate count. |
| **2A-18** | "N recordings queued — starting shortly" banner text | **Superseded** | Same mechanism as 2A-17. Per-file status chips replace the aggregate queue summary. |
| **2A-19** | Banner auto-dismiss on completion | **Superseded** | Glow stops animating when all child recordings complete processing (`stateLevel` returns to `0`). No dismiss gesture needed — the visual simply returns to its default state. |
| **2A-20** | Banner tap-to-navigate to Meeting Notes | **Superseded — functionality unnecessary** | The glow indicators exist only within Meeting Notes. The user is already in the correct context when they see them. Navigation is not needed. |

---

## §4 — Rationale

**Context proximity.** Transcription status matters when the user is looking at their recordings. A banner on the Dashboard or Settings screen communicates that *something* is happening but requires a navigation step before the user can act. The glow indicator surfaces state at the point of interaction — when the user is already looking at the folder whose recordings are processing.

**Screen real estate.** On mobile, a persistent banner consumes a fixed-height strip on every screen in the app, including screens with no connection to transcription (Dashboard tools, Spoke settings, etc.). The cost was disproportionate to the value for a single-purpose indicator.

**Information density.** The per-file status chips inside folders provide more granular information than the banner's aggregate summary. Instead of "Transcribing — 47% · 2 more queued," the user sees the specific recording being transcribed, its individual progress, and the exact recordings waiting in queue. This scales better as the user accumulates recordings — the banner would need increasingly compressed text, while the list view naturally accommodates any count.

**Visual consistency.** The recording state already used a pulsing glow on the active folder card (red glow during capture). Extending this visual language to transcription state (accent glow during processing) creates a single visual grammar for "this folder has active work." The user doesn't need to learn a second indicator system.

---

*This addendum documents one architectural decision. No other changes are proposed or implied.*
