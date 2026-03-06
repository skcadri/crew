import SwiftUI

/// Main chat container for a worktree with optional summary + TOC rail.
struct ChatView: View {

    @ObservedObject var store: ChatStore
    let worktreeId: UUID
    let modelName: String?

    @State private var inputText: String = ""

    init(store: ChatStore, worktreeId: UUID, modelName: String? = nil) {
        self.store = store
        self.worktreeId = worktreeId
        self.modelName = modelName
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if store.isLoading {
                                TypingIndicator()
                                    .id("typing")
                                    .padding(.leading, 20)
                                    .padding(.vertical, 8)
                            }

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
                    .onAppear {
                        store.loadMessages(worktreeId: worktreeId)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !store.tocEntries.isEmpty {
                            TOCJumpButton {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(store.tocEntries.first?.messageId, anchor: .top)
                                }
                            }
                            .padding(.trailing, 12)
                            .padding(.top, 8)
                        }
                    }
                    .safeAreaInset(edge: .trailing) {
                        if !store.tocEntries.isEmpty || store.summarySnapshot != nil {
                            ChatSummaryTOCPanel(
                                snapshot: store.summarySnapshot,
                                tocEntries: store.tocEntries,
                                onSelect: { messageId in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(messageId, anchor: .top)
                                    }
                                }
                            )
                            .frame(width: 260)
                        }
                    }
                }

                ChatInputView(
                    text: $inputText,
                    isProcessing: store.isLoading,
                    modelName: modelName,
                    onSend: sendMessage
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        store.addMessage(worktreeId: worktreeId, role: .user, content: trimmed)
    }
}

private struct TOCJumpButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("TOC", systemImage: "list.bullet.indent")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .help("Jump to first section")
    }
}

private struct ChatSummaryTOCPanel: View {
    let snapshot: ChatSummarySnapshot?
    let tocEntries: [ChatTOCEntry]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)

            if let snapshot {
                ScrollView {
                    Text(snapshot.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            } else {
                Text("Summary appears automatically for longer chats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Table of Contents")
                .font(.headline)

            if tocEntries.isEmpty {
                Text("No headings detected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tocEntries) { entry in
                            Button {
                                onSelect(entry.messageId)
                            } label: {
                                Text(entry.title)
                                    .lineLimit(2)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat((entry.level - 1) * 10))
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .overlay(alignment: .leading) { Divider() }
    }
}

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
