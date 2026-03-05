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
            // porcelain XY — we combine X and Y codes
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
    case gitNotFound
    case commandFailed(String)
    case nothingToCommit

    var errorDescription: String? {
        switch self {
        case .gitNotFound:           return "git executable not found"
        case .commandFailed(let m):  return "git command failed: \(m)"
        case .nothingToCommit:       return "Nothing to commit"
        }
    }
}

// MARK: - GitService

/// All git operations for Crew — shells out to the system `git` binary.
/// Methods are `static` so they can be called without a shared instance.
enum GitService {

    // MARK: Helpers

    private static let gitPath: String = {
        // Prefer /usr/bin/git; fall back to searching PATH
        let candidates = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "git"
    }()

    /// Run a git command synchronously (on the calling async context).
    /// Returns (stdout, stderr, exitCode).
    @discardableResult
    static func run(
        args: [String],
        cwd: String? = nil,
        stdin stdinString: String? = nil
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

            if let input = stdinString {
                let stdinPipe = Pipe()
                task.standardInput = stdinPipe
                let data = Data(input.utf8)
                stdinPipe.fileHandleForWriting.write(data)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: GitError.gitNotFound)
                return
            }

            task.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(decoding: stdoutData, as: UTF8.self)
            let stderr = String(decoding: stderrData, as: UTF8.self)

            if task.terminationStatus != 0 {
                let msg = stderr.isEmpty ? stdout : stderr
                continuation.resume(throwing: GitError.commandFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                return
            }

            continuation.resume(returning: (stdout, stderr))
        }
    }

    // MARK: - Status

    /// Returns the list of changed files using `git status --porcelain`.
    static func status(repoPath: String) async throws -> [FileChange] {
        let (stdout, _) = try await run(args: ["status", "--porcelain"], cwd: repoPath)
        return parseStatus(stdout)
    }

    private static func parseStatus(_ output: String) -> [FileChange] {
        output
            .components(separatedBy: "\n")
            .compactMap { line -> FileChange? in
                guard line.count >= 3 else { return nil }
                // Porcelain format: XY<space>filename
                let xy = String(line.prefix(2))
                let path = String(line.dropFirst(3))
                guard !path.isEmpty else { return nil }
                // Handle renames: "old -> new" — take the new name after " -> "
                let displayPath = path.contains(" -> ") ? String(path.split(separator: ">").last ?? Substring(path)).trimmingCharacters(in: .whitespaces) : path
                return FileChange(path: displayPath, status: FileChange.Status(rawCode: xy))
            }
    }

    // MARK: - Diff

    /// Returns the unified diff for a specific file or all files.
    /// - `includeStaged`: if true, uses `--cached` to show staged changes
    static func diff(repoPath: String, file: String? = nil, includeStaged: Bool = false) async throws -> String {
        var args = ["diff"]
        if includeStaged { args.append("--cached") }
        args += ["--no-color", "--", ]
        if let file { args.append(file) } else { args.append(".") }

        do {
            let (stdout, _) = try await run(args: args, cwd: repoPath)
            if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !includeStaged {
                // Try staged if unstaged is empty
                return try await diff(repoPath: repoPath, file: file, includeStaged: true)
            }
            return stdout
        } catch GitError.commandFailed {
            // Possibly untracked file — show a placeholder
            return file.map { "# \($0) is untracked (no diff available)" } ?? ""
        }
    }

    // MARK: - Add

    /// Stages the given files (or all if empty).
    static func add(repoPath: String, files: [String]) async throws {
        if files.isEmpty { return }
        try await run(args: ["add", "--"] + files, cwd: repoPath)
    }

    // MARK: - Commit

    /// Stages `files`, then commits with `message`.
    static func commit(repoPath: String, message: String, files: [String]) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.commandFailed("Commit message cannot be empty")
        }
        // Stage files
        try await add(repoPath: repoPath, files: files)
        // Commit
        try await run(args: ["commit", "-m", message], cwd: repoPath)
    }

    // MARK: - Push

    /// Pushes the current branch to its tracking remote.
    /// Falls back to `git push --set-upstream origin <branch>` if no upstream is set.
    static func push(repoPath: String) async throws {
        do {
            try await run(args: ["push"], cwd: repoPath)
        } catch GitError.commandFailed(let msg) {
            if msg.contains("no upstream") || msg.contains("set-upstream") {
                // Get current branch name
                let (branchOut, _) = try await run(
                    args: ["rev-parse", "--abbrev-ref", "HEAD"],
                    cwd: repoPath
                )
                let branch = branchOut.trimmingCharacters(in: .whitespacesAndNewlines)
                try await run(
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
        let (stdout, _) = try await run(
            args: ["rev-parse", "--abbrev-ref", "HEAD"],
            cwd: repoPath
        )
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
