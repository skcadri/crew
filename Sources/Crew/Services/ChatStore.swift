import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false

    // B1 plan mode
    @Published private(set) var planState: PlanState?

    // B2 ask-user flow
    @Published private(set) var pendingQuestion: PendingQuestion?
    @Published private(set) var isFlowPaused: Bool = false

    private(set) var currentWorktreeId: UUID?

    init() {}

    func loadMessages(worktreeId: UUID) {
        currentWorktreeId = worktreeId
        do {
            messages = try Database.shared.fetchMessages(forWorktree: worktreeId)
            planState = try Database.shared.fetchPlanState(forWorktree: worktreeId)
            pendingQuestion = try Database.shared.fetchPendingQuestion(forWorktree: worktreeId)
            isFlowPaused = pendingQuestion != nil
        } catch {
            print("[ChatStore] loadMessages error: \(error)")
            messages = []
            planState = nil
            pendingQuestion = nil
            isFlowPaused = false
        }
    }

    @discardableResult
    func addMessage(worktreeId: UUID, role: MessageRole, content: String) -> ChatMessage {
        let message = ChatMessage(worktreeId: worktreeId, role: role, content: content)
        do { try Database.shared.insertMessage(message) }
        catch { print("[ChatStore] addMessage persist error: \(error)") }
        messages.append(message)
        return message
    }

    func appendToLastAssistantMessage(_ text: String) {
        guard let idx = messages.indices.last(where: { messages[$0].role == .assistant }) else { return }
        messages[idx].content += text
    }

    func finaliseStreaming() {
        guard let msg = messages.last(where: { $0.role == .assistant }) else { return }
        do { try Database.shared.updateMessage(msg) }
        catch { print("[ChatStore] finaliseStreaming persist error: \(error)") }
    }

    // MARK: B1 plan flow

    var isAwaitingPlanApproval: Bool { planState?.isAwaitingApproval == true }
    var canContinueExecution: Bool { !isAwaitingPlanApproval }

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

    // MARK: B2 ask-user flow

    func setPendingQuestion(worktreeId: UUID, prompt: String) {
        let question = PendingQuestion(worktreeId: worktreeId, prompt: prompt)
        do {
            try Database.shared.upsertPendingQuestion(question)
            pendingQuestion = question
            isFlowPaused = true
            isLoading = false
        } catch {
            print("[ChatStore] setPendingQuestion persist error: \(error)")
        }
    }

    @discardableResult
    func submitPendingQuestionResponse(worktreeId: UUID, response: String) -> ChatMessage {
        let answer = addMessage(worktreeId: worktreeId, role: .user, content: response)
        do { try Database.shared.clearPendingQuestion(forWorktree: worktreeId) }
        catch { print("[ChatStore] clearPendingQuestion error: \(error)") }
        pendingQuestion = nil
        isFlowPaused = false
        return answer
    }

    func clearMemory() {
        messages = []
        planState = nil
        pendingQuestion = nil
        isFlowPaused = false
        currentWorktreeId = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
