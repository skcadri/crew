import SwiftUI

@MainActor
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var selectedWorkspaceID: String?

    @ObservedObject private var repoManager = RepoManager.shared
    @ObservedObject private var worktreeManager = WorktreeManager.shared
    @ObservedObject private var workspaceSurfaceRouter = WorkspaceSurfaceRouter.shared

    @State private var query: String = ""
    @State private var prNumbersByWorktree: [UUID: Int] = [:]

    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search workspace, repo, branch, or PR #", text: $query)
                .textFieldStyle(.roundedBorder)

            List(filteredEntries) { entry in
                Button {
                    run(entry)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.body.weight(.medium))
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(entry.kindLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(minHeight: 320)
        }
        .padding(14)
        .frame(width: 680, height: 430)
        .task {
            await hydratePRNumbers()
        }
    }

    private var filteredEntries: [PaletteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return allEntries }
        return allEntries.filter { $0.searchable.contains(q) }
    }

    private var allEntries: [PaletteEntry] {
        var entries: [PaletteEntry] = [
            PaletteEntry(
                title: "Next Unread Workspace",
                subtitle: "Jump to the next backlog workspace",
                searchable: "next unread backlog",
                kindLabel: "Action",
                action: .nextUnread
            ),
            PaletteEntry(
                title: "Next Needs Attention",
                subtitle: "Jump to workspace in review / active work",
                searchable: "next needs attention review",
                kindLabel: "Action",
                action: .nextNeedsAttention
            ),
            PaletteEntry(
                title: "Open Workspace Settings",
                subtitle: "Open app settings window",
                searchable: "settings workspace preferences",
                kindLabel: "Action",
                action: .openWorkspaceSettings
            )
        ]

        for worktree in worktreeManager.worktrees {
            let repo = repoManager.repos.first(where: { $0.id == worktree.repoId })
            let repoName = repo?.name ?? "Unknown Repo"
            let prText = prNumbersByWorktree[worktree.id].map { "PR #\($0)" } ?? "PR unknown"
            let subtitle = "\(repoName) • \(worktree.branch) • \(prText)"
            let searchable = [repoName, worktree.branch, prText, worktree.path, worktree.status.title]
                .joined(separator: " ")
                .lowercased()

            entries.append(
                PaletteEntry(
                    title: "\(repoName) / \(worktree.branch)",
                    subtitle: subtitle,
                    searchable: searchable,
                    kindLabel: "Workspace",
                    action: .openWorkspace(worktree.id)
                )
            )
        }

        return entries
    }

    private func run(_ entry: PaletteEntry) {
        switch entry.action {
        case .openWorkspace(let worktreeId):
            selectedWorkspaceID = "worktree-\(worktreeId.uuidString)"
            workspaceSurfaceRouter.setSelectedTab(.plan, for: worktreeId.uuidString)

        case .nextUnread:
            if let next = worktreeManager.worktrees
                .filter({ $0.status == .backlog })
                .sorted(by: { $0.createdAt < $1.createdAt })
                .first {
                selectedWorkspaceID = "worktree-\(next.id.uuidString)"
                workspaceSurfaceRouter.setSelectedTab(.plan, for: next.id.uuidString)
            }

        case .nextNeedsAttention:
            let priority = worktreeManager.worktrees
                .filter { $0.status == .inReview || $0.status == .inProgress }
                .sorted { lhs, rhs in
                    rank(lhs.status) < rank(rhs.status)
                }
            if let next = priority.first {
                selectedWorkspaceID = "worktree-\(next.id.uuidString)"
                workspaceSurfaceRouter.setSelectedTab(.questions, for: next.id.uuidString)
            }

        case .openWorkspaceSettings:
            openSettings()
        }

        isPresented = false
    }

    private func rank(_ status: WorktreeStatus) -> Int {
        switch status {
        case .inReview: return 0
        case .inProgress: return 1
        default: return 99
        }
    }

    private func hydratePRNumbers() async {
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for worktree in worktreeManager.worktrees {
                group.addTask {
                    do {
                        let metadata = try await GitHubChecksService.shared.fetchPullRequestMetadata(repoPath: worktree.path, branch: worktree.branch)
                        return (worktree.id, metadata.number)
                    } catch {
                        return (worktree.id, nil)
                    }
                }
            }

            var next: [UUID: Int] = [:]
            for await result in group {
                if let pr = result.1 {
                    next[result.0] = pr
                }
            }
            prNumbersByWorktree = next
        }
    }
}

private struct PaletteEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let searchable: String
    let kindLabel: String
    let action: PaletteAction
}

private enum PaletteAction {
    case openWorkspace(UUID)
    case nextUnread
    case nextNeedsAttention
    case openWorkspaceSettings
}
