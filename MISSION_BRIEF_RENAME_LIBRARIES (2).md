# Mission Brief: User-Facing Terminology Rename — Workspaces to Libraries

## Objective

Rename user-facing terminology for two core Kraken concepts:

- **"Workspace" → "Library"** — the protected, user-curated containers of reference material (pricing files, contracts, company documents). These are read-only to spokes.
- **"Spoke outputs" → "Drafts"** — AI-generated artifacts spokes produce (meeting summaries, quote drafts, captured thoughts). These are things the user can review, refine, export, or delete.

The change is **user-facing only**. Code-level schema names, table names, API method names, and internal class names remain unchanged to preserve technical clarity for developers. This mission touches UI strings, onboarding copy, settings labels, help text, microcopy, and documentation visible to end users.

## Why this change

The word "Workspace" implies a place where *work happens* — bidirectional editing, moving things in and out, temporary drafts. That's the opposite of what the container actually is: a protected, curated repository that spokes read from but never write to. Users expecting workspace semantics would be surprised by read-only-for-spokes behavior.

"Library" matches the actual semantics almost exactly. Users understand libraries as curated collections of reference material — things you consult, not things you rewrite. Spokes "read from your Library" reads naturally. "AI can never write into your Library" reads naturally. "Grant the Quote spoke access to your Pricing Library" reads naturally.

"Drafts" correctly frames AI-generated artifacts as things the user can review, refine, or discard. It doesn't overclaim (they're not finished products), and it invites user engagement (drafts are meant to be worked with).

## Execution Rules (Read First)

