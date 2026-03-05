import Foundation

// MARK: - AgentFactory

/// Creates the appropriate `CodingAgent` implementation for a given `AgentType`.
///
/// Callers should hold a strong reference to the returned agent for the lifetime
/// of the conversation.  `AgentManager` does this automatically.
public enum AgentFactory {

    // MARK: Configuration keys

    /// `UserDefaults` key for the Claude binary path override.
    public static let claudePathKey = "claudeBinaryPath"

    // MARK: Factory method

    /// Instantiate a `CodingAgent` for the requested type.
    ///
    /// - Parameters:
    ///   - agentType: Which provider to use.
    ///   - id:        Stable identifier for the new instance (defaults to a fresh UUID).
    ///   - defaults:  Where to read per-agent configuration from (defaults to
    ///                `UserDefaults.standard`).
    /// - Returns: A ready-to-use (but not yet started) `CodingAgent`.
    public static func makeAgent(
        _ agentType: AgentType,
        id: UUID = UUID(),
        defaults: UserDefaults = .standard
    ) -> any CodingAgent {
        switch agentType {
        case .claudeCode:
            let path = defaults.string(forKey: claudePathKey) ?? "/usr/local/bin/claude"
            return ClaudeCodeAgent(id: id, claudePath: path)

        case .codex:
            // TICKET-006 — CodexAgent will be implemented separately.
            // For now we return a stub that immediately errors.
            return StubAgent(id: id, agentType: .codex, errorMessage: "CodexAgent not yet implemented (TICKET-006)")

        case .lmStudio:
            // TICKET-006 — LMStudioAgent will be implemented separately.
            return StubAgent(id: id, agentType: .lmStudio, errorMessage: "LMStudioAgent not yet implemented (TICKET-006)")
        }
    }
}

// MARK: - StubAgent (placeholder for unimplemented types)

/// Minimal `CodingAgent` that immediately emits an error then finishes.
/// Removed once the real implementations land in TICKET-006.
private final class StubAgent: CodingAgent, @unchecked Sendable {

    let id: UUID
    let type: AgentType
    private let errorMessage: String
    private(set) var isRunning: Bool = false

    init(id: UUID, agentType: AgentType, errorMessage: String) {
        self.id = id
        self.type = agentType
        self.errorMessage = errorMessage
    }

    func start(workdir: String, prompt: String) async throws -> AsyncStream<AgentEvent> {
        makeErrorStream()
    }

    func send(message: String) async throws -> AsyncStream<AgentEvent> {
        makeErrorStream()
    }

    func cancel() async { isRunning = false }

    private func makeErrorStream() -> AsyncStream<AgentEvent> {
        let msg = errorMessage
        return AsyncStream { continuation in
            continuation.yield(.error(msg))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}
