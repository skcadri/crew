import Foundation

struct ChatTOCEntry: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var level: Int
    var messageId: UUID

    init(id: String = UUID().uuidString, title: String, level: Int, messageId: UUID) {
        self.id = id
        self.title = title
        self.level = max(1, min(level, 6))
        self.messageId = messageId
    }
}

struct ChatSummarySnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var worktreeId: UUID
    var summary: String
    var tocEntries: [ChatTOCEntry]
    var messageCount: Int
    var characterCount: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        worktreeId: UUID,
        summary: String,
        tocEntries: [ChatTOCEntry],
        messageCount: Int,
        characterCount: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.summary = summary
        self.tocEntries = tocEntries
        self.messageCount = messageCount
        self.characterCount = characterCount
        self.updatedAt = updatedAt
    }
}
