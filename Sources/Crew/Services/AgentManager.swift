import Foundation

// MARK: - AgentManager

/// Central registry for active `CodingAgent` instances.
///
/// Each git worktree (identified by its UUID) can have exactly one running agent
/// at a time.  `AgentManager` owns the lifecycle: spawn → stream → cancel/finish.
///
/// This is an `actor` so callers can safely mutate the registry from any async
/// context without additional locking.
public actor AgentManager {

    // MARK: Singleton

    public static let shared = AgentManager()

    // MARK: Private state

    /// Live agents keyed by worktree UUID.
    private var agents: [UUID: any CodingAgent] = [:]

    /// `UserDefaults` used to look up agent configuration (passed to `AgentFactory`).
    private let defaults: UserDefaults

    // MARK: Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Spawn a new agent for the given worktree and immediately start it.
    ///
    /// If an agent is already running for this worktree, it is cancelled first.
    ///
    /// - Parameters:
    ///   - worktreeID: The UUID of the `Worktree` model record.
    ///   - agentType:  Which agent implementation to use.
    ///   - workdir:    Absolute path to the worktree on disk.
    ///   - prompt:     Initial task / instruction.
    /// - Returns: An `AsyncStream<AgentEvent>` for the first turn.
    @discardableResult
    public func spawn(
        worktreeID: UUID,
        agentType: AgentType,
        workdir: String,
        prompt: String
    ) async throws -> AsyncStream<AgentEvent> {

        // Cancel any existing agent for this worktree.
        if let existing = agents[worktreeID] {
            await existing.cancel()
            agents.removeValue(forKey: worktreeID)
        }

        let agent = AgentFactory.makeAgent(agentType, defaults: defaults)
        agents[worktreeID] = agent

        let stream = try await agent.start(workdir: workdir, prompt: prompt)

        // Remove the agent from the registry when it finishes naturally.
        Task {
            await self.observeCompletion(worktreeID: worktreeID, stream: stream)
        }

        return stream
    }

    /// Send a follow-up message to the agent currently attached to a worktree.
    ///
    /// - Parameters:
    ///   - worktreeID: Target worktree.
    ///   - message:    Follow-up prompt or instruction.
    /// - Returns: An `AsyncStream<AgentEvent>` for this turn.
    public func send(worktreeID: UUID, message: String) async throws -> AsyncStream<AgentEvent> {
        guard let agent = agents[worktreeID] else {
            throw AgentManagerError.noActiveAgent(worktreeID)
        }
        return try await agent.send(message: message)
    }

    /// Cancel the agent for a worktree (if any) and remove it from the registry.
    public func cancel(worktreeID: UUID) async {
        guard let agent = agents[worktreeID] else { return }
        await agent.cancel()
        agents.removeValue(forKey: worktreeID)
    }

    /// Returns the live agent for a worktree, or `nil` if none is active.
    public func agent(for worktreeID: UUID) -> (any CodingAgent)? {
        agents[worktreeID]
    }

    /// `true` if an agent is currently running for the given worktree.
    public func isRunning(worktreeID: UUID) -> Bool {
        agents[worktreeID]?.isRunning ?? false
    }

    /// All worktree IDs that currently have an active agent.
    public var activeWorktreeIDs: [UUID] {
        Array(agents.keys)
    }

    // MARK: - Private helpers

    /// Watches the stream and removes the agent once it emits `.done`.
    private func observeCompletion(worktreeID: UUID, stream: AsyncStream<AgentEvent>) async {
        for await event in stream {
            if case .done = event {
                agents.removeValue(forKey: worktreeID)
                return
            }
        }
        // Stream exhausted without an explicit `.done` — clean up anyway.
        agents.removeValue(forKey: worktreeID)
    }
}

// MARK: - AgentManagerError

public enum AgentManagerError: LocalizedError {
    case noActiveAgent(UUID)

    public var errorDescription: String? {
        switch self {
        case .noActiveAgent(let id):
            return "No active agent for worktree \(id). Call spawn() first."
        }
    }
}
