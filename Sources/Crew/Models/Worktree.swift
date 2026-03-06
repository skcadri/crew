import Foundation

/// Status of an agent workspace / git worktree.
enum WorktreeStatus: String, Codable, CaseIterable, Identifiable {
    case backlog
    case inProgress = "in_progress"
    case inReview = "in_review"
    case done
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        case .archived: return "Archived"
        }
    }

    static func fromDatabaseValue(_ raw: String) -> WorktreeStatus {
        if let status = WorktreeStatus(rawValue: raw) {
            return status
        }

        // Legacy mappings from pre-A1 statuses.
        switch raw {
        case "idle": return .backlog
        case "running": return .inProgress
        case "completed": return .done
        case "error": return .inReview
        default: return .backlog
        }
    }
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
        status: WorktreeStatus = .backlog,
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
