import SwiftUI

struct DetailPlaceholder: View {
    let selectedWorkspaceID: String?

    var body: some View {
        Group {
            if let id = selectedWorkspaceID {
                // TICKET-007: Replace with real ChatView
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Workspace: \(id)")
                        .font(.title2)
                    Text("Chat & terminal will appear here")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "square.3.layers.3d.down.left")
                        .font(.system(size: 56))
                        .foregroundStyle(.tertiary)
                    Text("Select a workspace to begin")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Choose a workspace from the sidebar, or create a new one to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    Button(action: {
                        NotificationCenter.default.post(name: .crewNewWorkspace, object: nil)
                    }) {
                        Label("New Workspace", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                    .accessibilityLabel("Create new workspace")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}

#Preview("Empty state") {
    DetailPlaceholder(selectedWorkspaceID: nil)
        .frame(width: 700, height: 600)
}

#Preview("With workspace") {
    DetailPlaceholder(selectedWorkspaceID: "ws-1")
        .frame(width: 700, height: 600)
}
