import Foundation

// MARK: - LMStudioAgent

/// Sends prompts to a locally-running LM Studio instance via its
/// OpenAI-compatible REST API.
///
/// **Endpoints used:**
/// - `GET  <baseURL>/v1/models`               — model discovery
/// - `POST <baseURL>/v1/chat/completions`     — streaming inference
///
/// No API key is required; LM Studio's local server does not authenticate.
///
/// **Availability helpers:**
/// - `LMStudioAgent.isAvailable()` — quick reachability check
/// - `LMStudioAgent.listModels(baseURL:)` — returns loaded model IDs
public actor LMStudioAgent: @preconcurrency CodingAgent {

    // MARK: - Public properties

    public nonisolated let id: UUID
    public nonisolated let type: AgentType = .lmStudio

    public var isRunning: Bool { _isRunning }

    // MARK: - Configuration

    /// Default base URL for a stock LM Studio installation.
    public static let defaultBaseURL = "http://127.0.0.1:1234"

    // MARK: - Private state

    private var _isRunning = false
    private var currentTask: Task<Void, Never>?

    private let model: String
    private let baseURL: String
    private let session: URLSession

    /// Rolling conversation history, preserved across `send` calls.
    private var messages: [[String: String]] = []

    // MARK: - Init

    /// - Parameters:
    ///   - id:      Stable identifier (defaults to a fresh UUID).
    ///   - model:   Model identifier to pass in the request body.  Use
    ///              `LMStudioAgent.listModels()` to discover what is loaded.
    ///   - baseURL: LM Studio server URL (default `http://127.0.0.1:1234`).
    ///   - session: URLSession to use (injectable for tests).
    public init(
        id: UUID = UUID(),
        model: String,
        baseURL: String = LMStudioAgent.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.id = id
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - CodingAgent

    public func start(workdir: String, prompt: String) async throws -> AsyncStream<AgentEvent> {
        guard !_isRunning else { throw AgentError.alreadyRunning }
        messages = []   // fresh session
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

    // MARK: - Static availability helpers

    /// Returns `true` if an LM Studio server is reachable at the default base URL.
    ///
    /// The check performs a lightweight `GET /v1/models` and considers any
    /// 2xx HTTP response as "available".
    public static func isAvailable(baseURL: String = LMStudioAgent.defaultBaseURL) async -> Bool {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    /// Returns the list of model IDs currently available in LM Studio.
    ///
    /// - Parameter baseURL: LM Studio server URL.
    /// - Throws: `URLError` / decoding errors if the server is unreachable or
    ///           returns unexpected JSON.
    public static func listModels(baseURL: String = LMStudioAgent.defaultBaseURL) async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        // OpenAI-compatible shape:
        // { "object": "list", "data": [ { "id": "…", … }, … ] }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArr = json["data"] as? [[String: Any]]
        else {
            throw URLError(.cannotParseResponse)
        }

        return dataArr.compactMap { $0["id"] as? String }
    }

    // MARK: - Private helpers

    private func sendMessage(_ content: String) throws -> AsyncStream<AgentEvent> {
        messages.append(["role": "user", "content": content])

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages
        ]

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            return AsyncStream { continuation in
                continuation.yield(.error("Invalid LM Studio base URL: \(baseURL)"))
                continuation.yield(.done)
                continuation.finish()
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // LM Studio does not require Authorization, but some builds accept it.
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        // Allow longer generation without timing out.
        request.timeoutInterval = 300

        _isRunning = true

        let capturedSession = session
        var capturedMessages = messages

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
                        // Try to include a snippet from the response body.
                        continuation.yield(.error(
                            "LM Studio HTTP \(httpResponse.statusCode). " +
                            "Make sure the model is loaded and the server is running."
                        ))
                        continuation.yield(.done)
                        return
                    }

                    var assistantText = ""

                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))

                        if jsonStr == "[DONE]" {
                            capturedMessages.append(["role": "assistant", "content": assistantText])
                            Task { await self?.appendAssistantTurn(capturedMessages) }
                            continuation.yield(.done)
                            return
                        }

                        if let delta = LMStudioAgent.parseDelta(jsonStr) {
                            assistantText += delta
                            continuation.yield(.text(delta))
                        }
                    }

                    // Stream ended without [DONE] — still emit done.
                    if !assistantText.isEmpty {
                        capturedMessages.append(["role": "assistant", "content": assistantText])
                        Task { await self?.appendAssistantTurn(capturedMessages) }
                    }
                    continuation.yield(.done)

                } catch is CancellationError {
                    // Normal cancellation.
                } catch {
                    continuation.yield(.error(
                        "LM Studio connection error: \(error.localizedDescription)"
                    ))
                    continuation.yield(.done)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
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

    /// Parses the incremental `content` delta out of a streaming chat
    /// completions data line.
    ///
    /// LM Studio emits the same SSE shape as OpenAI:
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
