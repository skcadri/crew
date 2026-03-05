import Foundation

// MARK: - CodexAgent

/// Sends prompts to the OpenAI chat completions endpoint and maps the
/// Server-Sent-Events (SSE) stream to `AgentEvent` values.
///
/// **API:** `POST https://api.openai.com/v1/chat/completions`
/// with `"stream": true` — each SSE data line carries a JSON delta.
///
/// **API key resolution order:**
/// 1. The key passed to `init(apiKey:)`.
/// 2. The `OPENAI_API_KEY` environment variable.
/// 3. A `UserDefaults` entry keyed `"openAIAPIKey"`.
///
/// If no key is found, every request emits `AgentEvent.error(…)`.
public actor CodexAgent: @preconcurrency CodingAgent {

    // MARK: - Public properties

    public nonisolated let id: UUID
    public nonisolated let type: AgentType = .codex

    public var isRunning: Bool { _isRunning }

    // MARK: - Configuration

    /// Base URL for the completions endpoint.
    public static let defaultBaseURL = "https://api.openai.com"

    /// Default model name sent to the API.
    public static let defaultModel = "gpt-5.3-codex"

    // MARK: - Private state

    private var _isRunning = false
    private var currentTask: Task<Void, Never>?

    private let model: String
    private let baseURL: String
    private let apiKey: String?

    /// Conversation history — grows with each `start` / `send` call so the
    /// agent retains context within a session.
    private var messages: [[String: String]] = []

    private let session: URLSession

    // MARK: - Init

    /// - Parameters:
    ///   - id:       Stable identifier (defaults to a fresh UUID).
    ///   - model:    Model to request (defaults to `defaultModel`).
    ///   - baseURL:  API base URL (defaults to OpenAI production endpoint).
    ///   - apiKey:   OpenAI API key.  If `nil`, falls back to the environment
    ///               variable `OPENAI_API_KEY` or `UserDefaults`.
    ///   - session:  URLSession to use (injectable for tests).
    public init(
        id: UUID = UUID(),
        model: String = CodexAgent.defaultModel,
        baseURL: String = CodexAgent.defaultBaseURL,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.id = id
        self.model = model
        self.baseURL = baseURL
        self.session = session

        // Resolve the API key at init time.
        if let key = apiKey, !key.isEmpty {
            self.apiKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
                  !envKey.isEmpty {
            self.apiKey = envKey
        } else if let defaultsKey = UserDefaults.standard.string(forKey: "openAIAPIKey"),
                  !defaultsKey.isEmpty {
            self.apiKey = defaultsKey
        } else {
            self.apiKey = nil
        }
    }

    // MARK: - CodingAgent

    public func start(workdir: String, prompt: String) async throws -> AsyncStream<AgentEvent> {
        guard !_isRunning else { throw AgentError.alreadyRunning }
        // Reset history for a fresh session.
        messages = []
        return try sendMessage(prompt)
    }

    public func send(message: String) async throws -> AsyncStream<AgentEvent> {
        guard !_isRunning else { throw AgentError.alreadyRunning }
        return try sendMessage(message)
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
        _isRunning = false
    }

    // MARK: - Private helpers

    private func sendMessage(_ content: String) throws -> AsyncStream<AgentEvent> {
        guard let key = apiKey else {
            return AsyncStream { continuation in
                continuation.yield(.error(
                    "No OpenAI API key configured. Set OPENAI_API_KEY or add a key in Settings."
                ))
                continuation.yield(.done)
                continuation.finish()
            }
        }

        // Append the user turn.
        messages.append(["role": "user", "content": content])

        // Build the request payload.
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages
        ]

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            return AsyncStream { continuation in
                continuation.yield(.error("Invalid base URL: \(baseURL)"))
                continuation.yield(.done)
                continuation.finish()
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _isRunning = true

        // Capture mutable state needed inside the closure (Swift concurrency).
        let capturedSession = session
        var capturedMessages = messages   // snapshot; we'll append the assistant reply

        let stream = AsyncStream<AgentEvent> { [weak self] continuation in
            let task = Task {
                defer {
                    Task { await self?.markFinished() }
                    continuation.finish()
                }

                do {
                    let (asyncBytes, response) = try await capturedSession.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200..<300).contains(httpResponse.statusCode) {
                        continuation.yield(.error("HTTP \(httpResponse.statusCode)"))
                        continuation.yield(.done)
                        return
                    }

                    var assistantText = ""

                    // Each SSE line looks like:
                    //   data: {"id":"…","choices":[{"delta":{"content":"…"}}]}
                    // or the terminal sentinel:
                    //   data: [DONE]
                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))   // strip "data: "

                        if jsonStr == "[DONE]" {
                            // Persist assistant reply into conversation history.
                            capturedMessages.append(["role": "assistant", "content": assistantText])
                            Task { await self?.appendAssistantTurn(capturedMessages) }
                            continuation.yield(.done)
                            return
                        }

                        if let delta = CodexAgent.parseDelta(jsonStr) {
                            assistantText += delta
                            continuation.yield(.text(delta))
                        }
                    }

                    // Stream ended without [DONE] — still finish gracefully.
                    if !assistantText.isEmpty {
                        capturedMessages.append(["role": "assistant", "content": assistantText])
                        Task { await self?.appendAssistantTurn(capturedMessages) }
                    }
                    continuation.yield(.done)

                } catch is CancellationError {
                    // Normal path when cancel() is called.
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.yield(.done)
                }
            }

            continuation.onTermination = { _ in task.cancel() }

            // Store so cancel() can reach it.
            Task { await self?.storeTask(task) }
        }

        return stream
    }

    private func markFinished() {
        _isRunning = false
        currentTask = nil
    }

    private func storeTask(_ task: Task<Void, Never>) {
        currentTask = task
    }

    private func appendAssistantTurn(_ updatedMessages: [[String: String]]) {
        messages = updatedMessages
    }

    // MARK: - SSE delta parser

    /// Extracts the incremental text delta from a single SSE data JSON string.
    ///
    /// Expected shape:
    /// ```json
    /// {
    ///   "choices": [
    ///     { "delta": { "content": "…" }, "finish_reason": null }
    ///   ]
    /// }
    /// ```
    static func parseDelta(_ jsonString: String) -> String? {
        guard
            let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let delta = first["delta"] as? [String: Any],
            let content = delta["content"] as? String
        else {
            return nil
        }
        return content
    }
}
