import Foundation

/// Role of a chat participant.
enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
}

/// Structured, persisted question that pauses agent flow until answered.
struct PendingQuestion: Identifiable, Codable, Hashable {
    var id: UUID
    var worktreeId: UUID
    var prompt: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        prompt: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.prompt = prompt
        self.createdAt = createdAt
    }
}

/// A single chat message in a worktree conversation.
struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var worktreeId: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
