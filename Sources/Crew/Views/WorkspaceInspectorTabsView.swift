import SwiftUI

struct WorkspaceInspectorTabsView: View {
    enum InspectorTab: String, CaseIterable, Identifiable {
        case git = "Git"
        case checks = "Checks"

        var id: String { rawValue }
    }

    let repoPath: String
    let worktreeId: UUID

    @State private var selectedTab: InspectorTab = .git

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector tab", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            Group {
                switch selectedTab {
                case .git:
                    GitPanelView(repoPath: repoPath, workspaceId: worktreeId.uuidString)
                case .checks:
                    ChecksPanelView(repoPath: repoPath, worktreeId: worktreeId)
                }
            }
        }
    }
}
