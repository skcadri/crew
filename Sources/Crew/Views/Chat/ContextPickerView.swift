import SwiftUI

struct ContextPickerView: View {
    let workspacePath: String
    let selectedFiles: Set<String>
    let onToggle: (String) -> Void

    @State private var files: [String] = []
    @State private var newFileName: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Context")
                    .font(.headline)
                Spacer()
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if files.isEmpty {
                Text("No files in .context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(files, id: \.self) { file in
                            Toggle(isOn: Binding(
                                get: { selectedFiles.contains(file) },
                                set: { _ in onToggle(file) }
                            )) {
                                Text(file)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            HStack(spacing: 6) {
                TextField("new-file.md", text: $newFileName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    createFile()
                }
                .disabled(newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 260)
        .padding(10)
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            files = try ContextFileService.shared.listFiles(workspacePath: workspacePath)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFile() {
        let trimmed = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try ContextFileService.shared.writeFile(workspacePath: workspacePath, relativePath: trimmed, content: "")
            if !selectedFiles.contains(trimmed) {
                onToggle(trimmed)
            }
            newFileName = ""
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
