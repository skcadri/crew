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
        } catch {
            print("[ChatStore] loadMessages error: \(error)")
            messages = []
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

    /// Clears all messages for the current worktree from memory only (not DB).
    func clearMemory() {
        messages = []
        currentWorktreeId = nil
    }
}
