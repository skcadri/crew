import Foundation

struct PRReviewComment: Identifiable, Hashable {
    enum ResolutionState: String, Hashable {
        case unresolved
        case resolved

        var displayText: String {
            switch self {
            case .unresolved: return "Unresolved"
            case .resolved: return "Resolved"
            }
        }

        var symbolName: String {
            switch self {
            case .unresolved: return "exclamationmark.bubble"
            case .resolved: return "checkmark.bubble"
            }
        }
    }

    let id: String
    let path: String
    let line: Int?
    let startLine: Int?
    let body: String
    let authorLogin: String?
    let createdAt: Date?
    let state: ResolutionState
    let isOutdated: Bool
    let url: String
}

struct PRCommentFileGroup: Identifiable, Hashable {
    let path: String
    let comments: [PRReviewComment]

    var id: String { path }

    var unresolvedCount: Int {
        comments.filter { $0.state == .unresolved }.count
    }
}
