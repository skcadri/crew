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

    // ---- plan_states ----
    private let planStates        = Table("plan_states")
    private let planWorktreeId    = Expression<String>("worktree_id")
    private let planStatus        = Expression<String>("status")
    private let planText          = Expression<String>("plan_text")
    private let planFeedback      = Expression<String?>("feedback")
    private let planUpdatedAt     = Expression<Int64>("updated_at")

    // ---- check_todos ----
    private let checkTodos         = Table("check_todos")
    private let todoId             = Expression<String>("id")
    private let todoWorktreeId     = Expression<String>("worktree_id")
    private let todoTitle          = Expression<String>("title")
    private let todoIsDone         = Expression<Bool>("is_done")
    private let todoCreatedAt      = Expression<Int64>("created_at")

    // ---- pending_questions ----
    private let pendingQuestions      = Table("pending_questions")
    private let pendingQuestionId     = Expression<String>("id")
    private let pendingQuestionWTID   = Expression<String>("worktree_id")
    private let pendingQuestionPrompt = Expression<String>("prompt")
    private let pendingQuestionAt     = Expression<Int64>("created_at")

    // ---- review_file_state ----
    private let reviewFileState    = Table("review_file_state")
    private let rfsWorkspaceId     = Expression<String>("workspace_id")
    private let rfsFilePath        = Expression<String>("file_path")
    private let rfsViewed          = Expression<Bool>("viewed")
    private let rfsUpdatedAt       = Expression<Int64>("updated_at")

    // ---- phase_a_checks ----
    private let phaseAChecks          = Table("phase_a_checks")
    private let phaseACheckId         = Expression<String>("id")
    private let phaseACheckWorktreeId = Expression<String>("worktree_id")
    private let phaseACheckProvider   = Expression<String>("provider")
    private let phaseACheckExternalId = Expression<String>("external_id")
    private let phaseACheckPayload    = Expression<String>("payload_json")
    private let phaseACheckUpdatedAt  = Expression<Int64>("updated_at")

    // ---- phase_a_review_state ----
    private let phaseAReviewStates          = Table("phase_a_review_states")
    private let phaseAReviewStateId         = Expression<String>("id")
    private let phaseAReviewStateWorktreeId = Expression<String>("worktree_id")
    private let phaseAReviewStatePayload    = Expression<String>("payload_json")
    private let phaseAReviewStateUpdatedAt  = Expression<Int64>("updated_at")

    // ---- phase_a_comments ----
    private let phaseAComments           = Table("phase_a_comments")
    private let phaseACommentId          = Expression<String>("id")
    private let phaseACommentWorktreeId  = Expression<String>("worktree_id")
    private let phaseACommentProvider    = Expression<String>("provider")
    private let phaseACommentExternalId  = Expression<String>("external_id")
    private let phaseACommentPayload     = Expression<String>("payload_json")
    private let phaseACommentUpdatedAt   = Expression<Int64>("updated_at")

    // ---- workspace_context_refs ----
    private let workspaceContextRefs        = Table("workspace_context_refs")
    private let contextRefWorkspaceId       = Expression<String>("workspace_id")
    private let contextRefRelativePath      = Expression<String>("relative_path")
    private let contextRefUpdatedAt         = Expression<Int64>("updated_at")

    // ---- phase_b_workspace_state ----
    private let phaseBWorkspaceState            = Table("phase_b_workspace_state")
    private let phaseBWorkspaceStateWorkspaceId = Expression<String>("workspace_id")
    private let phaseBWorkspaceStatePayload     = Expression<String>("payload_json")
    private let phaseBWorkspaceStateUpdatedAt   = Expression<Int64>("updated_at")

    // ---- phase_c_workspace_state ----
    private let phaseCWorkspaceState            = Table("phase_c_workspace_state")
    private let phaseCWorkspaceStateWorkspaceId = Expression<String>("workspace_id")
    private let phaseCWorkspaceStatePayload     = Expression<String>("payload_json")
    private let phaseCWorkspaceStateUpdatedAt   = Expression<Int64>("updated_at")

    // ---- chat_summaries ----
    private let chatSummaries              = Table("chat_summaries")
    private let chatSummaryWorktreeId      = Expression<String>("worktree_id")
    private let chatSummaryPayload         = Expression<String>("payload_json")
    private let chatSummaryUpdatedAt       = Expression<Int64>("updated_at")

    // MARK: Init

    private init() {
        let dbPath = Database.databasePath()
        do {
            db = try Connection(dbPath)
            try applyMigrations()
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

    private func applyMigrations() throws {
        try SQLiteMigrationRunner.apply([
            SQLiteMigration(version: 1, label: "Core schema") { [self] db in
                try self.createCoreTables(on: db)
            },
            SQLiteMigration(version: 2, label: "Phase A integration state") { [self] db in
                try self.createPhaseAIntegrationTables(on: db)
            },
            SQLiteMigration(version: 3, label: "Plan mode approval state") { [self] db in
                try self.createPlanStateTable(on: db)
            },
            SQLiteMigration(version: 4, label: "Pending questions") { [self] db in
                try self.createPendingQuestionTable(on: db)
            },
            SQLiteMigration(version: 5, label: "Workspace context references") { [self] db in
                try self.createWorkspaceContextTables(on: db)
            },
            SQLiteMigration(version: 6, label: "Phase B integration state") { [self] db in
                try self.createPhaseBIntegrationTables(on: db)
            },
            SQLiteMigration(version: 7, label: "Chat summaries") { [self] db in
                try self.createChatSummaryTable(on: db)
            },
            SQLiteMigration(version: 8, label: "Phase C integration state") { [self] db in
                try self.createPhaseCIntegrationTables(on: db)
            }
        ], on: db)
    }

    private func createCoreTables(on db: Connection) throws {
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
            t.column(wtStatus,       defaultValue: WorktreeStatus.backlog.rawValue)
            t.column(wtSelectedModel)
            t.column(wtCreatedAt)
            t.foreignKey(wtRepoId, references: repos, repoId, delete: .cascade)
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

        // review_file_state
        try db.run(reviewFileState.create(ifNotExists: true) { t in
            t.column(rfsWorkspaceId)
            t.column(rfsFilePath)
            t.column(rfsViewed)
            t.column(rfsUpdatedAt)
            t.primaryKey(rfsWorkspaceId, rfsFilePath)
        })

        try runLegacyStatusMigration()
    }

    /// Lightweight data migration for legacy workspace statuses.
    private func runLegacyStatusMigration() throws {
        let legacyMappings: [(String, WorktreeStatus)] = [
            ("idle", .backlog),
            ("running", .inProgress),
            ("completed", .done),
            ("error", .inReview)
        ]

        for (legacy, mapped) in legacyMappings {
            let rows = worktrees.filter(wtStatus == legacy)
            try db.run(rows.update(wtStatus <- mapped.rawValue))
        }

        let validStatuses = WorktreeStatus.allCases.map { "'\($0.rawValue)'" }.joined(separator: ",")
        try db.run("UPDATE worktrees SET status = ? WHERE status NOT IN (\(validStatuses))", WorktreeStatus.backlog.rawValue)
    }

    private func createPendingQuestionTable(on db: Connection) throws {
        try db.run(pendingQuestions.create(ifNotExists: true) { t in
            t.column(pendingQuestionId, primaryKey: true)
            t.column(pendingQuestionWTID)
            t.column(pendingQuestionPrompt)
            t.column(pendingQuestionAt)
            t.foreignKey(pendingQuestionWTID, references: worktrees, wtId, delete: .cascade)
            t.unique(pendingQuestionWTID)
        })
    }

    /// Shared persistence envelopes for A2/A3/A4/A5 integration.
    private func createPhaseAIntegrationTables(on db: Connection) throws {
        try db.run(phaseAChecks.create(ifNotExists: true) { t in
            t.column(phaseACheckId, primaryKey: true)
            t.column(phaseACheckWorktreeId)
            t.column(phaseACheckProvider)
            t.column(phaseACheckExternalId)
            t.column(phaseACheckPayload)
            t.column(phaseACheckUpdatedAt)
            t.foreignKey(phaseACheckWorktreeId, references: worktrees, wtId, delete: .cascade)
            t.unique(phaseACheckWorktreeId, phaseACheckProvider, phaseACheckExternalId)
        })

        try db.run(phaseAReviewStates.create(ifNotExists: true) { t in
            t.column(phaseAReviewStateId, primaryKey: true)
            t.column(phaseAReviewStateWorktreeId)
            t.column(phaseAReviewStatePayload)
            t.column(phaseAReviewStateUpdatedAt)
            t.foreignKey(phaseAReviewStateWorktreeId, references: worktrees, wtId, delete: .cascade)
            t.unique(phaseAReviewStateWorktreeId)
        })

        try db.run(phaseAComments.create(ifNotExists: true) { t in
            t.column(phaseACommentId, primaryKey: true)
            t.column(phaseACommentWorktreeId)
            t.column(phaseACommentProvider)
            t.column(phaseACommentExternalId)
            t.column(phaseACommentPayload)
            t.column(phaseACommentUpdatedAt)
            t.foreignKey(phaseACommentWorktreeId, references: worktrees, wtId, delete: .cascade)
            t.unique(phaseACommentWorktreeId, phaseACommentProvider, phaseACommentExternalId)
        })
    }

    private func createPlanStateTable(on db: Connection) throws {
        try db.run(planStates.create(ifNotExists: true) { t in
            t.column(planWorktreeId, primaryKey: true)
            t.column(planStatus, defaultValue: PlanApprovalStatus.none.rawValue)
            t.column(planText, defaultValue: "")
            t.column(planFeedback)
            t.column(planUpdatedAt)
            t.foreignKey(planWorktreeId, references: worktrees, wtId, delete: .cascade)
        })
    }

    private func createWorkspaceContextTables(on db: Connection) throws {
        try db.run(workspaceContextRefs.create(ifNotExists: true) { t in
            t.column(contextRefWorkspaceId)
            t.column(contextRefRelativePath)
            t.column(contextRefUpdatedAt)
            t.primaryKey(contextRefWorkspaceId, contextRefRelativePath)
            t.foreignKey(contextRefWorkspaceId, references: worktrees, wtId, delete: .cascade)
        })
    }

    private func createPhaseBIntegrationTables(on db: Connection) throws {
        try db.run(phaseBWorkspaceState.create(ifNotExists: true) { t in
            t.column(phaseBWorkspaceStateWorkspaceId, primaryKey: true)
            t.column(phaseBWorkspaceStatePayload)
            t.column(phaseBWorkspaceStateUpdatedAt)
            t.foreignKey(phaseBWorkspaceStateWorkspaceId, references: worktrees, wtId, delete: .cascade)
        })
    }

    private func createPhaseCIntegrationTables(on db: Connection) throws {
        try db.run(phaseCWorkspaceState.create(ifNotExists: true) { t in
            t.column(phaseCWorkspaceStateWorkspaceId, primaryKey: true)
            t.column(phaseCWorkspaceStatePayload, defaultValue: "{}")
            t.column(phaseCWorkspaceStateUpdatedAt, defaultValue: 0)
            t.foreignKey(phaseCWorkspaceStateWorkspaceId, references: worktrees, wtId, delete: .cascade)
        })

        // Backward-compat for earlier experimental schemas.
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "updated_at",
            definitionSQL: "updated_at INTEGER NOT NULL DEFAULT 0",
            on: db
        )
    }

    private func createChatSummaryTable(on db: Connection) throws {
        try db.run(chatSummaries.create(ifNotExists: true) { t in
            t.column(chatSummaryWorktreeId, primaryKey: true)
            t.column(chatSummaryPayload, defaultValue: "{}")
            t.column(chatSummaryUpdatedAt, defaultValue: 0)
            t.foreignKey(chatSummaryWorktreeId, references: worktrees, wtId, delete: .cascade)
        })

        // Backward-compat for earlier experimental schemas.
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "chat_summaries",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "chat_summaries",
            column: "updated_at",
            definitionSQL: "updated_at INTEGER NOT NULL DEFAULT 0",
            on: db
        )
    }
}

