import Foundation

@MainActor
final class CheckTODOStore: ObservableObject {
    @Published private(set) var items: [CheckTODOItem] = []
    @Published var errorMessage: String? = nil

    private let db = Database.shared
    private let worktreeId: UUID

    init(worktreeId: UUID) {
        self.worktreeId = worktreeId
        load()
    }

    func load() {
        do {
            items = try db.fetchTODOItems(forWorktree: worktreeId)
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addItem(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = CheckTODOItem(worktreeId: worktreeId, title: trimmed)
        do {
            try db.insertTODOItem(item)
            items.append(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ item: CheckTODOItem) {
        do {
            try db.updateTODOItemDone(id: item.id, isDone: !item.isDone)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].isDone.toggle()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ item: CheckTODOItem) {
        do {
            try db.deleteTODOItem(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
