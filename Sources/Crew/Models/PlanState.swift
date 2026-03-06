import Foundation

/// Lifecycle for plan-mode approval in a workspace chat.
enum PlanApprovalStatus: String, Codable, CaseIterable {
    case none
    case awaitingApproval = "awaiting_approval"
    case approved
    case rejected
}

/// Persisted plan-mode state scoped per worktree (workspace/chat).
struct PlanState: Codable, Hashable {
    var worktreeId: UUID
    var status: PlanApprovalStatus
    var planText: String
    var feedback: String?
    var updatedAt: Date

    init(
        worktreeId: UUID,
        status: PlanApprovalStatus = .none,
        planText: String = "",
        feedback: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.worktreeId = worktreeId
        self.status = status
        self.planText = planText
        self.feedback = feedback
        self.updatedAt = updatedAt
    }

    var isAwaitingApproval: Bool {
        status == .awaitingApproval
    }
}
