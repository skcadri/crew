import SwiftUI

@MainActor
final class ChecksPanelViewModel: ObservableObject {
    @Published var gitSummary = GitStatusSummary()
    @Published var isLoadingGit = false
    @Published var gitError: String? = nil
    @Published var ciChecks: [CICheck] = [
        CICheck(name: "Build", status: .pending, details: "CI provider not connected yet"),
        CICheck(name: "Unit Tests", status: .pending, details: "Waiting for GitHub checks integration"),
        CICheck(name: "Lint", status: .pending, details: "Will be populated in A3")
    ]

    @Published var showFixErrorsStub = false

    let repoPath: String
    let todoStore: CheckTODOStore

    init(repoPath: String, worktreeId: UUID) {
        self.repoPath = repoPath
        self.todoStore = CheckTODOStore(worktreeId: worktreeId)
    }

    var completedTODOs: Int {
        todoStore.items.filter(\.isDone).count
    }

    var failingChecksCount: Int {
        ciChecks.filter { $0.status == .failure }.count
    }

    var readinessLabel: String {
        if gitSummary.totalChanges > 0 { return "Not ready" }
        if todoStore.items.contains(where: { !$0.isDone }) { return "Pending checklist" }
        if failingChecksCount > 0 { return "Blocked by CI" }
        return "Ready to open PR"
    }

    func refreshGitSummary() async {
        isLoadingGit = true
        gitError = nil
        defer { isLoadingGit = false }

        do {
            let changes = try await GitService.status(repoPath: repoPath)
            var summary = GitStatusSummary()
            for change in changes {
                switch change.status {
                case .modified: summary.modified += 1
                case .added, .copied, .renamed: summary.added += 1
                case .deleted: summary.deleted += 1
                case .untracked: summary.untracked += 1
                case .unknown: break
                }
            }
            gitSummary = summary
        } catch {
            gitError = error.localizedDescription
        }
    }
}

struct ChecksPanelView: View {
    @StateObject private var vm: ChecksPanelViewModel
    @State private var newTODOText: String = ""

    init(repoPath: String, worktreeId: UUID) {
        _vm = StateObject(wrappedValue: ChecksPanelViewModel(repoPath: repoPath, worktreeId: worktreeId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                gitStatusSection
                ciSection
                todoSection
                prReadinessSection
            }
            .padding(12)
        }
        .alert("Fix Errors", isPresented: $vm.showFixErrorsStub) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Auto-fix workflow will be wired in a later phase.")
        }
        .task {
            await vm.refreshGitSummary()
        }
    }

    private var gitStatusSection: some View {
        PanelSection(title: "Git Status Summary", icon: "arrow.triangle.branch") {
            if vm.isLoadingGit {
                ProgressView("Loading git status…")
                    .controlSize(.small)
            } else if let gitError = vm.gitError {
                Text(gitError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    statusRow("Modified", vm.gitSummary.modified)
                    statusRow("Added", vm.gitSummary.added)
                    statusRow("Deleted", vm.gitSummary.deleted)
                    statusRow("Untracked", vm.gitSummary.untracked)
                    Divider()
                    statusRow("Total", vm.gitSummary.totalChanges, emph: true)
                }
            }
        }
    }

    private var ciSection: some View {
        PanelSection(title: "CI Checks", icon: "checklist") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Placeholder checks (A3 will connect to GitHub checks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(vm.ciChecks) { check in
                    HStack {
                        Circle()
                            .fill(ciColor(check.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name)
                            Text(check.details)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(check.status.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var todoSection: some View {
        PanelSection(title: "TODO Checklist", icon: "checkmark.square") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Add TODO item…", text: $newTODOText)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        vm.todoStore.addItem(title: newTODOText)
                        newTODOText = ""
                    }
                    .disabled(newTODOText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if vm.todoStore.items.isEmpty {
                    Text("No TODO items yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.todoStore.items) { item in
                        HStack {
                            Button {
                                vm.todoStore.toggle(item)
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            }
                            .buttonStyle(.plain)

                            Text(item.title)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? .secondary : .primary)

                            Spacer()

                            Button(role: .destructive) {
                                vm.todoStore.remove(item)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var prReadinessSection: some View {
        PanelSection(title: "PR Readiness", icon: "paperplane") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(vm.readinessLabel)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Checklist")
                    Spacer()
                    Text("\(vm.completedTODOs)/\(vm.todoStore.items.count) complete")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Failing CI checks")
                    Spacer()
                    Text("\(vm.failingChecksCount)")
                        .foregroundStyle(vm.failingChecksCount == 0 ? Color.secondary : Color.red)
                }

                HStack {
                    Spacer()
                    Button {
                        vm.showFixErrorsStub = true
                    } label: {
                        Label("Fix Errors", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func statusRow(_ title: String, _ value: Int, emph: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .fontWeight(emph ? .semibold : .regular)
        }
    }

    private func ciColor(_ status: CICheck.Status) -> Color {
        switch status {
        case .pending: return .orange
        case .success: return .green
        case .failure: return .red
        }
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
