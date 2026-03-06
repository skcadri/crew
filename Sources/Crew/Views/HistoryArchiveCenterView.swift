import SwiftUI

struct HistoryArchiveCenterView: View {
    @ObservedObject private var worktreeManager = WorktreeManager.shared
    @ObservedObject private var repoManager = RepoManager.shared

    @State private var searchText: String = ""
    @State private var selectedStatus: WorktreeStatus? = nil
    @State private var selectedRepoId: UUID? = nil
    @State private var selectedWorkspaceId: UUID? = nil
    @State private var timeline: [WorkspaceHistoryEvent] = []

    private let db = Database.shared

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                filterBar

                List(filteredWorkspaces, selection: $selectedWorkspaceId) { workspace in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(workspace.branch)
                                .font(.headline)
                            Spacer()
                            Text(workspace.status.title)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(statusColor(workspace.status).opacity(0.15), in: Capsule())
                                .foregroundStyle(statusColor(workspace.status))
                        }

                        Text(repoName(for: workspace.repoId))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(workspace.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                    .tag(workspace.id)
                }
            }
            .padding(12)
            .frame(minWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                if let workspace = selectedWorkspace {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workspace.branch)
                                .font(.title3.bold())
                            Text(repoName(for: workspace.repoId))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(workspace.status == .archived ? "Unarchive" : "Archive") {
                            let target: WorktreeStatus = workspace.status == .archived ? .backlog : .archived
                            worktreeManager.transition(workspace.id, to: target)
                            reloadTimeline(for: workspace.id)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    Text("Metadata Timeline")
                        .font(.headline)

                    if timeline.isEmpty {
                        ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath")
                    } else {
                        List(timeline) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(eventTitle(event))
                                    .font(.subheadline.weight(.medium))
                                Text(event.metadata ?? "No additional metadata")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    ContentUnavailableView("Select a workspace", systemImage: "clock.badge.questionmark", description: Text("Choose a workspace from history to view archive actions and timeline metadata."))
                }
            }
            .padding(12)
            .frame(minWidth: 420)
        }
        .navigationTitle("History & Archive Center")
        .onAppear {
            if selectedWorkspaceId == nil {
                selectedWorkspaceId = filteredWorkspaces.first?.id
            }
            reloadTimelineForSelection()
        }
        .onChange(of: selectedWorkspaceId) { _, _ in
            reloadTimelineForSelection()
        }
        .onChange(of: worktreeManager.worktrees) { _, _ in
            if selectedWorkspaceId == nil {
                selectedWorkspaceId = filteredWorkspaces.first?.id
            }
            reloadTimelineForSelection()
        }
    }

    private var selectedWorkspace: Worktree? {
        guard let selectedWorkspaceId else { return nil }
        return worktreeManager.worktrees.first(where: { $0.id == selectedWorkspaceId })
    }

    private var filteredWorkspaces: [Worktree] {
        worktreeManager.worktrees
            .filter { workspace in
                if let selectedRepoId, workspace.repoId != selectedRepoId {
                    return false
                }
                if let selectedStatus, workspace.status != selectedStatus {
                    return false
                }
                if searchText.isEmpty {
                    return true
                }
                let needle = searchText.lowercased()
                return workspace.branch.lowercased().contains(needle)
                    || workspace.path.lowercased().contains(needle)
                    || repoName(for: workspace.repoId).lowercased().contains(needle)
            }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.status.title < rhs.status.title
            }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search branch, path, or repository", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Status", selection: $selectedStatus) {
                    Text("All statuses").tag(WorktreeStatus?.none)
                    ForEach(WorktreeStatus.allCases) { status in
                        Text(status.title).tag(WorktreeStatus?.some(status))
                    }
                }
                .pickerStyle(.menu)

                Picker("Repository", selection: $selectedRepoId) {
                    Text("All repos").tag(UUID?.none)
                    ForEach(repoManager.repos) { repo in
                        Text(repo.name).tag(UUID?.some(repo.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func reloadTimelineForSelection() {
        guard let selectedWorkspaceId else {
            timeline = []
            return
        }
        reloadTimeline(for: selectedWorkspaceId)
    }

    private func reloadTimeline(for workspaceId: UUID) {
        timeline = (try? db.fetchWorkspaceHistoryEvents(worktreeId: workspaceId)) ?? []
    }

    private func repoName(for repoId: UUID) -> String {
        repoManager.repos.first(where: { $0.id == repoId })?.name ?? "Unknown Repository"
    }

    private func eventTitle(_ event: WorkspaceHistoryEvent) -> String {
        switch event.eventType {
        case .created:
            return "Workspace created"
        case .archived:
            return "Archived"
        case .unarchived:
            return "Unarchived"
        case .statusChanged:
            if let fromStatus = event.fromStatus {
                return "Status: \(fromStatus.title) → \(event.toStatus.title)"
            }
            return "Status changed to \(event.toStatus.title)"
        }
    }

    private func statusColor(_ status: WorktreeStatus) -> Color {
        switch status {
        case .backlog: return .gray
        case .inProgress: return .blue
        case .inReview: return .orange
        case .done: return .green
        case .archived: return .secondary
        }
    }
}

#Preview {
    HistoryArchiveCenterView()
        .frame(width: 1200, height: 700)
}
