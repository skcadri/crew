import Foundation

/// Represents a git repository managed by Crew.
struct Repository: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: String
    var localPath: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        localPath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.localPath = localPath
        self.createdAt = createdAt
    }
}
