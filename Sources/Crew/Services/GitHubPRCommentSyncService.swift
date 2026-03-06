import Foundation

enum GitHubPRCommentSyncError: Error, LocalizedError {
    case ghNotInstalled
    case commandFailed(String)
    case notInPullRequestContext
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI (gh) not found"
        case .commandFailed(let message):
            return message
        case .notInPullRequestContext:
            return "No current PR found for this branch"
        case .invalidResponse:
            return "Could not parse GitHub response"
        }
    }
}

struct PRCommentSyncSnapshot {
    let pullRequestNumber: Int
    let comments: [PRReviewComment]

    var groupedByFile: [PRCommentFileGroup] {
        Dictionary(grouping: comments, by: \.path)
            .map { path, groupedComments in
                PRCommentFileGroup(
                    path: path,
                    comments: groupedComments.sorted { lhs, rhs in
                        (lhs.line ?? Int.max, lhs.id) < (rhs.line ?? Int.max, rhs.id)
                    }
                )
            }
            .sorted { $0.path < $1.path }
    }
}

final class GitHubPRCommentSyncService {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func fetchCurrentPRComments(repoPath: String) async throws -> PRCommentSyncSnapshot {
        let prNumber = try await currentPRNumber(repoPath: repoPath)
        guard let prNumber else {
            throw GitHubPRCommentSyncError.notInPullRequestContext
        }

        let repository = try await currentRepository(repoPath: repoPath)

        var allThreads: [GraphQLReviewThread] = []
        var cursor: String? = nil

        repeat {
            let page = try await fetchReviewThreadsPage(
                repoPath: repoPath,
                owner: repository.owner,
                name: repository.name,
                pullNumber: prNumber,
                afterCursor: cursor
            )
            allThreads.append(contentsOf: page.threads)
            cursor = page.nextCursor
        } while cursor != nil

        let comments = allThreads.flatMap { thread in
            thread.comments.nodes.map { node in
                PRReviewComment(
                    id: node.id,
                    path: thread.path,
                    line: node.line,
                    startLine: node.startLine,
                    body: node.body,
                    authorLogin: node.author?.login,
                    createdAt: node.createdAt,
                    state: thread.isResolved ? .resolved : .unresolved,
                    isOutdated: thread.isOutdated,
                    url: node.url
                )
            }
        }

        return PRCommentSyncSnapshot(
            pullRequestNumber: prNumber,
            comments: comments.sorted { lhs, rhs in
                (lhs.path, lhs.line ?? Int.max, lhs.id) < (rhs.path, rhs.line ?? Int.max, rhs.id)
            }
        )
    }

    private static func currentPRNumber(repoPath: String) async throws -> Int? {
        do {
            let output = try await runGH(
                args: ["pr", "view", "--json", "number", "--jq", ".number"],
                cwd: repoPath
            )
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        } catch GitHubPRCommentSyncError.commandFailed {
            return nil
        }
    }

    private static func currentRepository(repoPath: String) async throws -> (owner: String, name: String) {
        let output = try await runGH(
            args: ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            cwd: repoPath
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw GitHubPRCommentSyncError.invalidResponse }
        return (parts[0], parts[1])
    }

    private static func fetchReviewThreadsPage(
        repoPath: String,
        owner: String,
        name: String,
        pullNumber: Int,
        afterCursor: String?
    ) async throws -> (threads: [GraphQLReviewThread], nextCursor: String?) {
        let query = """
        query($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 50, after: $after) {
                nodes {
                  path
                  isResolved
                  isOutdated
                  comments(first: 100) {
                    nodes {
                      id
                      body
                      line
                      startLine
                      createdAt
                      url
                      author { login }
                    }
                  }
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
        }
        """

        var args = [
            "api", "graphql",
            "-f", "query=\(query)",
            "-f", "owner=\(owner)",
            "-f", "name=\(name)",
            "-F", "number=\(pullNumber)"
        ]

        if let afterCursor {
            args += ["-f", "after=\(afterCursor)"]
        }

        let output = try await runGH(args: args, cwd: repoPath)
        guard let data = output.data(using: .utf8) else {
            throw GitHubPRCommentSyncError.invalidResponse
        }

        let decoded = try decoder.decode(GraphQLResponse.self, from: data)
        guard let reviewThreads = decoded.data.repository.pullRequest?.reviewThreads else {
            throw GitHubPRCommentSyncError.invalidResponse
        }

        return (
            reviewThreads.nodes,
            reviewThreads.pageInfo.hasNextPage ? reviewThreads.pageInfo.endCursor : nil
        )
    }

    private static func runGH(args: [String], cwd: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + args
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitHubPRCommentSyncError.ghNotInstalled)
                return
            }

            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                let message = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: GitHubPRCommentSyncError.commandFailed(message))
                return
            }

            continuation.resume(returning: stdout)
        }
    }
}

private struct GraphQLResponse: Decodable {
    struct DataNode: Decodable {
        struct RepositoryNode: Decodable {
            struct PullRequestNode: Decodable {
                let reviewThreads: GraphQLReviewThreads
            }

            let pullRequest: PullRequestNode?
        }

        let repository: RepositoryNode
    }

    let data: DataNode
}

private struct GraphQLReviewThreads: Decodable {
    let nodes: [GraphQLReviewThread]
    let pageInfo: GraphQLPageInfo
}

private struct GraphQLReviewThread: Decodable {
    let path: String
    let isResolved: Bool
    let isOutdated: Bool
    let comments: GraphQLReviewCommentConnection
}

private struct GraphQLReviewCommentConnection: Decodable {
    let nodes: [GraphQLReviewCommentNode]
}

private struct GraphQLReviewCommentNode: Decodable {
    struct Author: Decodable {
        let login: String
    }

    let id: String
    let body: String
    let line: Int?
    let startLine: Int?
    let createdAt: Date?
    let url: String
    let author: Author?
}

private struct GraphQLPageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}
