import Foundation

// MARK: - AgentEvent

/// Events emitted by a running CodingAgent.
public enum AgentEvent: Sendable {
    /// Streaming chat text from the agent.
    case text(String)
    /// A tool execution notification (command name / summary).
    case toolUse(String)
    /// An error message from the agent or subprocess.
    case error(String)
    /// The agent has finished the current turn.
    case done
}

// MARK: - CodingAgent Protocol

/// Common interface for every coding agent (Claude Code, Codex, LM Studio, …).
///
/// Implementations must be `actor`-isolated or otherwise thread-safe, because
/// `isRunning` may be read from any concurrency context.
public protocol CodingAgent: AnyObject, Sendable {

    /// Stable identifier for this agent instance.
    var id: UUID { get }

    /// Which provider/binary this agent wraps.
    var type: AgentType { get }

    /// `true` while the agent subprocess or network request is active.
    var isRunning: Bool { get }

    /// Start a new agent session in the given working directory with an initial prompt.
    ///
    /// - Parameters:
    ///   - workdir: Absolute path to the git worktree the agent should operate in.
    ///   - prompt:  The initial instruction / task description.
    /// - Returns: An `AsyncStream` of `AgentEvent` values for this turn.
    func start(workdir: String, prompt: String) async throws -> AsyncStream<AgentEvent>

    /// Send a follow-up message to a running agent.
    ///
    /// - Parameter message: Follow-up prompt or instruction.
    /// - Returns: An `AsyncStream` of `AgentEvent` values for this turn.
    func send(message: String) async throws -> AsyncStream<AgentEvent>

    /// Terminate the agent immediately.  Safe to call even if not running.
    func cancel() async
}
