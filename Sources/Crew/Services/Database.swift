import Foundation
import SQLite

// MARK: - Database Errors

enum DatabaseError: Error, LocalizedError {
    case directoryCreationFailed(String)
    case insertFailed(String)
    case updateFailed(String)
    case deleteFailed(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let msg): return "Failed to create DB directory: \(msg)"
        case .insertFailed(let msg):            return "Insert failed: \(msg)"
        case .updateFailed(let msg):            return "Update failed: \(msg)"
        case .deleteFailed(let msg):            return "Delete failed: \(msg)"
        case .notFound(let msg):                return "Not found: \(msg)"
        }
    }
}

// MARK: - Database

/// SQLite persistence layer for Crew.
/// All database work is serialised on a private queue via SQLite.swift's connection.
final class Database {

    // MARK: Singleton

    static let shared = Database()

    // MARK: Connection

    private let db: Connection

    // MARK: Table Definitions

    // ---- repos ----
    private let repos          = Table("repos")
    private let repoId         = Expression<String>("id")
    private let repoName       = Expression<String>("name")
    private let repoURL        = Expression<String>("url")
    private let repoLocalPath  = Expression<String>("local_path")
    private let repoCreatedAt  = Expression<Int64>("created_at")

    // ---- worktrees ----
    private let worktrees         = Table("worktrees")
    private let wtId              = Expression<String>("id")
    private let wtRepoId          = Expression<String>("repo_id")
    private let wtBranch          = Expression<String>("branch")
    private let wtPath            = Expression<String>("path")
    private let wtStatus          = Expression<String>("status")
    private let wtSelectedModel   = Expression<String?>("selected_model")
    private let wtCreatedAt       = Expression<Int64>("created_at")

    // ---- messages ----
    private let messages      = Table("messages")
    private let msgId         = Expression<String>("id")
    private let msgWorktreeId = Expression<String>("worktree_id")
    private let msgRole       = Expression<String>("role")
    private let msgContent    = Expression<String>("content")
    private let msgTimestamp  = Expression<Int64>("timestamp")

    // ---- check_todos ----
    private let checkTodos         = Table("check_todos")
    private let todoId             = Expression<String>("id")
    private let todoWorktreeId     = Expression<String>("worktree_id")
    private let todoTitle          = Expression<String>("title")
    private let todoIsDone         = Expression<Bool>("is_done")
    private let todoCreatedAt      = Expression<Int64>("created_at")

    // MARK: Init

    private init() {
        let dbPath = Database.databasePath()
        do {
            db = try Connection(dbPath)
            try createTables()
        } catch {
            fatalError("Failed to open/initialise Crew database at \(dbPath): \(error)")
        }
    }

    // MARK: Path Helpers

    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let crewDir = appSupport.appendingPathComponent("Crew", isDirectory: true)

        // Auto-create the directory if needed
        if !FileManager.default.fileExists(atPath: crewDir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: crewDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                fatalError("Cannot create Crew support directory: \(error)")
            }
        }

        return crewDir.appendingPathComponent("crew.db").path
    }

    // MARK: Schema Creation

    private func createTables() throws {
        // repos
        try db.run(repos.create(ifNotExists: true) { t in
            t.column(repoId,        primaryKey: true)
            t.column(repoName)
            t.column(repoURL)
            t.column(repoLocalPath)
            t.column(repoCreatedAt)
        })

        // worktrees
        try db.run(worktrees.create(ifNotExists: true) { t in
            t.column(wtId,           primaryKey: true)
            t.column(wtRepoId)
            t.column(wtBranch)
            t.column(wtPath)
            t.column(wtStatus,       defaultValue: WorktreeStatus.idle.rawValue)
            t.column(wtSelectedModel)
            t.column(wtCreatedAt)
            t.foreignKey(wtRepoId, references: repos, repoId, delete: .cascade)
        })

        // messages
        try db.run(messages.create(ifNotExists: true) { t in
            t.column(msgId,         primaryKey: true)
            t.column(msgWorktreeId)
            t.column(msgRole)
            t.column(msgContent)
            t.column(msgTimestamp)
            t.foreignKey(msgWorktreeId, references: worktrees, wtId, delete: .cascade)
        })

        // check_todos
        try db.run(checkTodos.create(ifNotExists: true) { t in
            t.column(todoId,         primaryKey: true)
            t.column(todoWorktreeId)
            t.column(todoTitle)
            t.column(todoIsDone,     defaultValue: false)
            t.column(todoCreatedAt)
            t.foreignKey(todoWorktreeId, references: worktrees, wtId, delete: .cascade)
        })
    }
}

