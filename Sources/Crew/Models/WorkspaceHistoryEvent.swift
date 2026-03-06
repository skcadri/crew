import Foundation

enum WorkspaceHistoryEventType: String, Codable, CaseIterable {
    case created
    case statusChanged = "status_changed"
    case archived
    case unarchived
}

struct WorkspaceHistoryEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var worktreeId: UUID
    var eventType: WorkspaceHistoryEventType
    var fromStatus: WorktreeStatus?
    var toStatus: WorktreeStatus
    var metadata: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        eventType: WorkspaceHistoryEventType,
        fromStatus: WorktreeStatus? = nil,
        toStatus: WorktreeStatus,
        metadata: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.eventType = eventType
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.metadata = metadata
        self.createdAt = createdAt
    }
}
