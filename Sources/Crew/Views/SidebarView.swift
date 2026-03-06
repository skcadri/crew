import SwiftUI

struct SidebarView: View {
    @Binding var selectedWorkspaceID: String?

    @ObservedObject private var repoManager = RepoManager.shared
    @ObservedObject private var worktreeManager = WorktreeManager.shared

    @State private var showAddRepo: Bool = false
    @State private var repoToDelete: Repository? = nil
    @State private var showDeleteConfirmation: Bool = false

    var body: some View {
        List(selection: $selectedWorkspaceID) {

            // MARK: Repositories Section
            Section {
                if repoManager.repos.isEmpty {
                    Label("No repos yet — add one to get started", systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(repoManager.repos) { repo in
                        RepoRow(repo: repo)
                            .tag("repo-\(repo.id.uuidString)")
                            .contextMenu {
                                Button(role: .destructive) {
                                    repoToDelete = repo
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Remove Repository", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Repositories")
                    Spacer()
                    Button {
                        showAddRepo = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Add Repository")
                }
            }

            // MARK: Workspaces Section
            Section("Workspaces") {
                if worktreeManager.worktrees.isEmpty {
                    Label("No workspaces yet — click + to add one", systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(worktreeManager.worktrees) { worktree in
                        WorkspaceRow(worktree: worktree)
                            .tag("worktree-\(worktree.id.uuidString)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Crew")
        .onAppear {
            worktreeManager.loadAllWorktrees()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddRepo = true
                    } label: {
                        Label("Add Repository", systemImage: "folder.badge.plus")
                    }

                    Button {
                        NotificationCenter.default.post(name: .crewNewWorkspace, object: nil)
                    } label: {
                        Label("New Workspace", systemImage: "plus.square.on.square")
                    }

                    Button {
                        NotificationCenter.default.post(name: .crewNewWorkspaceFromBranch, object: nil)
                    } label: {
                        Label("New Workspace from Branch…", systemImage: "arrow.triangle.branch")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Repository or New Workspace")
            }
        }
        // MARK: Add Repo Sheet
        .sheet(isPresented: $showAddRepo) {
            AddRepoSheet(repoManager: repoManager)
        }
        // MARK: Delete Confirmation
        .confirmationDialog(
            deleteTitle,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let repo = repoToDelete {
                    repoManager.removeRepo(id: repo.id)
                }
                repoToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                repoToDelete = nil
            }
        } message: {
            if let repo = repoToDelete {
                Text("\"\(repo.name)\" will be removed from Crew and deleted from disk. This cannot be undone.")
            }
        }
    }

    private var deleteTitle: String {
        if let repo = repoToDelete {
            return "Remove \"\(repo.name)\"?"
        }
        return "Remove Repository?"
    }
}

#Preview {
    SidebarView(selectedWorkspaceID: .constant(nil))
        .frame(width: 240, height: 500)
}
