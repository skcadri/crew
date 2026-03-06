import SwiftUI

struct WorkspaceInspectorTabsView: View {
    let repoPath: String
    let worktreeId: UUID

    @StateObject private var workspaceSurfaceRouter = WorkspaceSurfaceRouter.shared
    private var workspaceKey: String { worktreeId.uuidString }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workspace tab", selection: selectedTabBinding) {
                Text("Git").tag(WorkspaceSurfaceTab.plan)
                Text("Checks").tag(WorkspaceSurfaceTab.questions)
                Text("Notes").tag(WorkspaceSurfaceTab.notes)
                Text("Summary").tag(WorkspaceSurfaceTab.summary)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            Group {
                switch workspaceSurfaceRouter.selectedTab(for: workspaceKey) {
                case .plan:
                    GitPanelView(repoPath: repoPath, workspaceId: worktreeId.uuidString)
                case .questions:
                    ChecksPanelView(repoPath: repoPath, worktreeId: worktreeId)
                case .notes:
                    NotesPanelView(repoPath: repoPath)
                case .summary:
                    SummaryPanelPlaceholderView()
                }
            }
        }
    }

    private var selectedTabBinding: Binding<WorkspaceSurfaceTab> {
        Binding {
            workspaceSurfaceRouter.selectedTab(for: workspaceKey)
        } set: { newValue in
            workspaceSurfaceRouter.setSelectedTab(newValue, for: workspaceKey)
        }
    }
}

private struct SummaryPanelPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Summary tab scaffolded",
            systemImage: "text.book.closed",
            description: Text("B5 summary snapshots + TOC render in the chat panel.")
        )
    }
}
