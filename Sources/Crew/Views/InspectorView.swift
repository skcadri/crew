import SwiftUI

struct InspectorView: View {
    let selectedWorkspaceID: String?

    @ObservedObject private var settings = SettingsStore.shared

    /// Local override for the model selected in this workspace.
    /// In a fuller implementation this would be persisted to the DB via WorktreeManager.
    @State private var workspaceModel: String = SettingsStore.shared.defaultModel

    // MARK: Workspace info (populated by GitService in a real flow)
    @State private var branch: String = "—"
    @State private var repoName: String = "—"
    @State private var gitStatus: String = "Idle"

    var body: some View {
        Group {
            if let id = selectedWorkspaceID {
                List {
                    // ── Workspace Info ────────────────────────────────
                    Section("Workspace") {
                        LabeledContent("Repo",   value: repoName)
                        LabeledContent("Branch", value: branch)
                        LabeledContent("Status", value: gitStatus)
                        LabeledContent("ID") {
                            Text(id)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    // ── Model Picker ──────────────────────────────────
                    Section("Model") {
                        HStack {
                            Text("Agent model")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ModelPickerView(
                                selectedModel: $workspaceModel,
                                localModels:   settings.lmStudioModels
                            )
                        }
                    }

                    // ── Git Panel placeholder ─────────────────────────
                    Section("Git") {
                        // TICKET-009: GitPanelView goes here
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No changes")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }

                        Button(action: {
                            // TICKET-009: Commit + push
                        }) {
                            Label("Commit & Push", systemImage: "arrow.triangle.branch")
                        }
                        .disabled(true)
                    }
                }
                .listStyle(.inset)
                .onAppear {
                    // Reset to default model when a workspace is first shown
                    workspaceModel = settings.defaultModel
                    loadWorkspaceInfo(id: id)
                }
                .onChange(of: selectedWorkspaceID) { _, newID in
                    if let newID {
                        workspaceModel = settings.defaultModel
                        loadWorkspaceInfo(id: newID)
                    }
                }
            } else {
                // ── Empty State ───────────────────────────────────────
                VStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No workspace selected")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.windowBackgroundColor))
        .frame(minWidth: 220)
    }

    // MARK: - Helpers

    /// Stub that would call GitService to populate branch/repo/status.
    private func loadWorkspaceInfo(id: String) {
        // TICKET-009 / TICKET-004 will supply real data from WorktreeManager.
        // For now we show placeholders.
        branch    = "feature/\(id.prefix(6))"
        repoName  = "crew-project"
        gitStatus = "Idle"
    }
}

#Preview("Empty") {
    InspectorView(selectedWorkspaceID: nil)
        .frame(width: 260, height: 500)
}

#Preview("With workspace") {
    InspectorView(selectedWorkspaceID: "ws-1abc23")
        .frame(width: 260, height: 500)
}
