import SwiftUI

struct ChatView: View {
    @ObservedObject var store: ChatStore
    let worktreeId: UUID
    let workspacePath: String
    let modelName: String?

    @State private var selectedContextFiles: Set<String> = []
    @State private var showContextPicker: Bool = false
    @State private var inputText: String = ""

    init(store: ChatStore, worktreeId: UUID, workspacePath: String, modelName: String? = nil) {
        self.store = store
        self.worktreeId = worktreeId
        self.workspacePath = workspacePath
        self.modelName = modelName
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }

                        if store.isLoading {
                            TypingIndicator().id("typing").padding(.leading, 20).padding(.vertical, 8)
                        }

                        if let pendingQuestion = store.pendingQuestion {
                            PendingQuestionCard(question: pendingQuestion)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .id("pending-question")
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: store.messages.count) { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.isLoading) {
                    if store.isLoading { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("typing", anchor: .bottom) } }
                }
                .onAppear {
                    store.loadMessages(worktreeId: worktreeId)
                    loadContextSelection()
                    _ = try? ContextFileService.shared.ensureContextDirectory(workspacePath: workspacePath)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if store.isAwaitingPlanApproval {
                PlanApprovalCard(store: store)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            contextStrip

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

    private var contextStrip: some View {
        HStack(spacing: 8) {
            Button {
                showContextPicker.toggle()
            } label: {
                Label(
                    selectedContextFiles.isEmpty
                    ? "Attach context"
                    : "\(selectedContextFiles.count) context file\(selectedContextFiles.count == 1 ? "" : "s")",
                    systemImage: "paperclip"
                )
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .accessibilityLabel("Attach context files")
            .popover(isPresented: $showContextPicker) {
                ContextPickerView(
                    workspacePath: workspacePath,
                    selectedFiles: selectedContextFiles,
                    onToggle: toggleContextFile
                )
            }

            if !selectedContextFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedContextFiles.sorted(), id: \.self) { file in
                            Text(file)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if store.pendingQuestion != nil {
            inputText = ""
            _ = store.submitPendingQuestionResponse(worktreeId: worktreeId, response: trimmed)
            return
        }

        guard store.canContinueExecution else { return }

        inputText = ""
        let finalMessage = buildMessageWithContext(userMessage: trimmed)
        store.addMessage(worktreeId: worktreeId, role: .user, content: finalMessage)
        store.startPlanApproval(for: finalMessage, worktreeId: worktreeId)
    }

    private func buildMessageWithContext(userMessage: String) -> String {
        guard !selectedContextFiles.isEmpty else { return userMessage }
        var sections: [String] = [userMessage, "", "Attached workspace context files:"]
        for file in selectedContextFiles.sorted() {
            let content = (try? ContextFileService.shared.readFile(workspacePath: workspacePath, relativePath: file)) ?? "[Unable to read file]"
            sections.append("\n--- .context/\(file) ---\n\(content)")
        }
        return sections.joined(separator: "\n")
    }

    private func toggleContextFile(_ relativePath: String) {
        if selectedContextFiles.contains(relativePath) { selectedContextFiles.remove(relativePath) }
        else { selectedContextFiles.insert(relativePath) }
        try? Database.shared.replaceContextRefs(worktreeId: worktreeId, relativePaths: selectedContextFiles)
    }

    private func loadContextSelection() {
        let refs = (try? Database.shared.fetchContextRefs(worktreeId: worktreeId)) ?? []
        selectedContextFiles = Set(refs.map(\.relativePath))
    }
}

private struct PlanApprovalCard: View {
    @ObservedObject var store: ChatStore
    @State private var feedback: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan approval required").font(.headline)
            Text("Review the proposed plan above, then approve or reject before execution continues.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Optional feedback", text: $feedback)
            HStack(spacing: 8) {
                Button("Approve") { store.approvePlan(); feedback = "" }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityLabel("Approve plan")
                Button("Approve with Feedback") { store.approvePlan(feedback: feedback); feedback = "" }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .accessibilityLabel("Approve plan with feedback")
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Reject") { store.rejectPlan(reason: feedback); feedback = "" }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(".", modifiers: .command)
                    .accessibilityLabel("Reject plan")
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
            Text(question.prompt).font(.body).fixedSize(horizontal: false, vertical: true)
            Text("Answer below to resume agent flow").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TypingIndicator: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { idx in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .opacity(phase == idx ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
