import Foundation

struct GitHubRepositoryRef: Equatable {
    let owner: String
    let name: String

    var fullName: String { "\(owner)/\(name)" }
}

struct GitHubPullRequestMetadata: Identifiable, Equatable {
    struct Author: Equatable {
        let login: String
    }

    let id: Int
    let number: Int
    let title: String
    let url: URL?
    let state: String
    let isDraft: Bool
    let headRefName: String
    let baseRefName: String
    let headRefOID: String
    let author: Author?

    init(
        number: Int,
        title: String,
        url: URL?,
        state: String,
        isDraft: Bool,
        headRefName: String,
        baseRefName: String,
        headRefOID: String,
        author: Author?
    ) {
        self.id = number
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.headRefOID = headRefOID
        self.author = author
    }
}

struct GitHubCheckRun: Identifiable, Equatable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let detailsURL: URL?
    let startedAt: Date?
    let completedAt: Date?
    let appName: String?
}

struct GitHubChecksSnapshot: Equatable {
    let pullRequest: GitHubPullRequestMetadata
    let checkRuns: [GitHubCheckRun]

    var hasFailures: Bool {
        checkRuns.contains { $0.conclusion?.lowercased() == "failure" }
    }
}

struct ChecksUIRowViewModel: Identifiable, Equatable {
    enum State: String, Equatable {
        case passing
        case failing
        case running
        case pending
        case neutral
    }

    let id: Int
    let title: String
    let subtitle: String?
    let state: State
    let detailsURL: URL?
}

struct ChecksUIViewModel: Equatable {
    let pullRequestNumber: Int
    let pullRequestTitle: String
    let branchName: String
    let overallStateText: String
    let rows: [ChecksUIRowViewModel]

    static func from(snapshot: GitHubChecksSnapshot) -> ChecksUIViewModel {
        let rows = snapshot.checkRuns.map { run in
            ChecksUIRowViewModel(
                id: run.id,
                title: run.name,
                subtitle: run.appName,
                state: Self.state(for: run),
                detailsURL: run.detailsURL
            )
        }

        let overall: String
        if rows.contains(where: { $0.state == .failing }) {
            overall = "Failing"
        } else if rows.contains(where: { $0.state == .running || $0.state == .pending }) {
            overall = "In Progress"
        } else if rows.allSatisfy({ $0.state == .passing }) && !rows.isEmpty {
            overall = "Passing"
        } else {
            overall = "Unknown"
        }

        return ChecksUIViewModel(
            pullRequestNumber: snapshot.pullRequest.number,
            pullRequestTitle: snapshot.pullRequest.title,
            branchName: snapshot.pullRequest.headRefName,
            overallStateText: overall,
            rows: rows
        )
    }

    private static func state(for check: GitHubCheckRun) -> ChecksUIRowViewModel.State {
        let status = check.status.lowercased()
        let conclusion = check.conclusion?.lowercased()

        if status == "queued" || status == "requested" || status == "waiting" {
            return .pending
        }

        if status == "in_progress" || status == "pending" {
            return .running
        }

        if status == "completed" {
            switch conclusion {
            case "success":
                return .passing
            case "failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale":
                return .failing
            default:
                return .neutral
            }
        }

        return .neutral
    }
}
