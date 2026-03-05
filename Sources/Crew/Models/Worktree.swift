import Foundation

/// Status of an agent workspace / git worktree.
enum WorktreeStatus: String, Codable, CaseIterable {
    case idle
    case running
    case completed
    case error
}

/// Represents an isolated git worktree where an agent operates.
struct Worktree: Identifiable, Codable, Hashable {
    var id: UUID
    var repoId: UUID
    var branch: String
    var path: String
    var status: WorktreeStatus
    var selectedModel: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        repoId: UUID,
        branch: String,
        path: String,
        status: WorktreeStatus = .idle,
        selectedModel: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.repoId = repoId
        self.branch = branch
        self.path = path
        self.status = status
        self.selectedModel = selectedModel
        self.createdAt = createdAt
    }
}
