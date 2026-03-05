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

            // ── Input bar ────────────────────────────────────────────────
            ChatInputView(
                text: $inputText,
                isProcessing: store.isLoading,
                modelName: modelName,
                onSend: sendMessage
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""

        // Add user message
        store.addMessage(worktreeId: worktreeId, role: .user, content: trimmed)
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
