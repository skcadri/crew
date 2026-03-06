import SwiftUI

/// Main chat container for a worktree.
///
/// Layout (top to bottom):
///   1. Message list (ScrollView) with auto-scroll on new messages.
///   2. Typing indicator (shown while agent is thinking).
///   3. `ChatInputView` at the bottom.
struct ChatView: View {

    @ObservedObject var store: ChatStore
    let worktreeId: UUID
    let modelName: String?

    @State private var inputText: String = ""
    /// Used to programmatically scroll to the bottom when new messages arrive.
    @State private var scrollID: UUID = UUID()

    init(store: ChatStore, worktreeId: UUID, modelName: String? = nil) {
        self.store = store
        self.worktreeId = worktreeId
        self.modelName = modelName
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Message list ─────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Thinking indicator
                        if store.isLoading {
                            TypingIndicator()
                                .id("typing")
                                .padding(.leading, 20)
                                .padding(.vertical, 8)
                        }

                        if let pendingQuestion = store.pendingQuestion {
                            PendingQuestionCard(question: pendingQuestion)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .id("pending-question")
                        }

                        // Invisible anchor for scrolling to bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: store.messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: store.isLoading) {
                    if store.isLoading {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: scrollID) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear {
                    // Load messages and scroll to bottom
                    store.loadMessages(worktreeId: worktreeId)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            if store.isAwaitingPlanApproval {
                PlanApprovalCard(store: store)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            // ── Input bar ────────────────────────────────────────────────
            ChatInputView(
                text: $inputText,
                isProcessing: store.isLoading,
                isInputLocked: store.isAwaitingPlanApproval,
                modelName: modelName,
                pendingQuestionPrompt: store.pendingQuestion?.prompt,
                onSend: sendMessage
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if store.pendingQuestion != nil {
            inputText = ""
            _ = store.submitPendingQuestionResponse(worktreeId: worktreeId, response: trimmed)
            return
        }

        // Prevent execution continuation until plan approval.
        guard store.canContinueExecution else { return }

        inputText = ""

        // Add user message, then enter explicit plan stage.
        store.addMessage(worktreeId: worktreeId, role: .user, content: trimmed)
        store.startPlanApproval(for: trimmed, worktreeId: worktreeId)
    }
}

// MARK: - PlanApprovalCard

private struct PlanApprovalCard: View {
    @ObservedObject var store: ChatStore
    @State private var feedback: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan approval required")
                .font(.headline)
            Text("Review the proposed plan above, then approve or reject before execution continues.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Optional feedback", text: $feedback)

            HStack(spacing: 8) {
                Button("Approve") {
                    store.approvePlan()
                    feedback = ""
                }
                .buttonStyle(.borderedProminent)

                Button("Approve with Feedback") {
                    store.approvePlan(feedback: feedback)
                    feedback = ""
                }
                .buttonStyle(.bordered)
                .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Reject") {
                    store.rejectPlan(reason: feedback)
                    feedback = ""
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PendingQuestionCard: View {
    let question: PendingQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Question from Agent", systemImage: "questionmark.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(question.prompt)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Answer below to resume agent flow")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - TypingIndicator

/// Three animated dots to indicate the agent is thinking.
private struct TypingIndicator: View {
    @State private var phase: Int = 0

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == idx ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ChatStore()
    // Seed some messages synchronously for preview
    Task { @MainActor in
        _ = store.addMessage(
            worktreeId: UUID(),
            role: .user,
            content: "Hello, can you help me refactor this Swift function?"
        )
        _ = store.addMessage(
            worktreeId: UUID(),
            role: .assistant,
            content: "Sure! Share the function and I'll take a look.\n\n```swift\nfunc greet(_ name: String) -> String {\n    return \"Hello, \\(name)!\"\n}\n```"
        )
    }
    return ChatView(
        store: store,
        worktreeId: UUID(),
        modelName: "claude-sonnet-4"
    )
    .frame(width: 600, height: 500)
}
#endif
