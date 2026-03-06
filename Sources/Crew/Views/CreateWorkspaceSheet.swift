import SwiftUI

/// Sheet presented when the user wants to create a new agent workspace (git worktree).
/// Accepts a branch name and an optional agent model, then calls WorktreeManager.
struct CreateWorkspaceSheet: View {

    let repo: Repository
    @ObservedObject var worktreeManager: WorktreeManager
    @Environment(\.dismiss) private var dismiss

    @State private var branchName: String = ""
    @State private var selectedModel: AgentType? = nil
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("New Workspace")
                    .font(.title2.weight(.semibold))
                Text("Isolated worktree in **\(repo.name)**")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(.bottom, 20)

            // ── Branch name ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Branch Name")
                    .font(.subheadline.weight(.medium))
                TextField("feature/my-feature", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { create() }
                Text("A new branch will be created from the repo's current HEAD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // ── Model picker ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent (optional)")
                    .font(.subheadline.weight(.medium))
                Picker("Agent", selection: $selectedModel) {
                    Text("None").tag(AgentType?.none)
                    Divider()
                    ForEach(AgentType.allCases) { agentType in
                        Text(agentType.displayName).tag(AgentType?.some(agentType))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                Text("You can change the agent later from the inspector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Error banner ──────────────────────────────────────────────
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 12)
            }

            Spacer()

            // ── Action buttons ────────────────────────────────────────────
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    create()
                } label: {
                    if isCreating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Creating…")
                        }
                    } else {
                        Text("Create Workspace")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 420, height: 310)
    }

    // MARK: - Create

    private func create() {
        let branch = branchName.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty, !isCreating else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await worktreeManager.createWorkspace(
                    repoId:   repo.id,
                    repoPath: repo.localPath,
                    branch:   branch,
                    model:    selectedModel
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    CreateWorkspaceSheet(
        repo: Repository(
            name:      "my-project",
            url:       "https://github.com/example/my-project",
            localPath: "/tmp/my-project"
        ),
        worktreeManager: WorktreeManager.shared
    )
}
#endif
