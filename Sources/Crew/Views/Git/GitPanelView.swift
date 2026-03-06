import SwiftUI
import AppKit

// MARK: - GitPanelViewModel

@MainActor
final class GitPanelViewModel: ObservableObject {
    @Published var changes: [FileChange] = []
    @Published var selectedFile: FileChange? = nil
    @Published var diffText: String = ""
    @Published var isLoadingStatus: Bool = false
    @Published var isLoadingDiff: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showCommitSheet: Bool = false
    @Published var checkedFiles: Set<String> = []
    @Published var viewedFiles: Set<String> = []
    @Published var reviewNotesByFile: [String: String] = [:]
    @Published var reviewSummary: String = ""

    // Toast
    @Published var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>? = nil

    let repoPath: String
    let workspaceId: String

    var viewedCount: Int {
        changes.filter { viewedFiles.contains($0.path) }.count
    }

    var isReadyForReview: Bool {
        !changes.isEmpty && viewedCount == changes.count
    }

    init(repoPath: String, workspaceId: String) {
        self.repoPath = repoPath
        self.workspaceId = workspaceId
        self.viewedFiles = (try? Database.shared.fetchViewedFiles(workspaceId: workspaceId)) ?? []
    }

    // MARK: Refresh

    func refresh() async {
        isLoadingStatus = true
        errorMessage = nil
        defer { isLoadingStatus = false }

        do {
            let newChanges = try await GitService.status(repoPath: repoPath)
            changes = newChanges
            checkedFiles = Set(newChanges.map(\.path))

            let paths = Set(newChanges.map(\.path))
            viewedFiles = viewedFiles.intersection(paths)
            try? Database.shared.clearViewedFiles(workspaceId: workspaceId, keeping: paths)

            // Re-load diff for selected file if it's still present
            if let sel = selectedFile, newChanges.contains(sel) {
                await loadDiff(for: sel)
            } else if let first = newChanges.first {
                selectedFile = first
                await loadDiff(for: first)
            } else {
                selectedFile = nil
                diffText = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Select File

    func select(_ change: FileChange) {
        selectedFile = change
        Task { await loadDiff(for: change) }
    }

    // MARK: Viewed State

    func setViewed(_ viewed: Bool, for filePath: String) {
        if viewed { viewedFiles.insert(filePath) }
        else { viewedFiles.remove(filePath) }

        do {
            try Database.shared.setFileViewed(workspaceId: workspaceId, filePath: filePath, viewed: viewed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleViewed(for filePath: String) {
        setViewed(!viewedFiles.contains(filePath), for: filePath)
    }

    // MARK: Summary

    func generateReviewSummary() {
        guard !changes.isEmpty else {
            reviewSummary = "No changed files to review."
            return
        }

        let counts = Dictionary(grouping: changes, by: { $0.status }).mapValues(\.count)
        let unviewed = changes.map(\.path).filter { !viewedFiles.contains($0) }
        let viewed = changes.map(\.path).filter { viewedFiles.contains($0) }

        var lines: [String] = []
        lines.append("Review Summary")
        lines.append("Files: \(changes.count) total • \(viewed.count) viewed • \(unviewed.count) pending")
        lines.append("Gate: \(isReadyForReview ? "READY" : "NOT READY")")
        lines.append("")
        lines.append("Change breakdown:")
        lines.append("- Modified: \(counts[.modified, default: 0])")
        lines.append("- Added: \(counts[.added, default: 0])")
        lines.append("- Deleted: \(counts[.deleted, default: 0])")
        lines.append("- Renamed: \(counts[.renamed, default: 0])")
        lines.append("- Copied: \(counts[.copied, default: 0])")
        lines.append("- Untracked: \(counts[.untracked, default: 0])")

        if !unviewed.isEmpty {
            lines.append("")
            lines.append("Pending files:")
            lines += unviewed.map { "- \($0)" }
        }

        let comments = reviewNotesByFile
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.key < $1.key }

        if !comments.isEmpty {
            lines.append("")
            lines.append("Reviewer notes:")
            for (path, note) in comments {
                lines.append("- \(path): \(note.replacingOccurrences(of: "\n", with: " "))")
            }
        }

        reviewSummary = lines.joined(separator: "\n")
    }

    // MARK: Load Diff

    private func loadDiff(for change: FileChange) async {
        isLoadingDiff = true
        defer { isLoadingDiff = false }

        do {
            diffText = try await GitService.diff(repoPath: repoPath, file: change.path)
        } catch {
            diffText = "# Error loading diff: \(error.localizedDescription)"
        }
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }
}

// MARK: - GitPanelView

/// Inspector panel showing changed files and a unified diff viewer.
/// Sits in the right inspector column of the main window.
struct GitPanelView: View {

    @StateObject private var vm: GitPanelViewModel

    init(repoPath: String, workspaceId: String) {
        _vm = StateObject(wrappedValue: GitPanelViewModel(repoPath: repoPath, workspaceId: workspaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let err = vm.errorMessage {
                errorBanner(err)
            }

            if vm.changes.isEmpty && !vm.isLoadingStatus {
                emptyState
            } else {
                contentSplit
            }
        }
        .sheet(isPresented: $vm.showCommitSheet) {
            CommitSheet(
                repoPath: vm.repoPath,
                changes: vm.changes
            ) {
                Task { await vm.refresh() }
                vm.showToast("✅ Committed successfully")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = vm.toastMessage {
                toastView(toast)
            }
        }
        .task {
            await vm.refresh()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("Git", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold))

            Spacer()

            gateBadge

            if !vm.changes.isEmpty {
                Text("\(vm.changes.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
            }

            Button {
                vm.generateReviewSummary()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vm.reviewSummary, forType: .string)
                vm.showToast("Review summary copied")
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.plain)
            .disabled(vm.changes.isEmpty)
            .help("Generate review summary and copy to clipboard")

            Button {
                Task { await vm.refresh() }
            } label: {
                Image(systemName: vm.isLoadingStatus ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(vm.isLoadingStatus ? 360 : 0))
                    .animation(
                        vm.isLoadingStatus
                            ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: vm.isLoadingStatus
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh git status")

            Button {
                vm.showCommitSheet = true
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.plain)
            .disabled(vm.changes.isEmpty)
            .help("Open commit sheet")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var gateBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: vm.isReadyForReview ? "checkmark.seal.fill" : "hourglass")
            Text("\(vm.viewedCount)/\(vm.changes.count) viewed")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(vm.isReadyForReview ? Color.green : .secondary)
        .help(vm.isReadyForReview ? "Ready for review" : "Review pending")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("Working tree clean")
                .font(.callout.weight(.medium))
            Text("No uncommitted changes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content split (file list + diff)

    private var contentSplit: some View {
        VSplitView {
            fileList
                .frame(minHeight: 80, maxHeight: 220)

            diffPanel
                .frame(minHeight: 120, maxHeight: .infinity)
        }
    }

    // MARK: - File list

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(vm.changes) { change in
                    FileChangeRow(
                        change: change,
                        isChecked: Binding(
                            get: { vm.checkedFiles.contains(change.path) },
                            set: { on in
                                if on { vm.checkedFiles.insert(change.path) }
                                else  { vm.checkedFiles.remove(change.path) }
                            }
                        ),
                        isViewed: vm.viewedFiles.contains(change.path),
                        isSelected: vm.selectedFile?.id == change.id,
                        onToggleViewed: {
                            vm.toggleViewed(for: change.path)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.select(change)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Diff panel

    private var diffPanel: some View {
        ZStack {
            if vm.isLoadingDiff {
                ProgressView("Loading diff…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if let file = vm.selectedFile {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(file.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()

                            Button(vm.viewedFiles.contains(file.path) ? "Viewed" : "Mark viewed") {
                                vm.toggleViewed(for: file.path)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor))

                        Divider()

                        TextField(
                            "Add review note for this file (optional)",
                            text: Binding(
                                get: { vm.reviewNotesByFile[file.path, default: ""] },
                                set: { vm.reviewNotesByFile[file.path] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()
                    }
                    DiffView(diffText: vm.diffText)
                }
            }
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8), in: Capsule())
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: message)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Git Panel — with changes") {
    GitPanelView(repoPath: "/tmp/fake", workspaceId: "preview-workspace")
        .frame(width: 320, height: 600)
}
#endif
