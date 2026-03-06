import Foundation
import Combine

/// Observable store for chat messages in a single worktree.
/// Handles loading from and persisting to the SQLite database.
@MainActor
final class ChatStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var messages: [ChatMessage] = []

    /// True while an agent response is being streamed.
    @Published var isLoading: Bool = false

    /// Persisted plan-mode state for the current workspace chat.
    @Published private(set) var planState: PlanState?

    // MARK: - Current worktree

    private(set) var currentWorktreeId: UUID?

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Loads all messages for the given worktree from SQLite.
    func loadMessages(worktreeId: UUID) {
        currentWorktreeId = worktreeId
        do {
            messages = try Database.shared.fetchMessages(forWorktree: worktreeId)
            planState = try Database.shared.fetchPlanState(forWorktree: worktreeId)
        } catch {
            print("[ChatStore] loadMessages error: \(error)")
            messages = []
            planState = nil
        }
    }

    /// Adds a new message: persists to SQLite and appends to the published array.
    /// - Parameters:
    ///   - worktreeId: The owning worktree.
    ///   - role: `.user` or `.assistant`.
    ///   - content: Text content of the message.
    @discardableResult
    func addMessage(
        worktreeId: UUID,
        role: MessageRole,
        content: String
    ) -> ChatMessage {
        let message = ChatMessage(
            worktreeId: worktreeId,
            role: role,
            content: content
        )
        do {
            try Database.shared.insertMessage(message)
        } catch {
            print("[ChatStore] addMessage persist error: \(error)")
        }
        messages.append(message)
        return message
    }

    /// Appends text to the last assistant message (streaming update).
    /// Does **not** persist the intermediate state — call `finaliseStreaming()` when done.
    func appendToLastAssistantMessage(_ text: String) {
        guard let idx = messages.indices.last(where: { messages[$0].role == .assistant }) else {
            return
        }
        messages[idx].content += text
    }

    /// Persists the final content of the last assistant message (after streaming completes).
    func finaliseStreaming() {
        guard let msg = messages.last(where: { $0.role == .assistant }) else { return }
        do {
            try Database.shared.updateMessage(msg)
        } catch {
            print("[ChatStore] finaliseStreaming persist error: \(error)")
        }
    }

    var isAwaitingPlanApproval: Bool {
        planState?.isAwaitingApproval == true
    }

    var canContinueExecution: Bool {
        !isAwaitingPlanApproval
    }

    /// Start plan mode for the given user prompt and persist awaiting-approval state.
    func startPlanApproval(for prompt: String, worktreeId: UUID) {
        let plan = buildPlan(from: prompt)
        let state = PlanState(
            worktreeId: worktreeId,
            status: .awaitingApproval,
            planText: plan,
            feedback: nil,
            updatedAt: Date()
        )

        persistPlanState(state)
        _ = addMessage(worktreeId: worktreeId, role: .assistant, content: plan + "\n\nApprove this plan to continue execution.")
    }

    func approvePlan(feedback: String? = nil) {
        guard var state = planState else { return }
        state.status = .approved
        state.feedback = feedback?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        state.updatedAt = Date()
        persistPlanState(state)

        guard let worktreeId = currentWorktreeId else { return }
        if let feedback = state.feedback {
            _ = addMessage(worktreeId: worktreeId, role: .user, content: "Plan approved with feedback: \(feedback)")
        } else {
            _ = addMessage(worktreeId: worktreeId, role: .assistant, content: "✅ Plan approved. Execution can continue.")
        }
    }

    func rejectPlan(reason: String?) {
        guard var state = planState else { return }
        state.status = .rejected
        state.feedback = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        state.updatedAt = Date()
        persistPlanState(state)

        guard let worktreeId = currentWorktreeId else { return }
        let reasonText = state.feedback ?? "No reason provided."
        _ = addMessage(worktreeId: worktreeId, role: .user, content: "❌ Plan rejected: \(reasonText)")
    }

    /// Clears all messages for the current worktree from memory only (not DB).
    func clearMemory() {
        messages = []
        planState = nil
        currentWorktreeId = nil
    }

    private func persistPlanState(_ state: PlanState) {
        do {
            try Database.shared.upsertPlanState(state)
            planState = state
        } catch {
            print("[ChatStore] persist plan state error: \(error)")
        }
    }

    private func buildPlan(from prompt: String) -> String {
        """
        Proposed plan:
        1. Understand the request: \(prompt)
        2. Outline implementation steps and expected changes.
        3. Execute only after explicit approval.
        """
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
