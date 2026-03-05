import Foundation

// MARK: - FileChange

/// Represents a single changed file in a git repository.
struct FileChange: Identifiable, Hashable {
    enum Status: String, Hashable {
        case modified   = "M"
        case added      = "A"
        case deleted    = "D"
        case untracked  = "?"
        case renamed    = "R"
        case copied     = "C"
        case unknown    = " "

        var displaySymbol: String { rawValue }

        init(rawCode: String) {
            let code = rawCode.trimmingCharacters(in: .whitespaces)
            switch code {
            case "M", " M", "MM": self = .modified
            case "A", "AM":       self = .added
            case "D", " D":       self = .deleted
            case "??":            self = .untracked
            case "R", "RM":       self = .renamed
            case "C", "CM":       self = .copied
            default:              self = .unknown
            }
        }
    }

    let id: UUID
    let path: String
    let status: Status

    init(path: String, status: Status) {
        self.id     = UUID()
        self.path   = path
        self.status = status
    }
}

// MARK: - GitError

enum GitError: Error, LocalizedError {
    case invalidURL(String)
    case cloneFailed(String)
    case commandFailed(String)
    case directoryCreationFailed(String)
    case gitNotFound
    case nothingToCommit

    var errorDescription: String? {
        switch self {
        case .invalidURL(let msg):              return "Invalid URL: \(msg)"
        case .cloneFailed(let msg):             return "Clone failed: \(msg)"
        case .commandFailed(let msg):           return "Git command failed: \(msg)"
        case .directoryCreationFailed(let msg): return "Could not create directory: \(msg)"
        case .gitNotFound:                      return "git executable not found"
        case .nothingToCommit:                  return "Nothing to commit"
        }
    }
}

// MARK: - GitService

/// All git operations for Crew — shells out to the system `git` binary.
final class GitService {

    static let shared = GitService()

    private init() {}

    // MARK: - Git Binary

    private static let gitPath: String = {
        let candidates = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "git"
    }()

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

    @discardableResult
    func cloneRepo(url: String) async throws -> String {
        guard !url.isEmpty else {
            throw GitError.invalidURL("URL must not be empty")
        }

        let repoName = deriveName(from: url)
        let destURL = Self.reposBaseURL.appendingPathComponent(repoName, isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.reposBaseURL.path) {
            do {
                try fm.createDirectory(at: Self.reposBaseURL, withIntermediateDirectories: true)
            } catch {
                throw GitError.directoryCreationFailed(error.localizedDescription)
            }
        }

        let finalDest = uniqueDestination(base: destURL)
        try await run(["git", "clone", url, finalDest.path])
        return finalDest.path
    }

    // MARK: - Branches

    func listBranches(repoPath: String) -> [String] {
        guard let output = try? runSync(["git", "-C", repoPath, "branch", "--format=%(refname:short)"]) else {
            return []
        }
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Status

    static func status(repoPath: String) async throws -> [FileChange] {
        let (stdout, _) = try await runStatic(args: ["status", "--porcelain"], cwd: repoPath)
        return parseStatus(stdout)
    }

    private static func parseStatus(_ output: String) -> [FileChange] {
        output
            .components(separatedBy: "\n")
            .compactMap { line -> FileChange? in
                guard line.count >= 3 else { return nil }
                let xy = String(line.prefix(2))
                let path = String(line.dropFirst(3))
                guard !path.isEmpty else { return nil }
                let displayPath = path.contains(" -> ") ? String(path.split(separator: ">").last ?? Substring(path)).trimmingCharacters(in: .whitespaces) : path
                return FileChange(path: displayPath, status: FileChange.Status(rawCode: xy))
            }
    }

    // MARK: - Diff

    static func diff(repoPath: String, file: String? = nil, includeStaged: Bool = false) async throws -> String {
        var args = ["diff"]
        if includeStaged { args.append("--cached") }
        args += ["--no-color", "--"]
        if let file { args.append(file) } else { args.append(".") }

        do {
            let (stdout, _) = try await runStatic(args: args, cwd: repoPath)
            if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !includeStaged {
                return try await diff(repoPath: repoPath, file: file, includeStaged: true)
            }
            return stdout
        } catch GitError.commandFailed {
            return file.map { "# \($0) is untracked (no diff available)" } ?? ""
        }
    }

    // MARK: - Add / Commit / Push

    static func add(repoPath: String, files: [String]) async throws {
        if files.isEmpty { return }
        try await runStatic(args: ["add", "--"] + files, cwd: repoPath)
    }

    static func commit(repoPath: String, message: String, files: [String]) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.commandFailed("Commit message cannot be empty")
        }
        try await add(repoPath: repoPath, files: files)
        try await runStatic(args: ["commit", "-m", message], cwd: repoPath)
    }

    static func push(repoPath: String) async throws {
        do {
            try await runStatic(args: ["push"], cwd: repoPath)
        } catch GitError.commandFailed(let msg) {
            if msg.contains("no upstream") || msg.contains("set-upstream") {
                let (branchOut, _) = try await runStatic(
                    args: ["rev-parse", "--abbrev-ref", "HEAD"],
                    cwd: repoPath
                )
                let branch = branchOut.trimmingCharacters(in: .whitespacesAndNewlines)
                try await runStatic(
                    args: ["push", "--set-upstream", "origin", branch],
                    cwd: repoPath
                )
            } else {
                throw GitError.commandFailed(msg)
            }
        }
    }

    // MARK: - Current Branch

    static func currentBranch(repoPath: String) async throws -> String {
        let (stdout, _) = try await runStatic(
            args: ["rev-parse", "--abbrev-ref", "HEAD"],
            cwd: repoPath
        )
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Remove Repo from Disk

    func removeRepoDirectory(atPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Run Helpers (instance)

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

    func runSync(_ args: [String]) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        let paths = ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = (paths + [existing]).joined(separator: ":")
        process.environment = env

        do { try process.run() } catch {
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

    // MARK: - Run Helpers (static)

    @discardableResult
    static func runStatic(
        args: [String],
        cwd: String? = nil
    ) async throws -> (stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: gitPath)
            task.arguments = args

            if let cwd {
                task.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError  = stderrPipe

            do { try task.run() } catch {
                continuation.resume(throwing: GitError.gitNotFound)
                return
            }

            task.waitUntilExit()

            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

            if task.terminationStatus != 0 {
                let msg = stderr.isEmpty ? stdout : stderr
                continuation.resume(throwing: GitError.commandFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                return
            }

            continuation.resume(returning: (stdout, stderr))
        }
    }

    // MARK: - Name helpers

    private func deriveName(from url: String) -> String {
        var name = url.components(separatedBy: "/").last ?? "repo"
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted).joined()
        return safe.isEmpty ? "repo" : safe
    }

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
