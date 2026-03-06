import SwiftUI
import Foundation

@MainActor
final class NotesPanelViewModel: ObservableObject {
    @Published var notesText: String = ""
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastSavedAt: Date? = nil

    private let contextDirectoryURL: URL
    private let notesFileURL: URL
    private var saveTask: Task<Void, Never>? = nil
    private var isApplyingLoadedText = false

    init(repoPath: String) {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        contextDirectoryURL = repoURL.appendingPathComponent(".context", isDirectory: true)
        notesFileURL = contextDirectoryURL.appendingPathComponent("notes.md", isDirectory: false)
        loadNotes()
    }

    deinit {
        saveTask?.cancel()
    }

    func updateNotes(_ text: String) {
        notesText = text
        guard !isApplyingLoadedText else { return }
        scheduleAutosave()
    }

    func forceSave() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    var notesFilePath: String {
        notesFileURL.path
    }

    private func loadNotes() {
        isLoading = true
        errorMessage = nil

        do {
            try ensureContextPathExists()

            if !FileManager.default.fileExists(atPath: notesFileURL.path) {
                try "".write(to: notesFileURL, atomically: true, encoding: .utf8)
            }

            let loaded = try String(contentsOf: notesFileURL, encoding: .utf8)
            isApplyingLoadedText = true
            notesText = loaded
            isApplyingLoadedText = false

            let attrs = try? FileManager.default.attributesOfItem(atPath: notesFileURL.path)
            lastSavedAt = attrs?[.modificationDate] as? Date
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.saveNow()
            }
        }
    }

    private func saveNow() {
        isSaving = true
        defer { isSaving = false }

        do {
            try ensureContextPathExists()
            try notesText.write(to: notesFileURL, atomically: true, encoding: .utf8)
            lastSavedAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save notes: \(error.localizedDescription)"
        }
    }

    private func ensureContextPathExists() throws {
        if !FileManager.default.fileExists(atPath: contextDirectoryURL.path) {
            try FileManager.default.createDirectory(
                at: contextDirectoryURL,
                withIntermediateDirectories: true
            )
        }
    }
}

struct NotesPanelView: View {
    @StateObject private var vm: NotesPanelViewModel

    init(repoPath: String) {
        _vm = StateObject(wrappedValue: NotesPanelViewModel(repoPath: repoPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if vm.isLoading {
                ProgressView("Loading notes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorAndPreview
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let date = vm.lastSavedAt {
                Text("Saved \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if vm.isSaving {
                ProgressView()
                    .controlSize(.mini)
            }

            Button("Save") {
                vm.forceSave()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var editorAndPreview: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Markdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: { vm.notesText },
                    set: { vm.updateNotes($0) }
                ))
                .font(.system(.body, design: .monospaced))
            }
            .padding(8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    markdownPreview
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if vm.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Nothing here yet. Start typing notes on the left.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let attributed = try? AttributedString(markdown: vm.notesText) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(vm.notesText)
                .textSelection(.enabled)
        }
    }
}

#if DEBUG
#Preview {
    NotesPanelView(repoPath: "/tmp")
        .frame(width: 520, height: 420)
}
#endif
