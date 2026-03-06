# Phase C Integration Glue (C1–C5)

This pass adds **merge-safe shared scaffolding** for the Phase C ticket set.

## Goals

- Provide shared models for C1 command palette, C2 archive/history center, C3 editor state, C4 perf preference, and C5 shortcut overlay.
- Add a dedicated persistence envelope for workspace-scoped Phase C integration state.
- Add a shared router/state holder so independent C1–C5 branches can plug into one in-memory surface.
- Keep this pass intentionally thin and additive.

## 1) Shared C1–C5 models + interfaces

File: `Sources/Crew/Models/PhaseCIntegrationModels.swift`

Added common enums + envelope:

- `WorkspaceCommandScope`
- `WorkspaceHistoryFilter`
- `ManualEditorFocusRegion`
- `ShortcutOverlayState`
- `PhaseCWorkspaceState`

Added integration interfaces:

- `PhaseCStateProviding`
- `PhaseCStatePersisting`

## 2) Shared router/state scaffold

File: `Sources/Crew/Services/WorkspacePhaseCRouter.swift`

Added `WorkspacePhaseCRouter` singleton with:

- per-workspace `PhaseCWorkspaceState`
- convenience setters for command palette visibility + history filter
- upsert/clear helpers for ticket branches to reuse

## 3) Persistence envelope migration additions

File: `Sources/Crew/Services/Database.swift`

Migration v8 introduces:

- `phase_c_workspace_state`
  - `workspace_id` (PK, FK to `worktrees.id`)
  - `payload_json`
  - `updated_at`

Database API added:

- `upsertPhaseCWorkspaceState(_:)`
- `fetchPhaseCWorkspaceState(workspaceId:)`

Also includes additive `addColumnIfMissing` guards for `payload_json` and `updated_at` to keep schema changes idempotent in mixed migration histories.

## 4) Tests

File: `Tests/CrewTests/PhaseCIntegrationTests.swift`

Coverage:

- Codable roundtrip for `PhaseCWorkspaceState`
- migration runner applies Phase C envelope and bumps `user_version`
- idempotent column-add helper behavior for Phase C table

## Merge-safety notes

- Schema is additive only (new migration v8).
- No feature-specific UI logic is forced in this pass.
- C1–C5 branches can independently consume shared model/router/database APIs.
