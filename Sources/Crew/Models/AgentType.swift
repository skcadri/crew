import Foundation

/// The type of coding agent that can be used in a workspace.
enum AgentType: String, CaseIterable, Codable {
    case claudeCode
    case codex
    case lmStudio

    /// Human-readable display name for the agent.
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .lmStudio:   return "LM Studio"
        }
    }

    /// Short identifier used in UI labels.
    var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex:      return "Codex"
        case .lmStudio:   return "Local"
        }
    }
}
