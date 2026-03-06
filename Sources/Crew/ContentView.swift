import SwiftUI

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedWorkspaceID: String? = nil

    @ObservedObject private var worktreeManager = WorktreeManager.shared

    /// Active ChatStore instances keyed by worktree UUID string, so state survives
    /// switching between worktrees without re-creating the store every time.
    @State private var chatStores: [String: ChatStore] = [:]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left column: Sidebar
            SidebarView(selectedWorkspaceID: $selectedWorkspaceID)
        } content: {
            // Center column: Agent chat panel (or placeholder)
            if let worktree = selectedWorktree {
                let store = chatStore(for: worktree)
                ChatView(
                    store:       store,
                    worktreeId:  worktree.id,
                    modelName:   worktree.selectedModel
                )
            } else {
                DetailPlaceholder(selectedWorkspaceID: selectedWorkspaceID)
            }
        } detail: {
            // Right column: Git panel (or placeholder inspector)
            if let worktree = selectedWorktree {
                GitPanelView(repoPath: worktree.path)
            } else {
                InspectorView(selectedWorkspaceID: selectedWorkspaceID)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Helpers

    /// Resolve the currently selected worktree from the selection tag.
    private var selectedWorktree: Worktree? {
        guard let id = selectedWorkspaceID,
              id.hasPrefix("worktree-") else { return nil }
        let uuidString = String(id.dropFirst("worktree-".count))
        return worktreeManager.worktrees.first { $0.id.uuidString == uuidString }
    }

    /// Retrieve or lazily create a ChatStore for the given worktree.
    private func chatStore(for worktree: Worktree) -> ChatStore {
        let key = worktree.id.uuidString
        if let existing = chatStores[key] { return existing }
        let store = ChatStore()
        chatStores[key] = store
        return store
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