// MARK: - Phase B Workspace State

extension Database {

    func upsertPhaseBWorkspaceState(_ state: PhaseBWorkspaceState) throws {
        let encoder = JSONEncoder()
        let payload = try String(decoding: encoder.encode(state), as: UTF8.self)
        let now = Int64(Date().timeIntervalSince1970)

        let row = phaseBWorkspaceState.filter(phaseBWorkspaceStateWorkspaceId == state.workspaceId.uuidString)
        if try db.pluck(row) != nil {
            try db.run(row.update(
                phaseBWorkspaceStatePayload <- payload,
                phaseBWorkspaceStateUpdatedAt <- now
            ))
        } else {
            try db.run(phaseBWorkspaceState.insert(
                phaseBWorkspaceStateWorkspaceId <- state.workspaceId.uuidString,
                phaseBWorkspaceStatePayload <- payload,
                phaseBWorkspaceStateUpdatedAt <- now
            ))
        }
    }

    func fetchPhaseBWorkspaceState(workspaceId: UUID) throws -> PhaseBWorkspaceState? {
        let row = phaseBWorkspaceState.filter(phaseBWorkspaceStateWorkspaceId == workspaceId.uuidString)
        guard let result = try db.pluck(row) else { return nil }
        let payload = result[phaseBWorkspaceStatePayload]
        return try JSONDecoder().decode(PhaseBWorkspaceState.self, from: Data(payload.utf8))
    }
}

