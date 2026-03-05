import Foundation
import Combine

// MARK: - RepoManager

/// Observable class that manages the lifecycle of repositories:
/// cloning, persisting to SQLite, and removing from disk.
@MainActor
final class RepoManager: ObservableObject {

    // MARK: Singleton

    static let shared = RepoManager()

    // MARK: Published State

    @Published var repos: [Repository] = []
    @Published var isCloning: Bool = false
    @Published var cloneProgress: String = ""
    @Published var lastError: String? = nil

    // MARK: Dependencies

    private let git = GitService.shared
    private let db  = Database.shared

    private init() {
        loadRepos()
    }

    // MARK: - Load

    /// Populate `repos` from the SQLite database.
    func loadRepos() {
        do {
            repos = try db.fetchAllRepositories()
        } catch {
            lastError = "Failed to load repositories: \(error.localizedDescription)"
        }
    }

    // MARK: - Add

    /// Clone `url`, insert into the database, and refresh the list.
    func addRepo(url: String) async throws {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GitError.invalidURL("URL cannot be empty")
        }

        isCloning = true
        cloneProgress = "Cloning…"
        lastError = nil

        defer {
            isCloning = false
            cloneProgress = ""
        }

        // Run git clone (throws on failure)
        let localPath = try await git.cloneRepo(url: url)

        // Derive a display name from the path
        let name = URL(fileURLWithPath: localPath).lastPathComponent

        let repo = Repository(
            name:      name,
            url:       url,
            localPath: localPath
        )

        try db.insertRepository(repo)
        repos.append(repo)
    }

    // MARK: - Remove

    /// Delete a repository from the database and its directory from disk.
    func removeRepo(id: UUID) {
        guard let repo = repos.first(where: { $0.id == id }) else { return }

        // Remove from DB
        do {
            try db.deleteRepository(id: id)
        } catch {
            lastError = "DB delete failed: \(error.localizedDescription)"
            return
        }

        // Remove from disk (best-effort; ignore if already gone)
        try? git.removeRepoDirectory(atPath: repo.localPath)

        // Remove from published list
        repos.removeAll { $0.id == id }
    }
}
