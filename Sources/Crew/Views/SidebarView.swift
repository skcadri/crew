import SwiftUI

struct SidebarView: View {
    @Binding var selectedWorkspaceID: String?

    @ObservedObject private var repoManager = RepoManager.shared
    @ObservedObject private var worktreeManager = WorktreeManager.shared

    @State private var showAddRepo: Bool = false
    @State private var repoToDelete: Repository? = nil
    @State private var showDeleteConfirmation: Bool = false

    @State private var showArchived: Bool = false
    @State private var statusFilters: Set<WorktreeStatus> = Set(WorktreeStatus.allCases.filter { $0 != .archived })

    var body: some View {
        List(selection: $selectedWorkspaceID) {

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

            if filteredWorktrees.isEmpty {
                Section("Workspaces") {
                    Label("No matching workspaces", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else {
                ForEach(groupedWorktrees, id: \.status) { group in
                    Section(group.status.title) {
                        ForEach(group.worktrees) { worktree in
                            WorkspaceRow(worktree: worktree) { newStatus in
                                worktreeManager.transition(worktree.id, to: newStatus)
                            }
                            .tag("worktree-\(worktree.id.uuidString)")
                            .contextMenu {
                                statusContextMenu(for: worktree)
                            }
                        }
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
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Toggle("Show Archived", isOn: $showArchived)

                    Divider()

                    ForEach(WorktreeStatus.allCases.filter { showArchived || $0 != .archived }) { status in
                        let binding = Binding(
                            get: { statusFilters.contains(status) },
                            set: { included in
                                if included { statusFilters.insert(status) }
                                else { statusFilters.remove(status) }
                            }
                        )
                        Toggle(status.title, isOn: binding)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .help("Filter Workspaces")
            }

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
        .onChange(of: showArchived) { _, newValue in
            if newValue {
                statusFilters.insert(.archived)
            } else {
                statusFilters.remove(.archived)
            }
        }
        .sheet(isPresented: $showAddRepo) {
            AddRepoSheet(repoManager: repoManager)
        }
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

    private var visibleWorktrees: [Worktree] {
        if showArchived {
            return worktreeManager.worktrees
        }
        return worktreeManager.worktrees.filter { $0.status != .archived }
    }

    private var filteredWorktrees: [Worktree] {
        visibleWorktrees.filter { statusFilters.contains($0.status) }
    }

    private var groupedWorktrees: [(status: WorktreeStatus, worktrees: [Worktree])] {
        let sorted = filteredWorktrees.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.createdAt < rhs.createdAt
            }
            return statusOrder(lhs.status) < statusOrder(rhs.status)
        }

        let grouped = Dictionary(grouping: sorted, by: \.status)
        return WorktreeStatus.allCases.compactMap { status in
            guard let items = grouped[status], !items.isEmpty else { return nil }
            return (status, items)
        }
    }

    private func statusOrder(_ status: WorktreeStatus) -> Int {
        switch status {
        case .backlog: return 0
        case .inProgress: return 1
        case .inReview: return 2
        case .done: return 3
        case .archived: return 4
        }
    }

    @ViewBuilder
    private func statusContextMenu(for worktree: Worktree) -> some View {
        ForEach(WorktreeStatus.allCases) { status in
            Button {
                worktreeManager.transition(worktree.id, to: status)
            } label: {
                Label(status.title, systemImage: status == worktree.status ? "checkmark" : "arrow.right")
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