// MARK: - Phase C Workspace State

extension Database {

    func upsertPhaseCWorkspaceState(_ state: PhaseCWorkspaceState) throws {
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "updated_at",
            definitionSQL: "updated_at INTEGER NOT NULL DEFAULT 0",
            on: db
        )

        let encoder = JSONEncoder()
        let payload = try String(decoding: encoder.encode(state), as: UTF8.self)
        let now = Int64(Date().timeIntervalSince1970)

        let row = phaseCWorkspaceState.filter(phaseCWorkspaceStateWorkspaceId == state.workspaceId.uuidString)
        if try db.pluck(row) != nil {
            try db.run(row.update(
                phaseCWorkspaceStatePayload <- payload,
                phaseCWorkspaceStateUpdatedAt <- now
            ))
        } else {
            try db.run(phaseCWorkspaceState.insert(
                phaseCWorkspaceStateWorkspaceId <- state.workspaceId.uuidString,
                phaseCWorkspaceStatePayload <- payload,
                phaseCWorkspaceStateUpdatedAt <- now
            ))
        }
    }

    func fetchPhaseCWorkspaceState(workspaceId: UUID) throws -> PhaseCWorkspaceState? {
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "updated_at",
            definitionSQL: "updated_at INTEGER NOT NULL DEFAULT 0",
            on: db
        )

        let row = phaseCWorkspaceState.filter(phaseCWorkspaceStateWorkspaceId == workspaceId.uuidString)
        guard let result = try db.pluck(row) else { return nil }
        let payload = result[phaseCWorkspaceStatePayload]
        return try JSONDecoder().decode(PhaseCWorkspaceState.self, from: Data(payload.utf8))
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
            status:        WorktreeStatus.fromDatabaseValue(row[wtStatus]),
            selectedModel: row[wtSelectedModel],
            createdAt:     Date(timeIntervalSince1970: Double(row[wtCreatedAt]))
        )
    }
}

