import SwiftUI

struct SidebarView: View {
    @Binding var selectedWorkspaceID: String?

    @ObservedObject private var repoManager = RepoManager.shared

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
                Text("No workspaces yet")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                // TICKET-004 will populate this section
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Crew")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddRepo = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Repository")
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
