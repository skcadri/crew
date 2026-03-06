import XCTest
import SQLite
@testable import Crew

final class PhaseCIntegrationTests: XCTestCase {

    func testPhaseCWorkspaceStateCodableRoundTrip() throws {
        let original = PhaseCWorkspaceState(
            workspaceId: UUID(),
            commandScope: .global,
            isCommandPaletteVisible: true,
            historyFilter: .all,
            editorFocusRegion: .find,
            shortcutOverlayState: .visible,
            prefersReducedPolling: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhaseCWorkspaceState.self, from: encoded)

        XCTAssertEqual(decoded.workspaceId, original.workspaceId)
        XCTAssertEqual(decoded.commandScope, .global)
        XCTAssertTrue(decoded.isCommandPaletteVisible)
        XCTAssertEqual(decoded.historyFilter, .all)
        XCTAssertEqual(decoded.editorFocusRegion, .find)
        XCTAssertEqual(decoded.shortcutOverlayState, .visible)
        XCTAssertTrue(decoded.prefersReducedPolling)
    }

    func testMigrationRunnerAppliesPhaseCMigrationAndSetsVersion() throws {
        let db = try Connection(.inMemory)

        let migrations = [
            SQLiteMigration(version: 1, label: "core") { db in
                try db.run("CREATE TABLE worktrees (id TEXT PRIMARY KEY)")
            },
            SQLiteMigration(version: 8, label: "phase-c envelope") { db in
                try db.run("""
                CREATE TABLE phase_c_workspace_state (
                    workspace_id TEXT PRIMARY KEY,
                    payload_json TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    FOREIGN KEY(workspace_id) REFERENCES worktrees(id) ON DELETE CASCADE
                )
                """)
            }
        ]

        try SQLiteMigrationRunner.apply(migrations, on: db)

        XCTAssertEqual(try SQLiteMigrationRunner.userVersion(on: db), 8)
        XCTAssertTrue(try SQLiteMigrationRunner.tableExists("phase_c_workspace_state", on: db))
    }

    func testAddColumnIfMissingIsIdempotentForPhaseCTable() throws {
        let db = try Connection(.inMemory)
        try db.run("CREATE TABLE phase_c_workspace_state (workspace_id TEXT PRIMARY KEY)")

        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )

        try SQLiteMigrationRunner.addColumnIfMissing(
            table: "phase_c_workspace_state",
            column: "payload_json",
            definitionSQL: "payload_json TEXT NOT NULL DEFAULT '{}'",
            on: db
        )

        let columns = try SQLiteMigrationRunner.columnInfo(for: "phase_c_workspace_state", on: db)
            .filter { $0.name == "payload_json" }

        XCTAssertEqual(columns.count, 1)
    }
}