// MARK: - Repository CRUD

extension Database {

    func insertRepository(_ repo: Repository) throws {
        let insert = repos.insert(
            repoId        <- repo.id.uuidString,
            repoName      <- repo.name,
            repoURL       <- repo.url,
            repoLocalPath <- repo.localPath,
            repoCreatedAt <- Int64(repo.createdAt.timeIntervalSince1970)
        )
        do {
            try db.run(insert)
        } catch {
            throw DatabaseError.insertFailed(error.localizedDescription)
        }
    }

    func fetchAllRepositories() throws -> [Repository] {
        try db.prepare(repos.order(repoCreatedAt.asc)).map { row in
            Repository(
                id:          UUID(uuidString: row[repoId])!,
                name:        row[repoName],
                url:         row[repoURL],
                localPath:   row[repoLocalPath],
                createdAt:   Date(timeIntervalSince1970: Double(row[repoCreatedAt]))
            )
        }
    }

    func fetchRepository(id: UUID) throws -> Repository? {
        let query = repos.filter(repoId == id.uuidString)
        return try db.pluck(query).map { row in
            Repository(
                id:        UUID(uuidString: row[repoId])!,
                name:      row[repoName],
                url:       row[repoURL],
                localPath: row[repoLocalPath],
                createdAt: Date(timeIntervalSince1970: Double(row[repoCreatedAt]))
            )
        }
    }

    func updateRepository(_ repo: Repository) throws {
        let row = repos.filter(repoId == repo.id.uuidString)
        let count = try db.run(row.update(
            repoName      <- repo.name,
            repoURL       <- repo.url,
            repoLocalPath <- repo.localPath
        ))
        if count == 0 {
            throw DatabaseError.notFound("Repository \(repo.id)")
        }
    }

    func deleteRepository(id: UUID) throws {
        let row = repos.filter(repoId == id.uuidString)
        let count = try db.run(row.delete())
        if count == 0 {
            throw DatabaseError.notFound("Repository \(id)")
        }
    }
}

// MARK: - Worktree CRUD

extension Database {

    func insertWorktree(_ wt: Worktree) throws {
        let insert = worktrees.insert(
            wtId            <- wt.id.uuidString,
            wtRepoId        <- wt.repoId.uuidString,
            wtBranch        <- wt.branch,
            wtPath          <- wt.path,
            wtStatus        <- wt.status.rawValue,
            wtSelectedModel <- wt.selectedModel,
            wtCreatedAt     <- Int64(wt.createdAt.timeIntervalSince1970)
        )
        do {
            try db.run(insert)
        } catch {
            throw DatabaseError.insertFailed(error.localizedDescription)
        }
    }

    func fetchAllWorktrees() throws -> [Worktree] {
        try db.prepare(worktrees.order(wtCreatedAt.asc)).map { row in
            rowToWorktree(row)
        }
    }

    func fetchWorktrees(forRepo repoId: UUID) throws -> [Worktree] {
        let query = worktrees
            .filter(wtRepoId == repoId.uuidString)
            .order(wtCreatedAt.asc)
        return try db.prepare(query).map { row in rowToWorktree(row) }
    }

    func fetchWorktree(id: UUID) throws -> Worktree? {
        let query = worktrees.filter(wtId == id.uuidString)
        return try db.pluck(query).map { row in rowToWorktree(row) }
    }

    func updateWorktree(_ wt: Worktree) throws {
        let row = worktrees.filter(wtId == wt.id.uuidString)
        let count = try db.run(row.update(
            wtBranch        <- wt.branch,
            wtPath          <- wt.path,
            wtStatus        <- wt.status.rawValue,
            wtSelectedModel <- wt.selectedModel
        ))
        if count == 0 {
            throw DatabaseError.notFound("Worktree \(wt.id)")
        }
    }

    func updateWorktreeStatus(id: UUID, status: WorktreeStatus) throws {
        let row = worktrees.filter(wtId == id.uuidString)
        let count = try db.run(row.update(wtStatus <- status.rawValue))
        if count == 0 {
            throw DatabaseError.notFound("Worktree \(id)")
        }
    }

    func deleteWorktree(id: UUID) throws {
        let row = worktrees.filter(wtId == id.uuidString)
        let count = try db.run(row.delete())
        if count == 0 {
            throw DatabaseError.notFound("Worktree \(id)")
        }
    }

