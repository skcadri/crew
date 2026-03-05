import SwiftUI

struct InspectorView: View {
    let selectedWorkspaceID: String?

    var body: some View {
        Group {
            if let id = selectedWorkspaceID {
                // TICKET-010: Replace with real model picker + git panel
                List {
                    Section("Workspace") {
                        LabeledContent("ID", value: id)
                        LabeledContent("Branch", value: "—")
                        LabeledContent("Status", value: "Idle")
                    }

                    Section("Model") {
                        // TICKET-010: ModelPickerView goes here
                        LabeledContent("Agent") {
                            Text("Not configured")
                                .foregroundStyle(.secondary)
                        }
                    }

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
            } else {
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
}

#Preview("Empty") {
    InspectorView(selectedWorkspaceID: nil)
        .frame(width: 260, height: 500)
}

#Preview("With workspace") {
    InspectorView(selectedWorkspaceID: "ws-1")
        .frame(width: 260, height: 500)
}