// MARK: - Workspace Context References

extension Database {

    func fetchContextRefs(worktreeId: UUID) throws -> [ContextFileReference] {
        let query = workspaceContextRefs
            .filter(contextRefWorkspaceId == worktreeId.uuidString)
            .order(contextRefRelativePath.asc)

        return try db.prepare(query).map { row in
            ContextFileReference(
                relativePath: row[contextRefRelativePath],
                updatedAt: Date(timeIntervalSince1970: Double(row[contextRefUpdatedAt]))
            )
        }
    }

    func upsertContextRef(worktreeId: UUID, relativePath: String) throws {
        let now = Int64(Date().timeIntervalSince1970)
        let row = workspaceContextRefs.filter(
            contextRefWorkspaceId == worktreeId.uuidString &&
            contextRefRelativePath == relativePath
        )

        if try db.pluck(row) != nil {
            try db.run(row.update(contextRefUpdatedAt <- now))
        } else {
            try db.run(workspaceContextRefs.insert(
                contextRefWorkspaceId <- worktreeId.uuidString,
                contextRefRelativePath <- relativePath,
                contextRefUpdatedAt <- now
            ))
        }
    }

    func deleteContextRef(worktreeId: UUID, relativePath: String) throws {
        let row = workspaceContextRefs.filter(
            contextRefWorkspaceId == worktreeId.uuidString &&
            contextRefRelativePath == relativePath
        )
        try db.run(row.delete())
    }

