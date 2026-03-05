import SwiftUI

/// Sheet presented when the user wants to add (clone) a new repository.
struct AddRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repoManager: RepoManager

    @State private var urlText: String = ""
    @State private var errorMessage: String? = nil
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Add Repository")
                    .font(.headline)
            }

            Divider()

            // URL Field
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository URL")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("https://github.com/user/repo.git", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isURLFocused)
                    .disabled(repoManager.isCloning)
                    .onSubmit { startClone() }
            }

            // Progress / Error
            Group {
                if repoManager.isCloning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text(repoManager.cloneProgress.isEmpty ? "Cloning…" : repoManager.cloneProgress)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 24)

            Divider()

            // Action Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(repoManager.isCloning)

                Button("Clone") {
                    startClone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || repoManager.isCloning)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { isURLFocused = true }
    }

    // MARK: - Actions

    private func startClone() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil

        Task {
            do {
                try await repoManager.addRepo(url: trimmed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AddRepoSheet(repoManager: RepoManager.shared)
}
