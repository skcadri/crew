import Foundation

// MARK: - ClaudeCodeAgent

/// Runs the `claude` CLI subprocess and maps its JSON output to `AgentEvent`.
///
/// The agent uses `--print` (non-interactive / JSON streaming mode) and sets the
/// working directory to the provided worktree path so all file operations happen
/// inside the correct branch.
///
/// **JSON line format** (Claude Code `--print` output):
/// ```json
/// {"type":"text","content":"…"}
/// {"type":"tool_use","name":"…","input":{…}}
/// {"type":"error","message":"…"}
/// {"type":"result","subtype":"success"}
/// ```
public actor ClaudeCodeAgent: @preconcurrency CodingAgent {

    // MARK: Public properties

    /// Stable identifier — `let` constant, safe to access from any context.
    public nonisolated let id: UUID

    /// Agent type — `let` constant, safe to access from any context.
    public nonisolated let type: AgentType = .claudeCode

    /// Whether the agent subprocess is currently active.
    /// Reads the actor-isolated `_isRunning` flag; call from an `await` context
    /// for a data-race-safe read, or rely on `@preconcurrency` for Swift 5 callers.
    public var isRunning: Bool { _isRunning }

    // MARK: Private state

    private var _isRunning = false
    private var process: Process?
    private var claudePath: String

    // MARK: Init

    /// - Parameter claudePath: Path to the `claude` binary.
    ///   Defaults to `/usr/local/bin/claude`; override in tests or custom installs
    ///   (e.g. `/opt/homebrew/bin/claude`).
    public init(id: UUID = UUID(), claudePath: String = "/usr/local/bin/claude") {
        self.id = id
        self.claudePath = claudePath
    }

    // MARK: CodingAgent

    public func start(workdir: String, prompt: String) async throws -> AsyncStream<AgentEvent> {
        guard !_isRunning else {
            throw AgentError.alreadyRunning
        }
        return try spawnProcess(workdir: workdir, prompt: prompt)
    }

    public func send(message: String) async throws -> AsyncStream<AgentEvent> {
        // For Claude Code CLI each turn is a fresh invocation because `--print`
        // is single-shot.  The caller should capture the last workdir from the
        // previous `start` call.  We re-use the stored process's currentDirectoryURL.
        let workdir = process?.currentDirectoryURL?.path ?? FileManager.default.currentDirectoryPath
        guard !_isRunning else {
            throw AgentError.alreadyRunning
        }
        return try spawnProcess(workdir: workdir, prompt: message)
    }

    public func cancel() async {
        guard _isRunning, let proc = process else { return }
        proc.terminate()
        _isRunning = false
        process = nil
    }

    // MARK: - Private helpers

    private func spawnProcess(workdir: String, prompt: String) throws -> AsyncStream<AgentEvent> {

        // Resolve the binary (check both common locations).
        let resolvedPath = resolveClaudeBinary()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolvedPath)
        proc.currentDirectoryURL = URL(fileURLWithPath: workdir)
        // --print: non-interactive JSON streaming mode
        proc.arguments = ["--print", prompt]

        // Environment: inherit current + ensure HOME / PATH are set.
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        self.process  = proc
        self._isRunning = true

        let stream = AsyncStream<AgentEvent> { continuation in

            // Capture self weakly to avoid retain cycle; actor isolation is fine
            // because we only mutate `_isRunning` / `process` via the actor.
            let capturedID = self.id

            // Read stdout line-by-line on a background thread.
            let stdoutHandle = stdoutPipe.fileHandleForReading

            Task {
                defer {
                    // Signal completion on the actor (fire-and-forget).
                    Task { self.markFinished() }
                    continuation.finish()
                }

                var buffer = Data()

                // Stream available bytes until EOF.
                for try await chunk in stdoutHandle.bytes {
                    buffer.append(chunk)

                    // Split on newlines and process each complete line.
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[buffer.startIndex...newlineIndex]
                        buffer.removeSubrange(buffer.startIndex...newlineIndex)

                        if let line = String(data: lineData, encoding: .utf8)?
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                           !line.isEmpty {
                            let event = ClaudeCodeAgent.parseJSONLine(line)
                            continuation.yield(event)
                            if case .done = event { return }
                        }
                    }
                }

                // Flush any remaining bytes.
                if !buffer.isEmpty,
                   let line = String(data: buffer, encoding: .utf8)?
                                  .trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    continuation.yield(ClaudeCodeAgent.parseJSONLine(line))
                }

                continuation.yield(.done)
                _ = capturedID  // silence unused warning
            }

            // Watch stderr for error output.
            let stderrHandle = stderrPipe.fileHandleForReading
            Task {
                var errBuffer = Data()
                for try await byte in stderrHandle.bytes {
                    errBuffer.append(byte)
                }
                if !errBuffer.isEmpty,
                   let msg = String(data: errBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !msg.isEmpty {
                    continuation.yield(.error(msg))
                }
            }

            // Handle cancellation from the caller.
            continuation.onTermination = { [weak proc] _ in
                proc?.terminate()
            }
        }

        // Launch after the stream is set up.
        try proc.run()

        return stream
    }

    private func markFinished() {
        _isRunning = false
        process = nil
    }

    /// Resolves the claude binary, falling back to common Homebrew and nvm paths.
    private func resolveClaudeBinary() -> String {
        let candidates = [
            claudePath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Return the configured path even if not found; Process.run() will throw.
        return claudePath
    }

    // MARK: - JSON line parser

    /// Parses a single JSON line from Claude Code's `--print` output.
    ///
    /// Expected schemas (non-exhaustive; we handle unknown types gracefully):
    /// - `{"type":"text","content":"…"}`
    /// - `{"type":"tool_use","name":"…"}`
    /// - `{"type":"error","message":"…"}`
    /// - `{"type":"result","subtype":"success"|"error_during_execution"}`
    static func parseJSONLine(_ line: String) -> AgentEvent {
        guard
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let typeStr = json["type"] as? String
        else {
            // Not JSON — treat as plain text (e.g. raw stdout during development).
            return .text(line)
        }

        switch typeStr {
        case "text":
            let content = (json["content"] as? String) ?? ""
            return .text(content)

        case "tool_use":
            let name  = (json["name"] as? String) ?? "unknown_tool"
            let input = (json["input"] as? [String: Any]).map { "\($0)" } ?? ""
            return .toolUse("\(name): \(input)")

        case "error":
            let msg = (json["message"] as? String) ?? line
            return .error(msg)

        case "result":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "success" {
                return .done
            } else {
                let errorMessage = (json["error"] as? String) ?? subtype
                return .error(errorMessage)
            }

        case "assistant":
            // Some versions wrap messages: {"type":"assistant","message":{"content":[…]}}
            if let message    = json["message"] as? [String: Any],
               let contentArr = message["content"] as? [[String: Any]] {
                let texts = contentArr.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                return .text(texts.joined())
            }
            return .text(line)

        default:
            return .text(line)
        }
    }
}

// MARK: - AgentError

public enum AgentError: LocalizedError {
    case alreadyRunning
    case binaryNotFound(String)
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:          return "Agent is already running. Call cancel() first."
        case .binaryNotFound(let p):   return "Claude binary not found at \(p)."
        case .notRunning:              return "Agent is not currently running."
        }
    }
}