    func replaceContextRefs(worktreeId: UUID, relativePaths: Set<String>) throws {
        let existing = try Set(fetchContextRefs(worktreeId: worktreeId).map(\.relativePath))

        for path in existing.subtracting(relativePaths) {
            try deleteContextRef(worktreeId: worktreeId, relativePath: path)
        }
        for path in relativePaths {
            try upsertContextRef(worktreeId: worktreeId, relativePath: path)
        }
    }
}

// MARK: - Review File State

extension Database {

    func fetchViewedFiles(workspaceId: String) throws -> Set<String> {
        let query = reviewFileState
            .filter(rfsWorkspaceId == workspaceId && rfsViewed == true)
            .select(rfsFilePath)

        let rows = try db.prepare(query)
        return Set(rows.map { $0[rfsFilePath] })
    }

    func setFileViewed(workspaceId: String, filePath: String, viewed: Bool) throws {
        let now = Int64(Date().timeIntervalSince1970)
        let row = reviewFileState.filter(
            rfsWorkspaceId == workspaceId && rfsFilePath == filePath
        )

        if viewed {
            if try db.pluck(row) != nil {
                try db.run(row.update(
                    rfsViewed <- true,
                    rfsUpdatedAt <- now
                ))
            } else {
                try db.run(reviewFileState.insert(
                    rfsWorkspaceId <- workspaceId,
                    rfsFilePath <- filePath,
                    rfsViewed <- true,
                    rfsUpdatedAt <- now
                ))
            }
        } else {
            try db.run(row.delete())
        }
    }

    func clearViewedFiles(workspaceId: String, keeping paths: Set<String>) throws {
        let existing = try fetchViewedFiles(workspaceId: workspaceId)
        let stale = existing.subtracting(paths)
        for path in stale {
            try setFileViewed(workspaceId: workspaceId, filePath: path, viewed: false)
        }
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

// MARK: - Plan Mode State CRUD

extension Database {

    func fetchPlanState(forWorktree worktreeId: UUID) throws -> PlanState? {
        let query = planStates.filter(planWorktreeId == worktreeId.uuidString)
        return try db.pluck(query).map { row in
            PlanState(
                worktreeId: UUID(uuidString: row[planWorktreeId])!,
                status: PlanApprovalStatus(rawValue: row[planStatus]) ?? .none,
                planText: row[planText],
                feedback: row[planFeedback],
                updatedAt: Date(timeIntervalSince1970: Double(row[planUpdatedAt]))
            )
        }
    }

    func upsertPlanState(_ state: PlanState) throws {
        let now = Int64(state.updatedAt.timeIntervalSince1970)
        let row = planStates.filter(planWorktreeId == state.worktreeId.uuidString)

        if try db.pluck(row) != nil {
            try db.run(row.update(
                planStatus <- state.status.rawValue,
                planText <- state.planText,
                planFeedback <- state.feedback,
                planUpdatedAt <- now
            ))
        } else {
            try db.run(planStates.insert(
                planWorktreeId <- state.worktreeId.uuidString,
                planStatus <- state.status.rawValue,
                planText <- state.planText,
                planFeedback <- state.feedback,
                planUpdatedAt <- now
            ))
        }
    }
}

// MARK: - Pending Question CRUD

extension Database {

    func fetchPendingQuestion(forWorktree worktreeId: UUID) throws -> PendingQuestion? {
        let query = pendingQuestions.filter(pendingQuestionWTID == worktreeId.uuidString)
        return try db.pluck(query).map { row in
            PendingQuestion(
                id: UUID(uuidString: row[pendingQuestionId])!,
                worktreeId: UUID(uuidString: row[pendingQuestionWTID])!,
                prompt: row[pendingQuestionPrompt],
                createdAt: Date(timeIntervalSince1970: Double(row[pendingQuestionAt]))
            )
        }
    }

    func upsertPendingQuestion(_ question: PendingQuestion) throws {
        let row = pendingQuestions.filter(pendingQuestionWTID == question.worktreeId.uuidString)
        let now = Int64(question.createdAt.timeIntervalSince1970)

        if try db.pluck(row) != nil {
            try db.run(row.update(
                pendingQuestionId <- question.id.uuidString,
                pendingQuestionPrompt <- question.prompt,
                pendingQuestionAt <- now
            ))
        } else {
            try db.run(pendingQuestions.insert(
                pendingQuestionId <- question.id.uuidString,
                pendingQuestionWTID <- question.worktreeId.uuidString,
                pendingQuestionPrompt <- question.prompt,
                pendingQuestionAt <- now
            ))
        }
    }

    func clearPendingQuestion(forWorktree worktreeId: UUID) throws {
        let row = pendingQuestions.filter(pendingQuestionWTID == worktreeId.uuidString)
        try db.run(row.delete())
    }
}

// MARK: - Chat Summary CRUD

extension Database {
    func upsertChatSummary(_ snapshot: ChatSummarySnapshot) throws {
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "chat_summaries",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "chat_summaries",
            column: "updated_at",
            definitionSQL: "updated_at INTEGER NOT NULL DEFAULT 0",
            on: db
        )

        let now = Int64(Date().timeIntervalSince1970)

        // Compatibility path for legacy summary schema (id/summary/toc_json/message_count/character_count).
        let hasLegacyColumns = try SQLiteMigrationRunner.columnExists("id", in: "chat_summaries", on: db)
            && (try SQLiteMigrationRunner.columnExists("summary", in: "chat_summaries", on: db))

        if hasLegacyColumns {
            let tocJSON = String(decoding: try JSONEncoder().encode(snapshot.tocEntries), as: UTF8.self)
            try db.run("""
                INSERT INTO chat_summaries (id, worktree_id, summary, toc_json, message_count, character_count, updated_at, payload_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(worktree_id) DO UPDATE SET
                    id=excluded.id,
                    summary=excluded.summary,
                    toc_json=excluded.toc_json,
                    message_count=excluded.message_count,
                    character_count=excluded.character_count,
                    updated_at=excluded.updated_at,
                    payload_json=excluded.payload_json
                """,
                snapshot.id.uuidString,
                snapshot.worktreeId.uuidString,
                snapshot.summary,
                tocJSON,
                snapshot.messageCount,
                snapshot.characterCount,
                now,
                String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
            )
            return
        }

        let payload = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        let row = chatSummaries.filter(chatSummaryWorktreeId == snapshot.worktreeId.uuidString)

        if try db.pluck(row) != nil {
            try db.run(row.update(
                chatSummaryPayload <- payload,
                chatSummaryUpdatedAt <- now
            ))
        } else {
            try db.run(chatSummaries.insert(
                chatSummaryWorktreeId <- snapshot.worktreeId.uuidString,
                chatSummaryPayload <- payload,
                chatSummaryUpdatedAt <- now
            ))
        }
    }

    func fetchChatSummary(forWorktree worktreeId: UUID) throws -> ChatSummarySnapshot? {
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "chat_summaries",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )
        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "chat_summaries",
            column: "updated_at",
            definitionSQL: "updated_at INTEGER NOT NULL DEFAULT 0",
            on: db
        )