    private func rowToWorktree(_ row: Row) -> Worktree {
        Worktree(
            id:            UUID(uuidString: row[wtId])!,
            repoId:        UUID(uuidString: row[wtRepoId])!,
            branch:        row[wtBranch],
            path:          row[wtPath],
            status:        WorktreeStatus(rawValue: row[wtStatus]) ?? .idle,
            selectedModel: row[wtSelectedModel],
            createdAt:     Date(timeIntervalSince1970: Double(row[wtCreatedAt]))
        )
    }
}

// MARK: - ChatMessage CRUD

extension Database {

    func insertMessage(_ message: ChatMessage) throws {
        let insert = messages.insert(
            msgId         <- message.id.uuidString,
            msgWorktreeId <- message.worktreeId.uuidString,
            msgRole       <- message.role.rawValue,
            msgContent    <- message.content,
            msgTimestamp  <- Int64(message.timestamp.timeIntervalSince1970)
        )
        do {
            try db.run(insert)
        } catch {
            throw DatabaseError.insertFailed(error.localizedDescription)
        }
    }

    func fetchMessages(forWorktree worktreeId: UUID) throws -> [ChatMessage] {
        let query = messages
            .filter(msgWorktreeId == worktreeId.uuidString)
            .order(msgTimestamp.asc)
        return try db.prepare(query).map { row in rowToMessage(row) }
    }

    func fetchMessage(id: UUID) throws -> ChatMessage? {
        let query = messages.filter(msgId == id.uuidString)
        return try db.pluck(query).map { row in rowToMessage(row) }
    }

    func updateMessage(_ message: ChatMessage) throws {
        let row = messages.filter(msgId == message.id.uuidString)
        let count = try db.run(row.update(
            msgRole      <- message.role.rawValue,
            msgContent   <- message.content,
            msgTimestamp <- Int64(message.timestamp.timeIntervalSince1970)
        ))
        if count == 0 {
            throw DatabaseError.notFound("ChatMessage \(message.id)")
        }
    }

    func deleteMessage(id: UUID) throws {
        let row = messages.filter(msgId == id.uuidString)
        let count = try db.run(row.delete())
        if count == 0 {
            throw DatabaseError.notFound("ChatMessage \(id)")
        }
    }

    func deleteMessages(forWorktree worktreeId: UUID) throws {
        let rows = messages.filter(msgWorktreeId == worktreeId.uuidString)
        try db.run(rows.delete())
    }

    private func rowToMessage(_ row: Row) -> ChatMessage {
        ChatMessage(
            id:          UUID(uuidString: row[msgId])!,
            worktreeId:  UUID(uuidString: row[msgWorktreeId])!,
            role:        MessageRole(rawValue: row[msgRole]) ?? .user,
            content:     row[msgContent],
            timestamp:   Date(timeIntervalSince1970: Double(row[msgTimestamp]))
        )
    }
}

// MARK: - Checks TODO CRUD

extension Database {

    func insertTODOItem(_ item: CheckTODOItem) throws {
        let insert = checkTodos.insert(
            todoId         <- item.id.uuidString,
            todoWorktreeId <- item.worktreeId.uuidString,
            todoTitle      <- item.title,
            todoIsDone     <- item.isDone,
            todoCreatedAt  <- Int64(item.createdAt.timeIntervalSince1970)
        )
        do {
            try db.run(insert)
        } catch {
            throw DatabaseError.insertFailed(error.localizedDescription)
        }
    }

    func fetchTODOItems(forWorktree worktreeId: UUID) throws -> [CheckTODOItem] {
        let query = checkTodos
            .filter(todoWorktreeId == worktreeId.uuidString)
            .order(todoCreatedAt.asc)

        return try db.prepare(query).map { row in
            CheckTODOItem(
                id: UUID(uuidString: row[todoId])!,
                worktreeId: UUID(uuidString: row[todoWorktreeId])!,
                title: row[todoTitle],
                isDone: row[todoIsDone],
                createdAt: Date(timeIntervalSince1970: Double(row[todoCreatedAt]))
            )
        }
    }

    func updateTODOItemDone(id: UUID, isDone: Bool) throws {
        let row = checkTodos.filter(todoId == id.uuidString)
        let count = try db.run(row.update(todoIsDone <- isDone))
        if count == 0 {
            throw DatabaseError.notFound("TODO item \(id)")
        }
    }

    func deleteTODOItem(id: UUID) throws {
        let row = checkTodos.filter(todoId == id.uuidString)
        let count = try db.run(row.delete())
        if count == 0 {
            throw DatabaseError.notFound("TODO item \(id)")
        }
    }
}
