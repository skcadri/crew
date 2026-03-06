import SwiftUI

struct SidebarView: View {
    @Binding var selectedWorkspaceID: String?

    @ObservedObject private var repoManager     = RepoManager.shared
    @ObservedObject private var worktreeManager = WorktreeManager.shared

    // Sheet / dialog state
    @State private var showAddRepo:             Bool = false
    @State private var repoToDelete:            Repository? = nil
    @State private var showDeleteRepoConfirm:   Bool = false
    @State private var repoForNewWorkspace:     Repository? = nil
    @State private var worktreeToDelete:        Worktree? = nil
    @State private var showDeleteWTConfirm:     Bool = false

    // Disclosure-group expanded state per repo
    @State private var expandedRepos: Set<UUID> = []

    var body: some View {
        List(selection: $selectedWorkspaceID) {

            // ── Repositories ───────────────────────────────────────────
            Section {
                if repoManager.repos.isEmpty {
                    Label("No repos yet — add one to get started", systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(repoManager.repos) { repo in
                        repoDisclosureGroup(repo)
                    }
                }
            } header: {
                HStack {
                    Text("Repositories")
                    Spacer()
                    Button { showAddRepo = true } label: {
                        Image(systemName: "plus").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Add Repository")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Crew")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddRepo = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add Repository")
            }
        }

        // ── Add Repo Sheet ────────────────────────────────────────────
        .sheet(isPresented: $showAddRepo) {
            AddRepoSheet(repoManager: repoManager)
        }

        // ── Create Workspace Sheet ────────────────────────────────────
        .sheet(item: $repoForNewWorkspace) { repo in
            CreateWorkspaceSheet(repo: repo, worktreeManager: worktreeManager)
        }

        // ── Delete Repo Confirmation ──────────────────────────────────
        .confirmationDialog(
            deleteRepoTitle,
            isPresented: $showDeleteRepoConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let repo = repoToDelete { repoManager.removeRepo(id: repo.id) }
                repoToDelete = nil
            }
            Button("Cancel", role: .cancel) { repoToDelete = nil }
        } message: {
            if let repo = repoToDelete {
                Text("\"\(repo.name)\" will be removed from Crew and deleted from disk. This cannot be undone.")
            }
        }

        // ── Delete Worktree Confirmation ──────────────────────────────
        .confirmationDialog(
            deleteWTTitle,
            isPresented: $showDeleteWTConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let wt = worktreeToDelete {
                    Task { try? await worktreeManager.deleteWorkspace(id: wt.id) }
                }
                worktreeToDelete = nil
            }
            Button("Cancel", role: .cancel) { worktreeToDelete = nil }
        } message: {
            if let wt = worktreeToDelete {
                Text("The worktree for branch \"\(wt.branch)\" will be deleted from disk.")
            }
        }
    }

    // MARK: - Repo DisclosureGroup

    @ViewBuilder
    private func repoDisclosureGroup(_ repo: Repository) -> some View {
        let isExpanded = Binding<Bool>(
            get: { expandedRepos.contains(repo.id) },
            set: { open in
                if open { expandedRepos.insert(repo.id) }
                else { expandedRepos.remove(repo.id) }
            }
        )

        DisclosureGroup(isExpanded: isExpanded) {
            // ── Worktrees nested under this repo ──────────────────────
            let repoWorktrees = worktreeManager.worktrees(for: repo.id)
            if repoWorktrees.isEmpty {
                Text("No workspaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            } else {
                ForEach(repoWorktrees) { wt in
                    WorkspaceRow(worktree: wt)
                        .tag("worktree-\(wt.id.uuidString)")
                        .contextMenu {
                            Button(role: .destructive) {
                                worktreeToDelete = wt
                                showDeleteWTConfirm = true
                            } label: {
                                Label("Delete Workspace", systemImage: "trash")
                            }
                        }
                }
            }

            // ── Add Workspace button ──────────────────────────────────
            Button {
                repoForNewWorkspace = repo
            } label: {
                Label("New Workspace", systemImage: "plus")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.top, 2)
        } label: {
            RepoRow(repo: repo)
                .tag("repo-\(repo.id.uuidString)")
                .contextMenu {
                    Button {
                        repoForNewWorkspace = repo
                    } label: {
                        Label("New Workspace", systemImage: "plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        repoToDelete = repo
                        showDeleteRepoConfirm = true
                    } label: {
                        Label("Remove Repository", systemImage: "trash")
                    }
                }
                .onAppear {
                    // Auto-expand repos that have worktrees
                    if !worktreeManager.worktrees(for: repo.id).isEmpty {
                        expandedRepos.insert(repo.id)
                    }
                }
        }
    }

    // MARK: - Dialog titles

    private var deleteRepoTitle: String {
        repoToDelete.map { "Remove \"\($0.name)\"?" } ?? "Remove Repository?"
    }

    private var deleteWTTitle: String {
        worktreeToDelete.map { "Delete workspace \"\($0.branch)\"?" } ?? "Delete Workspace?"
    }
}

#Preview {
    SidebarView(selectedWorkspaceID: .constant(nil))
        .frame(width: 260, height: 500)
}
