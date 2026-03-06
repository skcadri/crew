import Foundation

// MARK: - Phase A Shared Models (A2/A3/A4/A5 glue)

/// Normalized lifecycle for CI checks, regardless of provider.
enum CheckLifecycleState: String, Codable, CaseIterable {
    case queued
    case inProgress = "in_progress"
    case success
    case failed
    case cancelled
    case neutral
    case skipped
}

/// A provider-agnostic check record used by Checks UI + review gating.
struct CheckRecord: Identifiable, Codable, Hashable {
    var id: String
    var worktreeId: UUID
    var provider: String         // e.g. "github"
    var externalId: String       // provider-native identifier
    var name: String
    var status: CheckLifecycleState
    var detailsURL: String?
    var summary: String?
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        worktreeId: UUID,
        provider: String,
        externalId: String,
        name: String,
        status: CheckLifecycleState,
        detailsURL: String? = nil,
        summary: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.provider = provider
        self.externalId = externalId
        self.name = name
        self.status = status
        self.detailsURL = detailsURL
        self.summary = summary
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }
}

/// Shared review state for a worktree/PR. A5 can drive transitions; A2/A3/A4 can read it.
enum ReviewWorkflowState: String, Codable, CaseIterable {
    case idle
    case awaitingChecks
    case readyForReview
    case changesRequested
    case approved
    case merged
}

struct ReviewStateSnapshot: Identifiable, Codable, Hashable {
    var id: String
    var worktreeId: UUID
    var pullRequestNumber: Int?
    var state: ReviewWorkflowState
    var blockingCheckCount: Int
    var unresolvedThreadCount: Int
    var lastSyncedAt: Date?
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        worktreeId: UUID,
        pullRequestNumber: Int? = nil,
        state: ReviewWorkflowState = .idle,
        blockingCheckCount: Int = 0,
        unresolvedThreadCount: Int = 0,
        lastSyncedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.pullRequestNumber = pullRequestNumber
        self.state = state
        self.blockingCheckCount = blockingCheckCount
        self.unresolvedThreadCount = unresolvedThreadCount
        self.lastSyncedAt = lastSyncedAt
        self.updatedAt = updatedAt
    }
}

/// Provider-neutral PR comment/thread model to keep A4 merge-safe.
enum ReviewCommentResolution: String, Codable, CaseIterable {
    case unresolved
    case resolved
}

struct ReviewCommentRecord: Identifiable, Codable, Hashable {
    var id: String
    var worktreeId: UUID
    var provider: String
    var externalId: String
    var threadId: String?
    var filePath: String?
    var line: Int?
    var author: String
    var body: String
    var resolution: ReviewCommentResolution
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        worktreeId: UUID,
        provider: String,
        externalId: String,
        threadId: String? = nil,
        filePath: String? = nil,
        line: Int? = nil,
        author: String,
        body: String,
        resolution: ReviewCommentResolution = .unresolved,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.provider = provider
        self.externalId = externalId
        self.threadId = threadId
        self.filePath = filePath
        self.line = line
        self.author = author
        self.body = body
        self.resolution = resolution
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Adapter Protocols (extension points, no heavy services)

protocol ChecksDataProviding {
    func checks(for worktreeId: UUID) async throws -> [CheckRecord]
}

protocol ReviewCommentsProviding {
    func comments(for worktreeId: UUID) async throws -> [ReviewCommentRecord]
}

protocol ReviewStateProviding {
    func reviewState(for worktreeId: UUID) async throws -> ReviewStateSnapshot?
}