- Follow all rules in `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §0 Execution Rules and §2.1 Non-Negotiable Coding Rules.
- **Code-level names do not change.** Database tables stay named `workspaces`, `workspace_access`, `spoke_outputs`. Service classes stay `WorkspaceService`. API methods stay `listVisibleWorkspaces`, `grantReadAccess`, etc. Do not rename these.
- **UI strings, copy, and user-visible docs change.** Any string the user sees uses "Library" or "Libraries" (plural); any reference to generated artifacts in user-visible contexts uses "Drafts."
- **Developer-facing docs keep both terms where helpful.** The implementation plan, security protocol, and technical READMEs may use either term, but should clarify the mapping once at the top: "Library (the user-facing name for what the code calls a Workspace)."
- Produce a Phase Completion Checklist at the end per the standing phase-gate rule.
- This is a string-change mission, not a logic-change mission. Do not refactor behavior, do not rename files, do not change routes.

## Phase 1: UI String Inventory

### 1.1 Enumerate every user-facing string containing "workspace"

Before making any changes, produce a complete inventory of user-facing occurrences. Search in:

- `/lib/shell/` — all widget strings, screen titles, button labels, dialog copy, error messages.
- `/lib/spokes/*/` — any string a spoke shows to users (excluding internal logs and console output).
- `assets/` — any asset containing user-visible text (localization files, help content).
- User-facing documentation: any README, in-app help screen, onboarding copy, FAQ, or support link.
- Exported file templates (PDF/Word export headers, footers, titles).

Output: a list of every file path and line number containing user-visible "workspace" / "workspaces" / "Workspace" / "Workspaces" strings. Commit this inventory as `docs/rename_inventory.md` before making changes.

### 1.2 Enumerate "spoke outputs" and related phrasing

Same process for artifact-related user-facing copy:

- "spoke outputs"
- "spoke output"
- "generated artifacts"
- "outputs" (in user-facing contexts only; kernel code uses this term legitimately)
- "your meeting summaries," "your quotes," etc. (these may stay spoke-specific; see §2.3 below)

### 1.3 Flag ambiguous cases for review

Some strings will be ambiguous. Examples:

- "Add file to workspace" — clear rename target → "Add file to Library."
- "The audit log tracks workspace access" — could be user-facing or developer-facing depending on where it's shown. Flag for review.
- "Your workspace is ready" — clear rename target → "Your Library is ready."
- Error message "workspace_access_denied" — this is a code-level error identifier. Keep the code, but the user-visible error text should say "You don't have access to this Library."

Produce the inventory with ambiguous cases flagged so a human can confirm intent before bulk-replacement.

## Phase 2: Apply Renames

### 2.1 Terminology mapping (canonical)

Apply these replacements everywhere user-facing:

| Old user-facing term | New user-facing term |
|---|---|
| Workspace | Library |
| Workspaces | Libraries |
| workspace (as generic noun in a sentence) | library |
| workspaces (as generic noun in a sentence) | libraries |
| your workspace | your library |
| spoke output | draft |
| spoke outputs | drafts |
| generated artifact | draft |
| generated artifacts | drafts |

**Capitalization is context-sensitive — this matters for tone.** Over-capitalizing would make the UI feel branded and marketing-like rather than calm and natural. Use this rule:

*Capitalize* when:
- Used as a proper noun naming a specific Library ("Pricing Library," "Acme Client Library," "Contracts Library").
- Used as a section header or screen title ("Libraries," "Your Libraries").
- Referring to the Kraken concept in a list of features or high-level navigation ("Libraries hold your reference material").

*Lowercase* when:
- Used as a generic noun in sentence-style UI copy ("Create a library," "Add file to library," "This library is full," "Your library has been deleted").
- Used in body text that flows as natural English ("Files in this library are read-only to spokes").
- Used in error messages that read as sentences ("You don't have access to this library").

The same rule applies to "Draft(s)" — capitalize as a heading or proper-noun-adjacent reference ("Recent Drafts"), lowercase in flowing sentences ("the AI has generated a draft summary").

When uncertain, lowercase is the safer default for body copy. Uppercase is the safer default for headings and lists of concepts. If a string reads like marketing copy after capitalization, that's a signal to lowercase it.

### 2.2 Specific string replacements

The following are known high-traffic strings that must be updated. This is not exhaustive — use the inventory from Phase 1 for complete coverage. Where strings show specific capitalization below, follow §2.1's context rule.

**Onboarding and home screen:**

- "Your data lives in Workspaces. Tap here to create your first one, or jump straight into a spoke." → "Your data lives in Libraries. Tap here to create your first one, or jump straight into a spoke." (capitalized here because it's a feature-introducing sentence pointing at a named concept)

**Shell workspace management screen (now Library management):**

- Screen title: "Workspaces" → "Libraries" (capitalized — section title)
- Empty state: "No workspaces yet. Create one to get started." → "No libraries yet. Create one to get started." (lowercase — natural sentence)
- Primary button: "Create workspace" → "Create library" (lowercase — action in a sentence)
- Dialog title for create: "New workspace" → "New library" (lowercase — dialog title reads like a sentence)
- Field label: "Workspace name" → "Library name" (capitalized — a labeled field for a named thing)
- Placeholder: "e.g. Pricing, Contracts, Client Work" → unchanged (still valid)
- Action button: "Add file to workspace" → "Add file to library" (lowercase — natural action)
- Action button: "Rename workspace" → "Rename library" (lowercase)
- Action button: "Delete workspace" → "Delete library" (lowercase)
- Confirmation dialog title: "Delete workspace?" → "Delete library?" (lowercase — sentence-style question)
- Confirmation body: "This will permanently delete this workspace and all its contents. This cannot be undone." → "This will permanently delete this library and all its contents. This cannot be undone." (lowercase — body copy)

**Access management (within Library management screen):**

- Section title: "Spoke access" → unchanged (still accurate)
- Description: "Grant spokes read-only access to this workspace." → "Grant spokes read-only access to this library." (lowercase — body copy)
- Grant button: "Grant workspace access" → "Grant access"
- Revoke confirmation: "Revoke this spoke's access to this workspace?" → "Revoke this spoke's access to this library?" (lowercase — sentence-style)

**Error and status messages (user-visible only):**

- "You don't have access to this workspace." → "You don't have access to this library." (lowercase)
- "Workspace not found." → "Library not found." (lowercase despite sentence-initial — the full user-visible string is typically just this phrase; cap if it's sentence-initial)
- "Workspace quota exceeded." → "This library is full." (with a specific second line detailing which limit: "Maximum 10 GB total / 10,000 files / 250 MB per file.")
- "Workspace created successfully." → "Library created." (cap because sentence-initial)

**Audit log and activity panel entries:**

Audit log entries read as structured records, so consistent capitalization of the noun "Library" reads naturally:

- "Workspace created: [name]" → "Library created: [name]"
- "Workspace deleted: [name]" → "Library deleted: [name]"
- "Granted read access to workspace: [name]" → "Granted read access to library: [name]"
- "Revoked access to workspace: [name]" → "Revoked access to library: [name]"
- "Imported file to workspace: [name]" → "Added file to library: [name]"

**Settings screen:**

- "Workspaces" section heading → "Libraries" (capitalized — section heading)
- "Manage workspaces" link → "Manage libraries" (lowercase — action verb phrase)
- Help text: "Workspaces hold your reference materials — pricing files, contracts, company documents. Spokes read from these with your permission." → "Libraries hold your reference materials — pricing files, contracts, company documents. Spokes read from these with your permission." (capitalized — concept-introducing help text)

**Security protocol viewer (in-app):**

- "workspace isolation rules" → "library isolation rules" (lowercase — running body text)
- "spokes cannot write into workspaces" → "spokes cannot write into libraries" (lowercase)
- "workspace-scoped encryption" → "library-scoped encryption" (lowercase)

**Spoke-side references to user Libraries:**

- Any spoke that references user Libraries in its UI uses "library" or "Library" per §2.1's context rule.
- Examples:
  - Quote spoke (future): "Pricing Library" label in source selector (capitalized — it's naming a specific Library).
  - Document Summaries (future): "Choose a library to search" button (lowercase — natural action).

### 2.3 Spoke output / Drafts renaming

Where spokes display AI-generated artifacts to users, "drafts" (or "Drafts" as appropriate per §2.1's context rule) is the collective term. Examples:

**Meeting Notes spoke:**

- List view title: "Meeting Notes" — unchanged (this is the spoke name, not a generic term).
- Collective references: "Recent drafts," "your drafts" (lowercase — natural sentences).
- Section heading listing the spoke's outputs: "Drafts" (capitalized — heading).
- Export button: "Export this draft" (lowercase — natural action).
- Empty state: "No meeting notes yet. Record your first meeting to get started." — unchanged (natural English).

**Quote spoke (future):**

- List view: "Quote drafts" or "Your quotes" — either is fine in context; prefer "drafts" for AI-generated-but-not-finalized outputs, "quotes" for user-finalized ones.
- Action: "Export this draft" (lowercase).

**Shell-level references:**

- Activity panel entries describing AI outputs: "Generated quote draft: [name]" rather than "Generated spoke output."

Note: individual spokes may use their own more specific terms where it reads more naturally. "Your meeting notes" is better than "your meeting drafts" in the Meeting Notes spoke because "meeting notes" is the natural English phrase users already use. Reserve "drafts" for collective references ("All your drafts across spokes") and for contexts where genericity is useful.

When in doubt about capitalization of "draft(s)," default to lowercase in body copy and sentence-style UI, capitalized only in headings or when naming the concept explicitly.

### 2.4 Help text and onboarding copy

The onboarding flow's home banner (per `MISSION_BRIEF_ONBOARDING_FLOW.md` §2.2) changes:

- "Your data lives in Workspaces. Tap here to create your first one, or jump straight into a spoke."

Becomes:

- "Your data lives in Libraries. Tap here to create your first one, or jump straight into a spoke."

Any future onboarding tooltip or first-use coachmark that mentions the concept should use "Library" consistently.

If any onboarding copy explains the Library concept to new users, the explanation should emphasize the curated, protected nature:

> "Libraries hold your reference materials — things like pricing files, contracts, or company documents. You add files to your libraries; spokes read from them with your permission. Spokes can never change what's in your libraries."

(Note the capitalization: "Libraries" capitalized as the concept introduction, then lowercase in the flowing sentence that follows. This pattern — capitalize once when naming, lowercase when referring — keeps the copy calm rather than branded.)

## Phase 3: Asset and Icon Considerations

### 3.1 Icons

If any UI uses a "workspace" icon (typically a folder or filing-cabinet glyph), verify it still communicates the right concept. A simple bookshelf, book, or library-building icon may be clearer for the Library concept. This is optional — the existing folder icon is fine as long as it doesn't say "workspace" in any icon label.

Do not change icons that have no textual meaning tied to the old term. Stick to what's clear and consistent.

### 3.2 Illustrations and marketing visuals

If any onboarding screen uses illustrations with the word "Workspace" in them (unlikely but possible), replace with "Library." Otherwise, no illustration changes are required for this mission.

## Phase 4: Developer-Facing Docs

### 4.1 Implementation plan note

Add a small callout at the top of `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` near §3.8:

> **Note on terminology:** The code refers to these containers as "Workspaces." Users see them as "Libraries." Both terms refer to the same underlying system. Developer documentation and code use "Workspace"; user-facing strings and documentation use "Library."

### 4.2 Security protocol

Same pattern in `KRAKEN_SECURITY_PROTOCOL.md`:

> The security rules for "Workspaces" (developer term) and "Libraries" (user-facing term) are identical. This document uses both terms interchangeably.

### 4.3 Spoke mission briefs

Existing mission briefs (Meeting Notes, onboarding flow) reference both terms. Review them for consistency:

- Where the brief describes UI copy, update to use Library/Drafts.
- Where the brief describes code architecture, keep Workspace/spoke_outputs.

## Phase 5: Verification

### 5.1 Grep pass

After replacements, grep the codebase for remaining user-facing occurrences:

```
grep -rn "workspace" lib/shell/ lib/spokes/ | grep -v "// "
grep -rn "Workspace" lib/shell/ lib/spokes/ | grep -v "// "
```

Any results in user-facing strings (UI widgets, copy files, user-visible error text) need to be addressed or explicitly marked as developer-facing.

### 5.2 Visual review

Manual screenshot review of:

- Onboarding flow, all screens.
- Home screen with and without Libraries.
- Library management screen: create, rename, delete flows, grant/revoke access flows.
- Settings Privacy section.
- Audit log / Activity panel.
- Each spoke's main screen and its interaction points with Libraries (for Meeting Notes v1: the entity reference linking; for future spokes: their Library selectors).

Check that no user-facing "Workspace" text remains.

### 5.3 Documentation review

Review any in-app help content, README files users might see, and any support pages that mention the concept. Ensure consistency.

### 5.4 Test the grep guard

Add a CI check that fails the build if any string under `lib/shell/` or `lib/spokes/` matches `workspace` or `Workspace` *outside of explicit allowlist patterns* (e.g., references to the code-level `WorkspaceService` class, which is legitimately developer-facing in comments, or exact matches of the string constant `workspace_id` used as a database column reference).

The allowlist is narrow and documented. The purpose is to prevent drift over time: future features shouldn't accidentally reintroduce "Workspace" in user-facing strings.

## Phase 6: Exit Criteria

1. `docs/rename_inventory.md` committed with complete pre-rename inventory.
2. All user-facing strings replaced per §2.1 mapping.
3. Grep pass returns no unexplained user-facing "workspace" / "Workspace" occurrences.
4. Visual review screenshots attached to PR; no "Workspace" text visible anywhere to end users.
5. Developer-facing docs updated with terminology callouts.
6. CI guard in place and passing (deliberately introducing "Workspace" in a user-facing string fails the build).
7. Existing tests pass without modification. (Behavior did not change; only strings.)
8. Human copy review: a reviewer reads every changed user-facing string and confirms (a) it uses the correct new terminology, (b) the capitalization reads naturally in context per §2.1, and (c) the overall tone stays calm and plain rather than branded. This is not automatable; budget 30 minutes for it.
9. Phase Completion Checklist produced and committed.

## Out of Scope (Do Not Build)

- Renaming code-level classes, methods, table names, or API identifiers.
- Refactoring any behavior.
- Renaming files or changing folder structure.
- Changing database schemas.
- Updating external documentation (App Store descriptions, website copy) — those are a separate marketing mission.
- Localization to other languages — v1 is English; translation of the new terms to other languages is a future mission.
- Deciding whether to also rename "spoke" or "kernel" — those terms are kept as-is. "Spoke" is internally consistent with the Kraken metaphor, and "kernel" is developer-facing only (users see specific spoke names and kernel services by their user-facing names, not "the kernel").

## Execution Order

1. Phase 1 (inventory) — do this completely before any replacement.
2. Human review of inventory (30 minutes) — confirm no mass-replacement surprises.
3. Phase 2 (replacements) — methodical, one file category at a time.
4. Phase 3 (assets) — optional, skip if icons are already abstract enough.
5. Phase 4 (dev docs) — small and quick.
6. Phase 5 (verification) — thorough grep, visual review, CI guard.
7. Phase 6 (exit criteria) — final gate.

## Design Reference Notes

- The rename is about user mental model, not developer convenience. Developers have built Workspaces; users will use Libraries. The code preserves technical clarity; the UI preserves user clarity. Both are legitimate.
- **Tone matters as much as terminology.** Over-capitalizing "Library" or "Drafts" would make the UI feel branded and marketing-heavy. Under-capitalizing would lose the sense that these are specific Kraken concepts. The context-sensitive rule in §2.1 exists because calm, natural copy serves Kraken's positioning better than aggressive branding. When in doubt about a particular string, read it out loud — if capitalization makes it sound like advertising, lowercase it.
- When in doubt about whether a string is user-facing, assume it is. Over-capturing in Phase 1 is better than missing strings that leak "Workspace" into the user experience.
- Consistency of *term* matters more than any individual casing choice. If "library" is used 99 times and "Workspace" slips through once in a dialog, that one occurrence undermines the rename. The CI guard in §5.4 exists specifically to prevent this drift. Capitalization variation within the natural rules is fine; unreplaced old terminology is not.
- If any string genuinely reads better with the old term in context, raise it for review — don't silently keep it. There may be rare cases where the English of a particular sentence is better with "workspace" as a generic word, and those can be handled on a case-by-case basis. But those cases should be few and documented.
