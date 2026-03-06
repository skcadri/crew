import XCTest
import SQLite
@testable import Crew

final class PhaseBIntegrationTests: XCTestCase {

    func testPhaseBWorkspaceStateCodableRoundTrip() throws {
        let original = PhaseBWorkspaceState(
            workspaceId: UUID(),
            selectedTab: .notes,
            stage: .awaitingQuestionAnswer,
            latestPlanStatus: .approvedWithFeedback,
            hasPendingQuestion: true,
            notesPath: ".context/notes.md",
            lastSummaryHeading: "Execution Plan",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhaseBWorkspaceState.self, from: encoded)

        XCTAssertEqual(decoded.workspaceId, original.workspaceId)
        XCTAssertEqual(decoded.selectedTab, .notes)
        XCTAssertEqual(decoded.stage, .awaitingQuestionAnswer)
        XCTAssertEqual(decoded.latestPlanStatus, .approvedWithFeedback)
        XCTAssertTrue(decoded.hasPendingQuestion)
        XCTAssertEqual(decoded.lastSummaryHeading, "Execution Plan")
    }

    func testMigrationRunnerAppliesPhaseBMigrationAndSetsVersion() throws {
        let db = try Connection(.inMemory)

        let migrations = [
            SQLiteMigration(version: 1, label: "core") { db in
                try db.run("CREATE TABLE worktrees (id TEXT PRIMARY KEY)")
            },
            SQLiteMigration(version: 3, label: "phase-b envelope") { db in
                try db.run("""
                CREATE TABLE phase_b_workspace_state (
                    workspace_id TEXT PRIMARY KEY,
                    payload_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    FOREIGN KEY(workspace_id) REFERENCES worktrees(id) ON DELETE CASCADE
                )
                """)
            }
        ]

        try SQLiteMigrationRunner.apply(migrations, on: db)

        XCTAssertEqual(try SQLiteMigrationRunner.userVersion(on: db), 3)
        XCTAssertTrue(try SQLiteMigrationRunner.tableExists("phase_b_workspace_state", on: db))
    }

    func testAddColumnIfMissingIsIdempotent() throws {
        let db = try Connection(.inMemory)
        try db.run("CREATE TABLE phase_b_workspace_state (workspace_id TEXT PRIMARY KEY)")

        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_b_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )

        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_b_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )

        let columns = try SQLiteMigrationRunner.columnInfo(for: "phase_b_workspace_state", on: db)
            .filter { $0.name == "payload_json" }

        XCTAssertEqual(columns.count, 1)
    }
}
