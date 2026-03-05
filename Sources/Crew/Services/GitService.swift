import Foundation

// MARK: - GitService Errors

enum GitError: Error, LocalizedError {
    case invalidURL(String)
    case cloneFailed(String)
    case commandFailed(String)
    case directoryCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let msg):              return "Invalid URL: \(msg)"
        case .cloneFailed(let msg):             return "Clone failed: \(msg)"
        case .commandFailed(let msg):           return "Git command failed: \(msg)"
        case .directoryCreationFailed(let msg): return "Could not create directory: \(msg)"
        }
    }
}

// MARK: - GitService

/// Shells out to the system `git` CLI for all git operations.
final class GitService {

    static let shared = GitService()

    private init() {}

    // MARK: - Repos Base Path

    static var reposBaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Crew", isDirectory: true)
            .appendingPathComponent("repos", isDirectory: true)
    }

    // MARK: - Clone

    /// Clone a remote repository into ~/Library/Application Support/Crew/repos/<name>/
    /// - Returns: The absolute path to the cloned repo.
    @discardableResult
    func cloneRepo(url: String) async throws -> String {
        guard !url.isEmpty else {
            throw GitError.invalidURL("URL must not be empty")
        }

        // Derive a clean directory name from the URL
        let repoName = deriveName(from: url)
        let destURL = Self.reposBaseURL.appendingPathComponent(repoName, isDirectory: true)

        // Create the parent repos/ dir if needed
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.reposBaseURL.path) {
            do {
                try fm.createDirectory(at: Self.reposBaseURL, withIntermediateDirectories: true)
            } catch {
                throw GitError.directoryCreationFailed(error.localizedDescription)
            }
        }

        // If there's already a directory at that path, make it unique
        let finalDest = uniqueDestination(base: destURL)

        let output = try await run(["git", "clone", url, finalDest.path])
        _ = output  // clone stderr is progress; success means the dir exists
        return finalDest.path
    }

    // MARK: - Branches

    /// List branches in a local repository.
    func listBranches(repoPath: String) -> [String] {
        guard let output = try? runSync(["git", "-C", repoPath, "branch", "--format=%(refname:short)"]) else {
            return []
        }
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Remove Repo from Disk

    func removeRepoDirectory(atPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private Helpers

    /// Run a git command asynchronously and return combined stdout+stderr.
    @discardableResult
    func run(_ args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let output = try runSync(args)
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Run a git command synchronously (on the calling thread) and return stdout.
    /// Throws `GitError.commandFailed` when the exit code is non-zero.
    func runSync(_ args: [String]) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Inherit a clean environment so git can find ssh-agent etc.
        var env = ProcessInfo.processInfo.environment
        // Make sure PATH includes common git install locations
        let paths = ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = (paths + [existing]).joined(separator: ":")
        process.environment = env

        do {
            try process.run()
        } catch {
            throw GitError.commandFailed("Could not launch \(args.first ?? "?"): \(error)")
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let msg = stderr.isEmpty ? stdout : stderr
            throw GitError.commandFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Name helpers

    /// Derive a human-friendly directory name from a git URL.
    /// e.g. "https://github.com/user/my-app.git" → "my-app"
    private func deriveName(from url: String) -> String {
        var name = url
            .components(separatedBy: "/")
            .last ?? "repo"
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        // Strip anything that's not alphanumeric, dash, or underscore
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted)
                       .joined()
        return safe.isEmpty ? "repo" : safe
    }

    /// If `base` already exists on disk, append a counter to make it unique.
    private func uniqueDestination(base: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base.path) { return base }
        var counter = 2
        while true {
            let candidate = base.deletingLastPathComponent()
                               .appendingPathComponent("\(base.lastPathComponent)-\(counter)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
