import Foundation
import Combine

/// Shared tab routing state for B1–B5 surfaces (Plan / Questions / Notes / Summary).
@MainActor
final class WorkspaceSurfaceRouter: ObservableObject {
    static let shared = WorkspaceSurfaceRouter()

    @Published private var selectedTabsByWorkspace: [String: WorkspaceSurfaceTab] = [:]

    func selectedTab(for workspaceKey: String) -> WorkspaceSurfaceTab {
        selectedTabsByWorkspace[workspaceKey] ?? .plan
    }

    func setSelectedTab(_ tab: WorkspaceSurfaceTab, for workspaceKey: String) {
        selectedTabsByWorkspace[workspaceKey] = tab
    }

    func clear(workspaceKey: String) {
        selectedTabsByWorkspace.removeValue(forKey: workspaceKey)
    }
}
