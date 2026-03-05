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

    /// `UserDefaults` key for the OpenAI API key (Codex).
    public static let openAIAPIKeyKey = "openAIAPIKey"

    /// `UserDefaults` key for the Codex model name override.
    public static let codexModelKey = "codexModel"

    /// `UserDefaults` key for the LM Studio base URL override.
    public static let lmStudioBaseURLKey = "lmStudioBaseURL"

    /// `UserDefaults` key for the LM Studio model name override.
    public static let lmStudioModelKey = "lmStudioModel"

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
            let model   = defaults.string(forKey: codexModelKey)    ?? CodexAgent.defaultModel
            let baseURL = CodexAgent.defaultBaseURL
            // API key resolution happens inside CodexAgent (env → UserDefaults).
            let apiKey  = defaults.string(forKey: openAIAPIKeyKey)
            return CodexAgent(id: id, model: model, baseURL: baseURL, apiKey: apiKey)

        case .lmStudio:
            let baseURL = defaults.string(forKey: lmStudioBaseURLKey) ?? LMStudioAgent.defaultBaseURL
            // Default to the first available model name stored in UserDefaults;
            // falls back to a generic placeholder that the user can update in Settings.
            let model   = defaults.string(forKey: lmStudioModelKey)   ?? "local-model"
            return LMStudioAgent(id: id, model: model, baseURL: baseURL)
        }
    }
}

// StubAgent removed — CodexAgent and LMStudioAgent are now fully implemented (TICKET-006).
