# Phase B Integration Glue (B1–B5)

This branch adds **merge-friendly scaffolding** shared by Phase B tickets.

## Goals

- Define shared models/interfaces for plan approval, pending questions, notes, and summary snapshots.
- Add migration-safe persistence envelope for workspace-level Phase B route/workflow state.
- Add shared tab/router state for Plan / Questions / Notes / Summary.
- Keep implementation thin so feature tickets can land independently.

## Added in this integration pass

## 1) Shared B1–B5 models + interfaces

File: `Sources/Crew/Models/PhaseBIntegrationModels.swift`

Includes common enums and payloads:

- `AgentExecutionStage`
- `PlanApprovalStatus`
- `WorkspaceSurfaceTab`
- `PlanDraft`
- `PendingQuestionPrompt`
- `NotesDocumentState`
- `SummarySnapshotState`
- `PhaseBWorkspaceState`

And adapter interfaces for future ticket-specific providers:

- `PlanStateProviding`
- `QuestionsStateProviding`
- `NotesStateProviding`
- `SummaryStateProviding`

## 2) SQLite migration helper updates

File: `Sources/Crew/Services/SQLiteMigration.swift`

Added reusable schema-introspection helpers:

- `SQLiteColumnInfo`
- `tableExists(_:on:)`
- `columnInfo(for:on:)`
- `columnExists(_:in:on:)`
- `addColumnIfMissing(table:column:definitionSQL:on:)`

These keep future additive migrations idempotent and safer for parallel ticket development.

## 3) Phase B persistence envelope migration

File: `Sources/Crew/Services/Database.swift`

Migration v3 adds table:

- `phase_b_workspace_state`
  - `workspace_id` (PK, FK to `worktrees.id`)
  - `payload_json`
  - `updated_at`

Database API added:

- `upsertPhaseBWorkspaceState(_:)`
- `fetchPhaseBWorkspaceState(workspaceId:)`

The envelope stores shared workflow/route state as JSON, allowing B1–B5 to evolve without frequent schema churn.

## 4) Shared tab/route state for Plan/Questions/Notes/Summary

Files:

- `Sources/Crew/Services/WorkspaceSurfaceRouter.swift`
- `Sources/Crew/Views/WorkspaceInspectorTabsView.swift`

Added:

- `WorkspaceSurfaceRouter` singleton (`@Published` tab selection keyed by workspace)
- segmented tab shell wired to `WorkspaceSurfaceTab`
- placeholders for B1/B2/B4/B5 feature surfaces

## 5) Basic tests for migration/model roundtrip

File: `Tests/CrewTests/PhaseBIntegrationTests.swift`

Coverage:

- Codable roundtrip for `PhaseBWorkspaceState`
- migration runner applies Phase B-style migration and updates `user_version`
- `addColumnIfMissing` is idempotent and only adds once

## Merge-safety notes

- No provider/network behavior is implemented in this pass.
- New schema is additive (migration v3).
- Shared types/protocols are intentionally thin extension points for B1–B5 ticket branches.
