import SwiftUI

// MARK: - GitPanelViewModel

@MainActor
final class GitPanelViewModel: ObservableObject {
    enum InspectorTab: String, CaseIterable, Identifiable {
        case diff = "Diff"
        case comments = "Comments"

        var id: String { rawValue }
    }

    @Published var changes: [FileChange] = []
    @Published var selectedFile: FileChange? = nil
    @Published var diffText: String = ""
    @Published var isLoadingStatus: Bool = false
    @Published var isLoadingDiff: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showCommitSheet: Bool = false
    @Published var checkedFiles: Set<String> = []

    @Published var selectedInspectorTab: InspectorTab = .diff
    @Published var isLoadingComments: Bool = false
    @Published var prCommentError: String? = nil
    @Published var prComments: [PRReviewComment] = []
    @Published var currentPRNumber: Int? = nil
    @Published var locallyAddressedCommentIDs: Set<String> = []

    // Toast
    @Published var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>? = nil

    let repoPath: String

    var groupedPRComments: [PRCommentFileGroup] {
        Dictionary(grouping: prComments, by: \.path)
            .map { path, comments in
                PRCommentFileGroup(path: path, comments: comments.sorted { lhs, rhs in
                    (lhs.line ?? Int.max, lhs.id) < (rhs.line ?? Int.max, rhs.id)
                })
            }
            .sorted { $0.path < $1.path }
    }

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

        await refreshPRComments()
    }

    func refreshPRComments() async {
        isLoadingComments = true
        prCommentError = nil
        defer { isLoadingComments = false }

        do {
            let snapshot = try await GitHubPRCommentSyncService.fetchCurrentPRComments(repoPath: repoPath)
            prComments = snapshot.comments
            currentPRNumber = snapshot.pullRequestNumber

            let knownIDs = Set(snapshot.comments.map(\.id))
            locallyAddressedCommentIDs = locallyAddressedCommentIDs.intersection(knownIDs)
        } catch {
            currentPRNumber = nil
            prComments = []
            prCommentError = error.localizedDescription
        }
    }

    func toggleLocallyAddressed(_ comment: PRReviewComment) {
        if locallyAddressedCommentIDs.contains(comment.id) {
            locallyAddressedCommentIDs.remove(comment.id)
        } else {
            locallyAddressedCommentIDs.insert(comment.id)
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
@MainActor
struct GitPanelView: View {

    @StateObject private var vm: GitPanelViewModel
    @ObservedObject private var router: ChecksPanelRouter

    private let workspaceKey: String

    init(
        workspaceKey: String,
        repoPath: String,
        router: ChecksPanelRouter
    ) {
        self.workspaceKey = workspaceKey
        self.router = router
        _vm = StateObject(wrappedValue: GitPanelViewModel(repoPath: repoPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let err = vm.errorMessage {
                errorBanner(err)
            }

            if selectedTab == .checks {
                checksPlaceholder
            } else if vm.changes.isEmpty && !vm.isLoadingStatus {
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

    private var selectedTab: InspectorPanelTab {
        router.selectedTab(for: workspaceKey)
    }

    private var tabBinding: Binding<InspectorPanelTab> {
        Binding(
            get: { router.selectedTab(for: workspaceKey) },
            set: { router.setSelectedTab($0, for: workspaceKey) }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("Git", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold))

            Picker("Inspector tab", selection: tabBinding) {
                ForEach(InspectorPanelTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            Spacer()

            if let pr = vm.currentPRNumber {
                Text("PR #\(pr)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }

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
            .help(selectedTab == .checks ? "Refresh checks panel" : "Refresh git status and PR comments")

            if selectedTab == .changes {
                Button {
                    vm.showCommitSheet = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.plain)
                .disabled(vm.changes.isEmpty)
                .help("Open commit sheet")
            }
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

    private var checksPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Checks panel integration ready")
                .font(.callout.weight(.medium))
            Text("Use the Checks tab for TODOs and readiness. This inspector tab is reserved for provider-backed checks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content split (file list + inspector)


    private var contentSplit: some View {
        VSplitView {
            fileList
                .frame(minHeight: 80, maxHeight: 220)

            inspectorPanel
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

    // MARK: - Inspector panel

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $vm.selectedInspectorTab) {
                ForEach(GitPanelViewModel.InspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch vm.selectedInspectorTab {
            case .diff:
                diffPanel
            case .comments:
                PRCommentsListView(
                    groups: vm.groupedPRComments,
                    locallyAddressed: vm.locallyAddressedCommentIDs,
                    isLoading: vm.isLoadingComments,
                    errorMessage: vm.prCommentError,
                    onRefresh: {
                        Task { await vm.refreshPRComments() }
                    },
                    onToggleAddressed: { vm.toggleLocallyAddressed($0) }
                )
            }
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
    GitPanelView(
        workspaceKey: "preview-workspace",
        repoPath: "/tmp/fake",
        router: .shared
    )
    .frame(width: 320, height: 600)
}
#endif