        let row = chatSummaries.filter(chatSummaryWorktreeId == worktreeId.uuidString)
        guard let result = try db.pluck(row) else { return nil }

        let payload = result[chatSummaryPayload]
        if !payload.isEmpty && payload != "{}" {
            if let decoded = try? JSONDecoder().decode(ChatSummarySnapshot.self, from: Data(payload.utf8)) {
                return decoded
            }
        }

        // Legacy fallback mapping
        let hasLegacyColumns = try SQLiteMigrationRunner.columnExists("summary", in: "chat_summaries", on: db)
            && (try SQLiteMigrationRunner.columnExists("toc_json", in: "chat_summaries", on: db))
        if hasLegacyColumns {
            let legacySummary = Expression<String>("summary")
            let legacyTOC = Expression<String>("toc_json")
            let legacyMessageCount = Expression<Int>("message_count")
            let legacyCharacterCount = Expression<Int>("character_count")
            let legacyUpdatedAt = Expression<Int64>("updated_at")

            let summary = result[legacySummary]
            let tocEntries = (try? JSONDecoder().decode([ChatTOCEntry].self, from: Data(result[legacyTOC].utf8))) ?? []
            return ChatSummarySnapshot(
                worktreeId: worktreeId,
                summary: summary,
                tocEntries: tocEntries,
                messageCount: result[legacyMessageCount],
                characterCount: result[legacyCharacterCount],
                updatedAt: Date(timeIntervalSince1970: Double(result[legacyUpdatedAt]))
            )
        }

        return nil
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
