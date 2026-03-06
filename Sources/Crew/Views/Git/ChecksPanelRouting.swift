import Foundation

/// Inspector tabs used by Git / Checks panel.
enum InspectorPanelTab: String, Codable, CaseIterable, Identifiable {
    case changes
    case checks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .changes: return "Changes"
        case .checks: return "Checks"
        }
    }

    var systemImage: String {
        switch self {
        case .changes: return "doc.text"
        case .checks: return "checklist"
        }
    }
}

/// Route state shared across inspector panels so A2 can plug in without
/// coupling to concrete check providers.
@MainActor
final class ChecksPanelRouter: ObservableObject {
    static let shared = ChecksPanelRouter()

    @Published private var selectedTabsByWorkspace: [String: InspectorPanelTab] = [:]

    func selectedTab(for workspaceKey: String) -> InspectorPanelTab {
        selectedTabsByWorkspace[workspaceKey] ?? .changes
    }

    func setSelectedTab(_ tab: InspectorPanelTab, for workspaceKey: String) {
        selectedTabsByWorkspace[workspaceKey] = tab
    }
}
