import Foundation

// MARK: - Shared C1–C5 Integration Models

enum WorkspaceCommandScope: String, Codable, CaseIterable, Identifiable {
    case workspace
    case repo
    case global

    var id: String { rawValue }
}

enum WorkspaceHistoryFilter: String, Codable, CaseIterable, Identifiable {
    case active
    case archived
    case all

    var id: String { rawValue }
}

enum ManualEditorFocusRegion: String, Codable, CaseIterable, Identifiable {
    case source
    case find
    case diff

    var id: String { rawValue }
}

enum ShortcutOverlayState: String, Codable, CaseIterable, Identifiable {
    case hidden
    case visible

    var id: String { rawValue }
}

/// Shared persistence envelope for C1–C5 behavior.
struct PhaseCWorkspaceState: Codable, Hashable {
    var workspaceId: UUID
    var commandScope: WorkspaceCommandScope
    var isCommandPaletteVisible: Bool
    var historyFilter: WorkspaceHistoryFilter
    var editorFocusRegion: ManualEditorFocusRegion
    var shortcutOverlayState: ShortcutOverlayState
    var prefersReducedPolling: Bool
    var updatedAt: Date

    init(
        workspaceId: UUID,
        commandScope: WorkspaceCommandScope = .workspace,
        isCommandPaletteVisible: Bool = false,
        historyFilter: WorkspaceHistoryFilter = .active,
        editorFocusRegion: ManualEditorFocusRegion = .source,
        shortcutOverlayState: ShortcutOverlayState = .hidden,
        prefersReducedPolling: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.workspaceId = workspaceId
        self.commandScope = commandScope
        self.isCommandPaletteVisible = isCommandPaletteVisible
        self.historyFilter = historyFilter
        self.editorFocusRegion = editorFocusRegion
        self.shortcutOverlayState = shortcutOverlayState
        self.prefersReducedPolling = prefersReducedPolling
        self.updatedAt = updatedAt
    }
}

// MARK: - Provider Interfaces

protocol PhaseCStateProviding {
    func fetchPhaseCWorkspaceState(workspaceId: UUID) throws -> PhaseCWorkspaceState?
}

protocol PhaseCStatePersisting {
    func upsertPhaseCWorkspaceState(_ state: PhaseCWorkspaceState) throws
}
