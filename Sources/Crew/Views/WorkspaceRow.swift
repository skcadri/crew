import SwiftUI

/// A single row in the sidebar representing one git worktree / agent workspace.
/// Displays a coloured status indicator dot, branch name, and optional model label.
struct WorkspaceRow: View {

    let worktree: Worktree
    var onSetStatus: ((WorktreeStatus) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(statusColor.opacity(0.3), lineWidth: 3)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(worktree.branch)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let raw = worktree.selectedModel,
                   let agent = AgentType(rawValue: raw) {
                    Text(agent.shortName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let onSetStatus {
                Menu {
                    ForEach(WorktreeStatus.allCases) { status in
                        Button {
                            onSetStatus(status)
                        } label: {
                            Label(status.title, systemImage: status == worktree.status ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }

            Text(worktree.status.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch worktree.status {
        case .backlog: return .gray
        case .inProgress: return .blue
        case .inReview: return .orange
        case .done: return .green
        case .archived: return .secondary
        }
    }
}

#if DEBUG
#Preview {
    List {
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "feature/login-flow",
            path:          "/tmp/ws1",
            status:        .backlog,
            selectedModel: AgentType.claudeCode.rawValue
        ))
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "fix/crash-on-launch",
            path:          "/tmp/ws2",
            status:        .inProgress,
            selectedModel: AgentType.lmStudio.rawValue
        ))
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "chore/update-deps",
            path:          "/tmp/ws3",
            status:        .inReview,
            selectedModel: nil
        ))
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "release/1.0",
            path:          "/tmp/ws4",
            status:        .done,
            selectedModel: AgentType.codex.rawValue
        ))
    }
    .frame(width: 300, height: 260)
}
#endif
