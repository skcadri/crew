import SwiftUI

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedWorkspaceID: String? = nil
    @State private var showAddWorkspaceSheet: Bool = false

    // Derive a friendly window title from the selected workspace
    private var windowTitle: String {
        guard let id = selectedWorkspaceID else { return "Crew" }
        // If the ID is prefixed (e.g. "repo-UUID"), show a trimmed label
        if id.hasPrefix("repo-") {
            return id.replacingOccurrences(of: "repo-", with: "")
        }
        return id
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Left column: Sidebar
                SidebarView(selectedWorkspaceID: $selectedWorkspaceID)
            } content: {
                // Center column: Agent workspace / detail
                DetailPlaceholder(selectedWorkspaceID: selectedWorkspaceID)
            } detail: {
                // Right column: Inspector
                InspectorView(selectedWorkspaceID: selectedWorkspaceID)
            }
            .navigationSplitViewStyle(.balanced)

            // MARK: Bottom Status Bar
            StatusBar(selectedWorkspaceID: selectedWorkspaceID)
        }
        .navigationTitle(windowTitle)
        // Respond to "New Workspace" keyboard shortcut / menu
        .onReceive(NotificationCenter.default.publisher(for: .crewNewWorkspace)) { _ in
            showAddWorkspaceSheet = true
        }
        .sheet(isPresented: $showAddWorkspaceSheet) {
            NewWorkspacePlaceholderSheet()
        }
    }
}

// MARK: - Status Bar

/// Thin bottom bar showing the current agent status and model name.
struct StatusBar: View {
    let selectedWorkspaceID: String?

    // These would be driven by AgentManager / SettingsStore in a full build.
    private var agentStatus: String {
        guard selectedWorkspaceID != nil else { return "No workspace selected" }
        return "Idle"
    }

    private var modelName: String {
        guard selectedWorkspaceID != nil else { return "" }
        return UserDefaults.standard.string(forKey: "defaultModel") ?? "Claude Code"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            Text(agentStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !modelName.isEmpty {
                Divider()
                    .frame(height: 12)

                Label(modelName, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var dotColor: Color {
        // Will be wired to real AgentManager state in future tickets
        selectedWorkspaceID != nil ? .green : .secondary
    }
}

// MARK: - New Workspace Placeholder Sheet

/// Temporary placeholder until TICKET-004 / CreateWorkspaceSheet is wired up.
private struct NewWorkspacePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("New Workspace")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Workspace creation will be fully wired up in TICKET-004.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 400, height: 300)
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
