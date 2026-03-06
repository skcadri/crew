import SwiftUI

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedWorkspaceID: String? = nil
    @State private var showAddWorkspaceSheet: Bool = false

    @ObservedObject private var worktreeManager = WorktreeManager.shared
    @ObservedObject private var repoManager = RepoManager.shared

    /// Active ChatStore instances keyed by worktree UUID string
    @State private var chatStores: [String: ChatStore] = [:]

    private var windowTitle: String {
        guard let id = selectedWorkspaceID else { return "Crew" }
        if let wt = selectedWorktree { return wt.branch }
        if id.hasPrefix("repo-") { return id.replacingOccurrences(of: "repo-", with: "") }
        return id
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selectedWorkspaceID: $selectedWorkspaceID)
            } content: {
                if let worktree = selectedWorktree {
                    let store = chatStore(for: worktree)
                    ChatView(
                        store: store,
                        worktreeId: worktree.id,
                        modelName: worktree.selectedModel
                    )
                } else {
                    DetailPlaceholder(selectedWorkspaceID: selectedWorkspaceID)
                }
            } detail: {
                if let worktree = selectedWorktree {
                    GitPanelView(repoPath: worktree.path, workspaceId: worktree.id.uuidString)
                } else {
                    InspectorView(selectedWorkspaceID: selectedWorkspaceID)
                }
            }
            .navigationSplitViewStyle(.balanced)

            StatusBar(selectedWorkspaceID: selectedWorkspaceID)
        }
        .navigationTitle(windowTitle)
        .onReceive(NotificationCenter.default.publisher(for: .crewNewWorkspace)) { _ in
            showAddWorkspaceSheet = true
        }
        .sheet(isPresented: $showAddWorkspaceSheet) {
            if let repo = selectedRepo {
                CreateWorkspaceSheet(repo: repo, worktreeManager: worktreeManager)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Add a repository first")
                        .font(.title3)
                    Button("Close") { showAddWorkspaceSheet = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
                .frame(width: 400, height: 250)
            }
        }
    }

    // MARK: - Helpers

    private var selectedRepo: Repository? {
        guard let id = selectedWorkspaceID else { return repoManager.repos.first }
        if id.hasPrefix("repo-") {
            let uuidString = String(id.dropFirst("repo-".count))
            return repoManager.repos.first { $0.id.uuidString == uuidString }
        }
        if let wt = selectedWorktree {
            return repoManager.repos.first { $0.id == wt.repoId }
        }
        return repoManager.repos.first
    }

    private var selectedWorktree: Worktree? {
        guard let id = selectedWorkspaceID,
              id.hasPrefix("worktree-") else { return nil }
        let uuidString = String(id.dropFirst("worktree-".count))
        return worktreeManager.worktrees.first { $0.id.uuidString == uuidString }
    }

    private func chatStore(for worktree: Worktree) -> ChatStore {
        let key = worktree.id.uuidString
        if let existing = chatStores[key] { return existing }
        let store = ChatStore()
        chatStores[key] = store
        return store
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    let selectedWorkspaceID: String?

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
            Circle()
                .fill(selectedWorkspaceID != nil ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)

            Text(agentStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !modelName.isEmpty {
                Divider().frame(height: 12)
                Label(modelName, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
