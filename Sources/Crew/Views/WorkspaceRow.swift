import SwiftUI

/// A single row in the sidebar representing one git worktree / agent workspace.
/// Displays a coloured status indicator dot, branch name, and optional model label.
struct WorkspaceRow: View {

    let worktree: Worktree

    var body: some View {
        HStack(spacing: 8) {

            // ── Status dot ───────────────────────────────────────────────
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(statusColor.opacity(0.3), lineWidth: 3)
                )

            // ── Branch + model ───────────────────────────────────────────
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

            // ── Status badge ─────────────────────────────────────────────
            Text(statusLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Status helpers

    private var statusColor: Color {
        switch worktree.status {
        case .idle:      return .green
        case .running:   return .blue
        case .completed: return .teal
        case .error:     return .red
        }
    }

    private var statusLabel: String {
        switch worktree.status {
        case .idle:      return "Idle"
        case .running:   return "Running"
        case .completed: return "Done"
        case .error:     return "Error"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    List {
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "feature/login-flow",
            path:          "/tmp/ws1",
            status:        .idle,
            selectedModel: AgentType.claudeCode.rawValue
        ))
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "fix/crash-on-launch",
            path:          "/tmp/ws2",
            status:        .running,
            selectedModel: AgentType.lmStudio.rawValue
        ))
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "chore/update-deps",
            path:          "/tmp/ws3",
            status:        .completed,
            selectedModel: nil
        ))
        WorkspaceRow(worktree: Worktree(
            repoId:        UUID(),
            branch:        "experiment/new-arch",
            path:          "/tmp/ws4",
            status:        .error,
            selectedModel: AgentType.codex.rawValue
        ))
    }
    .frame(width: 260, height: 260)
}
#endif
