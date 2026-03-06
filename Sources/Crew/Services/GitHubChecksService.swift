import Foundation

enum GitHubChecksError: Error, LocalizedError {
    case ghNotFound
    case commandFailed(command: [String], code: Int32, stderr: String)
    case invalidResponse(String)
    case parseFailed(String)
    case remoteNotFound
    case unsupportedRemoteURL(String)
    case pullRequestNotFound(branch: String)

    var errorDescription: String? {
        switch self {
        case .ghNotFound:
            return "GitHub CLI (gh) not found in PATH"
        case .commandFailed(let command, let code, let stderr):
            return "gh command failed (\(code)): \(command.joined(separator: " "))\n\(stderr)"
        case .invalidResponse(let message):
            return "Invalid GitHub response: \(message)"
        case .parseFailed(let message):
            return "Failed to parse GitHub response: \(message)"
        case .remoteNotFound:
            return "Could not find git remote 'origin'"
        case .unsupportedRemoteURL(let remote):
            return "Unsupported GitHub remote format: \(remote)"
        case .pullRequestNotFound(let branch):
            return "No pull request found for branch '\(branch)'"
        }
    }
}

final class GitHubChecksService {
    static let shared = GitHubChecksService()

    private init() {}

    func fetchPullRequestMetadata(repoPath: String, branch: String? = nil) async throws -> GitHubPullRequestMetadata {
        let branchToQuery = try await resolvedBranch(repoPath: repoPath, explicitBranch: branch)

        let data = try await runGH(
            [
                "pr", "list",
                "--head", branchToQuery,
                "--state", "all",
                "--limit", "1",
                "--json", "number,title,url,state,isDraft,headRefName,baseRefName,headRefOid,author"
            ],
            cwd: repoPath
        )

        let decoder = JSONDecoder()
        do {
            let prs = try decoder.decode([PRListItem].self, from: data)
            guard let first = prs.first else {
                throw GitHubChecksError.pullRequestNotFound(branch: branchToQuery)
            }
            return first.toDomain()
        } catch let error as GitHubChecksError {
            throw error
        } catch {
            throw GitHubChecksError.parseFailed(error.localizedDescription)
        }
    }

    func fetchChecksSnapshot(repoPath: String, branch: String? = nil) async throws -> GitHubChecksSnapshot {
        let pr = try await fetchPullRequestMetadata(repoPath: repoPath, branch: branch)
        let repository = try await resolveRepository(repoPath: repoPath)
        let runs = try await fetchCheckRuns(repo: repository, headSHA: pr.headRefOID, repoPath: repoPath)
        return GitHubChecksSnapshot(pullRequest: pr, checkRuns: runs)
    }

    func fetchChecksViewModel(repoPath: String, branch: String? = nil) async throws -> ChecksUIViewModel {
        let snapshot = try await fetchChecksSnapshot(repoPath: repoPath, branch: branch)
        return ChecksUIViewModel.from(snapshot: snapshot)
    }

    func rerunCheckRun(repoPath: String, checkRunID: Int) async throws {
        let repository = try await resolveRepository(repoPath: repoPath)
        let endpoint = "repos/\(repository.owner)/\(repository.name)/check-runs/\(checkRunID)/rerequest"

        _ = try await runGH(
            ["api", "--method", "POST", endpoint],
            cwd: repoPath
        )
    }

    // MARK: - Internals

    private func fetchCheckRuns(repo: GitHubRepositoryRef, headSHA: String, repoPath: String) async throws -> [GitHubCheckRun] {
        let endpoint = "repos/\(repo.owner)/\(repo.name)/commits/\(headSHA)/check-runs?per_page=100"

        let data = try await runGH(
            ["api", "--header", "Accept: application/vnd.github+json", endpoint],
            cwd: repoPath
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let response = try decoder.decode(CheckRunsResponse.self, from: data)
            return response.checkRuns.map { $0.toDomain() }
        } catch {
            throw GitHubChecksError.parseFailed(error.localizedDescription)
        }
    }

    private func resolvedBranch(repoPath: String, explicitBranch: String?) async throws -> String {
        if let explicitBranch, !explicitBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitBranch
        }

        return try await GitService.currentBranch(repoPath: repoPath)
    }

    private func resolveRepository(repoPath: String) async throws -> GitHubRepositoryRef {
        let (stdout, _) = try await GitService.runStatic(args: ["remote", "get-url", "origin"], cwd: repoPath)
        let remote = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty else {
            throw GitHubChecksError.remoteNotFound
        }
        return try parseGitHubRemote(remote)
    }

    private func parseGitHubRemote(_ remote: String) throws -> GitHubRepositoryRef {
        let cleaned = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        // Examples:
        //  - git@github.com:owner/repo.git
        //  - https://github.com/owner/repo.git
        //  - ssh://git@github.com/owner/repo.git
        if cleaned.contains("github.com") {
            let normalized = cleaned
                .replacingOccurrences(of: "git@github.com:", with: "github.com/")
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "ssh://", with: "")
                .replacingOccurrences(of: "git@", with: "")

            guard let repoRange = normalized.range(of: "github.com/") else {
                throw GitHubChecksError.unsupportedRemoteURL(remote)
            }

            var slug = String(normalized[repoRange.upperBound...])
            if slug.hasSuffix(".git") { slug.removeLast(4) }
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let parts = slug.split(separator: "/").map(String.init)
            guard parts.count >= 2 else {
                throw GitHubChecksError.unsupportedRemoteURL(remote)
            }

            return GitHubRepositoryRef(owner: parts[0], name: parts[1])
        }

        throw GitHubChecksError.unsupportedRemoteURL(remote)
    }

    private func runGH(_ args: [String], cwd: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + args
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var env = ProcessInfo.processInfo.environment
            let paths = ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
            env["PATH"] = (paths + [env["PATH"] ?? ""]).joined(separator: ":")
            process.environment = env

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitHubChecksError.ghNotFound)
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(decoding: stderrData, as: UTF8.self)

            guard process.terminationStatus == 0 else {
                continuation.resume(
                    throwing: GitHubChecksError.commandFailed(
                        command: ["gh"] + args,
                        code: process.terminationStatus,
                        stderr: stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                return
            }

            continuation.resume(returning: stdoutData)
        }
    }
}

// MARK: - DTOs

private struct PRListItem: Decodable {
    struct AuthorDTO: Decodable {
        let login: String
    }

    let number: Int
    let title: String
    let url: String?
    let state: String
    let isDraft: Bool
    let headRefName: String
    let baseRefName: String
    let headRefOid: String
    let author: AuthorDTO?

    func toDomain() -> GitHubPullRequestMetadata {
        GitHubPullRequestMetadata(
            number: number,
            title: title,
            url: url.flatMap(URL.init(string:)),
            state: state,
            isDraft: isDraft,
            headRefName: headRefName,
            baseRefName: baseRefName,
            headRefOID: headRefOid,
            author: author.map { .init(login: $0.login) }
        )
    }
}

private struct CheckRunsResponse: Decodable {
    let totalCount: Int
    let checkRuns: [CheckRunDTO]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }
}

private struct CheckRunDTO: Decodable {
    struct AppDTO: Decodable {
        let name: String
    }

    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let detailsURL: String?
    let startedAt: Date?
    let completedAt: Date?
    let app: AppDTO?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case conclusion
        case detailsURL = "details_url"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case app
    }

    func toDomain() -> GitHubCheckRun {
        GitHubCheckRun(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            detailsURL: detailsURL.flatMap(URL.init(string:)),
            startedAt: startedAt,
            completedAt: completedAt,
            appName: app?.name
        )
    }
}
