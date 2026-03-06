# Phase A Integration Glue (A1–A5)

This branch adds **shared infrastructure only** to reduce merge conflicts across parallel Phase A tickets.

## Goals

- Provide a common model vocabulary for checks/comments/review workflow.
- Add a reusable SQLite migration runner so each ticket can add schema safely.
- Add shared inspector tab routing so the Checks tab can land without reworking GitPanel plumbing.
- Avoid implementing provider-heavy services that belong in A2/A3/A4/A5.

## What was added

## 1) Shared models + adapter protocols

File: `Sources/Crew/Models/ReviewIntegrationModels.swift`

New model layer for cross-ticket contracts:

- `CheckLifecycleState`
- `CheckRecord`
- `ReviewWorkflowState`
- `ReviewStateSnapshot`
- `ReviewCommentResolution`
- `ReviewCommentRecord`

These are provider-agnostic models intended to be consumed by:

- A2 Checks UI shell
- A3 GitHub checks integration
- A4 PR comment sync
- A5 review controls/gating

Lightweight adapter protocols were also added as extension points:

- `ChecksDataProviding`
- `ReviewCommentsProviding`
- `ReviewStateProviding`

No concrete network/service implementation is included here by design.

## 2) Shared SQLite migration helper

File: `Sources/Crew/Services/SQLiteMigration.swift`

Added:

- `SQLiteMigration` (version + label + closure)
- `SQLiteMigrationRunner.apply(_:on:)`
- `PRAGMA user_version` helpers
- duplicate-version validation

`Database` now uses migration runner during init:

- v1: existing core schema (`repos`, `worktrees`, `messages`)
- v2: Phase A integration envelopes:
  - `phase_a_checks`
  - `phase_a_review_states`
  - `phase_a_comments`

The Phase A tables intentionally store provider payload as JSON (`payload_json`) + stable keys for dedupe/indexing. This keeps schema stable while A3/A4 evolve their provider mapping.

## 3) Shared toolbar/tab routing for checks panel

Files:

- `Sources/Crew/Views/Git/ChecksPanelRouting.swift`
- `Sources/Crew/Views/Git/GitPanelView.swift`
- `Sources/Crew/ContentView.swift`

Added:

- `InspectorPanelTab` enum (`changes`, `checks`)
- `ChecksPanelRouter` shared routing state keyed by workspace
- segmented tab switcher in Git panel toolbar
- checks placeholder surface in panel body

Current behavior:

- `Changes` tab: existing Git changes + diff flow
- `Checks` tab: placeholder integration surface ready for A2/A3

This lets A2/A3 implement checks rendering without changing ContentView-level inspector wiring.

## Merge-safety notes

- Existing core app behavior remains unchanged when `Changes` tab is selected.
- No heavy provider or review workflow service logic was added.
- Shared artifacts are intentionally thin and adapter-first.
- Future migrations can append versions in one place (`Database.applyMigrations`).
