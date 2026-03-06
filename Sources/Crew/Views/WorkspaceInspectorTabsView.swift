import SwiftUI

struct WorkspaceInspectorTabsView: View {
    let repoPath: String
    let worktreeId: UUID

    @StateObject private var workspaceSurfaceRouter = WorkspaceSurfaceRouter.shared

    private var workspaceKey: String { worktreeId.uuidString }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workspace tab", selection: selectedTabBinding) {
                ForEach(WorkspaceSurfaceTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            Group {
                switch workspaceSurfaceRouter.selectedTab(for: workspaceKey) {
                case .plan:
                    PlanPanelPlaceholderView()
                case .questions:
                    QuestionsPanelPlaceholderView()
                case .notes:
                    NotesPanelPlaceholderView(repoPath: repoPath)
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

private struct PlanPanelPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Plan tab scaffolded",
            systemImage: "list.bullet.rectangle",
            description: Text("B1 approval-loop components will land here.")
        )
    }
}

private struct QuestionsPanelPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Questions tab scaffolded",
            systemImage: "questionmark.bubble",
            description: Text("B2 structured question UX plugs in here.")
        )
    }
}

private struct NotesPanelPlaceholderView: View {
    let repoPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes path")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(repoPath)/.context/notes.md")
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
        .padding()
    }
}

private struct SummaryPanelPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Summary tab scaffolded",
            systemImage: "text.book.closed",
            description: Text("B5 summary snapshots + TOC will render here.")
        )
    }
}
