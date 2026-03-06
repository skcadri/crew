import SwiftUI

struct PRCommentsListView: View {
    let groups: [PRCommentFileGroup]
    let locallyAddressed: Set<String>
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onToggleAddressed: (PRReviewComment) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage {
                errorBanner(errorMessage)
            }

            if isLoading && groups.isEmpty {
                ProgressView("Syncing PR comments…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                emptyState
            } else {
                commentsList
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("PR Comments", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))

            Spacer()

            let commentCount = groups.reduce(0) { $0 + $1.comments.count }
            Text("\(commentCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue, in: Capsule())

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh comments from GitHub")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var commentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.comments) { comment in
                                commentRow(comment)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(group.path)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            if group.unresolvedCount > 0 {
                                Text("\(group.unresolvedCount) open")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(8)
        }
    }

    private func commentRow(_ comment: PRReviewComment) -> some View {
        let isLocallyAddressed = locallyAddressed.contains(comment.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: comment.state.symbolName)
                    .foregroundStyle(comment.state == .resolved ? .green : .orange)
                    .font(.caption)

                if let line = comment.line {
                    Text("L\(line)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                if comment.isOutdated {
                    Text("Outdated")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(comment.state.displayText)
                    .font(.caption2)
                    .foregroundStyle(comment.state == .resolved ? .green : .orange)
            }

            Text(comment.body)
                .font(.caption)
                .lineLimit(5)

            HStack(spacing: 8) {
                if let author = comment.authorLogin {
                    Text("@\(author)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isLocallyAddressed ? "Marked addressed" : "Mark addressed") {
                    onToggleAddressed(comment)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isLocallyAddressed ? Color.green.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isLocallyAddressed ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No PR comments")
                .font(.callout.weight(.medium))

            Text("Pull request review comments will appear here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }
}
