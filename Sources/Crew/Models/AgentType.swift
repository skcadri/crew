import Foundation

/// The type of coding agent to spawn.
public enum AgentType: String, Codable, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case codex      = "codex"
    case lmStudio   = "lm_studio"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .lmStudio:   return "LM Studio"
        }
    }
}
