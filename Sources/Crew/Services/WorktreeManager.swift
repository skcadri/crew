import Foundation
import Combine

// MARK: - WorktreeManager

/// Observable service that manages the lifecycle of git worktrees / agent workspaces.
/// Mirrors `RepoManager` in shape — clone → persist → publish.
@MainActor
final class WorktreeManager: ObservableObject {

    // MARK: Singleton

    static let shared = WorktreeManager()

    // MARK: Published State

    @Published var worktrees: [Worktree] = []
    @Published var lastError: String? = nil

    // MARK: Dependencies

    private let db = Database.shared

    private init() {
        loadAllWorktrees()
    }

    // MARK: - Load

    /// Populate `worktrees` for a single repo from the database.
    func loadWorktrees(repoId: UUID) {
        do {
            let repoWorktrees = try db.fetchWorktrees(forRepo: repoId)
            // Replace entries for this repo; keep entries from other repos intact.
            let others = worktrees.filter { $0.repoId != repoId }
            worktrees = others + repoWorktrees
        } catch {
            lastError = "Failed to load worktrees: \(error.localizedDescription)"
        }
    }

    /// Populate `worktrees` for all repos from the database.
    func loadAllWorktrees() {
        do {
            worktrees = try db.fetchAllWorktrees()
        } catch {
            lastError = "Failed to load worktrees: \(error.localizedDescription)"
        }
    }

    // MARK: - Create

    /// Creates a git worktree for `repoPath` on a new `branch`, persists it, and appends it
    /// to the published list.
    func createWorkspace(
        repoId:   UUID,
        repoPath: String,
        branch:   String,
        model:    AgentType?
    ) async throws {
        let path = try await GitService.createWorktree(repoPath: repoPath, branch: branch)

        let worktree = Worktree(
            repoId:        repoId,
            branch:        branch,
            path:          path,
            status:        .idle,
            selectedModel: model?.rawValue
        )

        try db.insertWorktree(worktree)
        worktrees.append(worktree)
    }

    // MARK: - Delete

    /// Removes a git worktree from disk and the database, then refreshes the published list.
    func deleteWorkspace(id: UUID) async throws {
        guard let worktree = worktrees.first(where: { $0.id == id }) else { return }

        // Attempt git worktree remove; look up the repo path from the DB.
        if let repo = try? db.fetchRepository(id: worktree.repoId) {
            try? await GitService.deleteWorktree(
                repoPath:     repo.localPath,
                worktreePath: worktree.path
            )
        }

        // Belt-and-suspenders: remove the directory if git didn't clean it up.
        let fm = FileManager.default
        if fm.fileExists(atPath: worktree.path) {
            try? fm.removeItem(atPath: worktree.path)
        }

        try db.deleteWorktree(id: id)
        worktrees.removeAll { $0.id == id }
    }

    // MARK: - Update Status

    func updateStatus(id: UUID, status: WorktreeStatus) {
        guard let idx = worktrees.firstIndex(where: { $0.id == id }) else { return }
        worktrees[idx].status = status
        try? db.updateWorktreeStatus(id: id, status: status)
    }

    // MARK: - Helpers

    /// Returns all worktrees for a given repo, preserving publish-list order.
    func worktrees(for repoId: UUID) -> [Worktree] {
        worktrees.filter { $0.repoId == repoId }
    }
}
