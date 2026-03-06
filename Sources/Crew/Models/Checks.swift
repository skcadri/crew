import Foundation

struct CICheck: Identifiable, Hashable {
    enum Status: String, Hashable {
        case pending
        case success
        case failure

        var label: String {
            switch self {
            case .pending: return "Pending"
            case .success: return "Passing"
            case .failure: return "Failing"
            }
        }
    }

    let id: UUID
    let name: String
    let status: Status
    let details: String

    init(id: UUID = UUID(), name: String, status: Status, details: String) {
        self.id = id
        self.name = name
        self.status = status
        self.details = details
    }
}

struct CheckTODOItem: Identifiable, Hashable {
    let id: UUID
    let worktreeId: UUID
    var title: String
    var isDone: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        title: String,
        isDone: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

struct GitStatusSummary {
    var modified: Int = 0
    var added: Int = 0
    var deleted: Int = 0
    var untracked: Int = 0

    var totalChanges: Int { modified + added + deleted + untracked }
}
