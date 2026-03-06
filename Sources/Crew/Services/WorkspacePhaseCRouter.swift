import Foundation
import Combine

/// Shared routing/interaction state scaffold for C1–C5 surfaces.
@MainActor
final class WorkspacePhaseCRouter: ObservableObject {
    static let shared = WorkspacePhaseCRouter()

    @Published private var stateByWorkspace: [String: PhaseCWorkspaceState] = [:]

    func state(for workspaceKey: String) -> PhaseCWorkspaceState? {
        stateByWorkspace[workspaceKey]
    }

    func state(for workspaceId: UUID) -> PhaseCWorkspaceState {
        stateByWorkspace[workspaceId.uuidString] ?? PhaseCWorkspaceState(workspaceId: workspaceId)
    }

    func upsert(_ state: PhaseCWorkspaceState) {
        stateByWorkspace[state.workspaceId.uuidString] = state
    }

    func setCommandPaletteVisible(_ isVisible: Bool, workspaceId: UUID) {
        var state = self.state(for: workspaceId)
        state.isCommandPaletteVisible = isVisible
        state.updatedAt = Date()
        upsert(state)
    }

    func setHistoryFilter(_ filter: WorkspaceHistoryFilter, workspaceId: UUID) {
        var state = self.state(for: workspaceId)
        state.historyFilter = filter
        state.updatedAt = Date()
        upsert(state)
    }

    func clear(workspaceKey: String) {
        stateByWorkspace.removeValue(forKey: workspaceKey)
    }
}
