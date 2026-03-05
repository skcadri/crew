import SwiftUI

// MARK: - CommitSheet

/// A sheet that lets the user compose a commit message, select which files to stage,
/// and optionally push after committing.
struct CommitSheet: View {

    let repoPath: String
    let changes: [FileChange]
    var onComplete: (() -> Void)?   // called after a successful commit (or push)

    @Environment(\.dismiss) private var dismiss

    @State private var commitMessage: String = ""
    @State private var checkedFiles: Set<String> = []
    @State private var shouldPush: Bool = false

    // Operation state
    @State private var isWorking: Bool = false
    @State private var alertItem: AlertItem? = nil

    // Alert model
    struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isSuccess: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text("Commit Changes")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Commit message
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Commit Message", systemImage: "text.bubble")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $commitMessage)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 72, maxHeight: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if commitMessage.isEmpty {
                                    Text("Enter a commit message…")
                                        .foregroundStyle(.tertiary)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    // File selector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Files to Stage", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button("All") { selectAll() }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Button("None") { deselectAll() }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(spacing: 2) {
                            ForEach(changes) { change in
                                FileChangeRow(
                                    change: change,
                                    isChecked: Binding(
                                        get: { checkedFiles.contains(change.path) },
                                        set: { on in
                                            if on { checkedFiles.insert(change.path) }
                                            else  { checkedFiles.remove(change.path) }
                                        }
                                    )
                                )
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // Push toggle
                    Toggle(isOn: $shouldPush) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(shouldPush ? Color.accentColor : Color.secondary)
                            Text("Push after commit")
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button {
                    Task { await performCommit() }
                } label: {
                    Label(
                        shouldPush ? "Commit & Push" : "Commit",
                        systemImage: shouldPush ? "arrow.up.circle.fill" : "checkmark.circle.fill"
                    )
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isWorking || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checkedFiles.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .alert(item: $alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK")) {
                    if item.isSuccess {
                        dismiss()
                        onComplete?()
                    }
                }
            )
        }
        .onAppear {
            // Pre-select all files
            checkedFiles = Set(changes.map(\.path))
        }
    }

    // MARK: - Actions

    private func selectAll() {
        checkedFiles = Set(changes.map(\.path))
    }

    private func deselectAll() {
        checkedFiles = []
    }

    private func performCommit() async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let files = Array(checkedFiles)
        guard !files.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            try await GitService.commit(repoPath: repoPath, message: message, files: files)

            if shouldPush {
                try await GitService.push(repoPath: repoPath)
                alertItem = AlertItem(
                    title: "Committed & Pushed",
                    message: "Changes committed and pushed to remote successfully.",
                    isSuccess: true
                )
            } else {
                alertItem = AlertItem(
                    title: "Committed",
                    message: "Changes committed successfully.",
                    isSuccess: true
                )
            }
        } catch {
            alertItem = AlertItem(
                title: "Git Error",
                message: error.localizedDescription,
                isSuccess: false
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    CommitSheet(
        repoPath: "/tmp/fake-repo",
        changes: [
            FileChange(path: "Sources/Crew/ContentView.swift", status: .modified),
            FileChange(path: "Sources/Crew/NewFeature.swift",  status: .added),
            FileChange(path: "Sources/Crew/Deprecated.swift",  status: .deleted),
            FileChange(path: "README.md",                      status: .modified),
        ]
    )
}
#endif
