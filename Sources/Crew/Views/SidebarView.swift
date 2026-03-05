import SwiftUI

struct SidebarView: View {
    @Binding var selectedWorkspaceID: String?

    // Placeholder data — replaced in TICKET-003 & TICKET-004
    private let sampleRepos = ["my-app", "backend-api"]
    private let sampleWorkspaces = [
        WorkspacePlaceholder(id: "ws-1", name: "feature/auth", status: .idle),
        WorkspacePlaceholder(id: "ws-2", name: "fix/login-bug", status: .running),
    ]

    var body: some View {
        List(selection: $selectedWorkspaceID) {
            Section("Repositories") {
                if sampleRepos.isEmpty {
                    Text("No repos yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(sampleRepos, id: \.self) { repo in
                        Label(repo, systemImage: "folder")
                            .tag(repo)
                    }
                }
            }

            Section("Workspaces") {
                if sampleWorkspaces.isEmpty {
                    Text("No workspaces yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(sampleWorkspaces) { ws in
                        WorkspaceRowPlaceholder(workspace: ws)
                            .tag(ws.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Crew")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    // TICKET-004: Open new workspace sheet
                }) {
                    Image(systemName: "plus")
                }
                .help("New Workspace")
            }
        }
    }
}

// MARK: - Placeholder Models (replaced by real models in TICKET-002)

struct WorkspacePlaceholder: Identifiable {
    let id: String
    let name: String
    let status: WorkspaceStatusPlaceholder
}

enum WorkspaceStatusPlaceholder {
    case idle, running, review, done, error

    var icon: String {
        switch self {
        case .idle:    return "🟢"
        case .running: return "🔵"
        case .review:  return "🟡"
        case .done:    return "✅"
        case .error:   return "🔴"
        }
    }
}

struct WorkspaceRowPlaceholder: View {
    let workspace: WorkspacePlaceholder

    var body: some View {
        HStack {
            Text(workspace.status.icon)
                .font(.system(size: 10))
            Label(workspace.name, systemImage: "wrench.and.screwdriver")
                .lineLimit(1)
        }
    }
}

#Preview {
    SidebarView(selectedWorkspaceID: .constant(nil))
        .frame(width: 240, height: 500)
}
