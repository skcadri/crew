import SwiftUI

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

    // Toast
    @Published var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>? = nil

    let repoPath: String

    init(repoPath: String) {
        self.repoPath = repoPath
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

    init(repoPath: String) {
        _vm = StateObject(wrappedValue: GitPanelViewModel(repoPath: repoPath))
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

            // Changed file count badge
            if !vm.changes.isEmpty {
                Text("\(vm.changes.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
            }

            // Refresh
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

            // Commit
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
                        isSelected: vm.selectedFile?.id == change.id
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
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(file.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor))

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
    GitPanelView(repoPath: "/tmp/fake")
        .frame(width: 320, height: 600)
}
#endif
