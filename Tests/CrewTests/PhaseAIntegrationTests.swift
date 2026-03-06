import XCTest
import SQLite
@testable import Crew

final class PhaseAIntegrationTests: XCTestCase {

    func testReviewModelsRoundTripCodable() throws {
        let snapshot = ReviewStateSnapshot(
            worktreeId: UUID(),
            pullRequestNumber: 42,
            state: .awaitingChecks,
            blockingCheckCount: 2,
            unresolvedThreadCount: 1,
            lastSyncedAt: Date()
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ReviewStateSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.state, .awaitingChecks)
        XCTAssertEqual(decoded.pullRequestNumber, 42)
        XCTAssertEqual(decoded.blockingCheckCount, 2)
    }

    func testSQLiteMigrationRunnerAppliesInOrderAndSetsUserVersion() throws {
        let db = try Connection(.inMemory)
        var applied: [Int] = []

        let migrations = [
            SQLiteMigration(version: 2, label: "second") { _ in applied.append(2) },
            SQLiteMigration(version: 1, label: "first") { _ in applied.append(1) }
        ]

        try SQLiteMigrationRunner.apply(migrations, on: db)

        XCTAssertEqual(applied, [1, 2])
        XCTAssertEqual(try SQLiteMigrationRunner.userVersion(on: db), 2)
    }

    func testSQLiteMigrationRunnerRejectsDuplicateVersions() throws {
        let db = try Connection(.inMemory)

        let migrations = [
            SQLiteMigration(version: 1, label: "a") { _ in },
            SQLiteMigration(version: 1, label: "b") { _ in }
        ]

        XCTAssertThrowsError(try SQLiteMigrationRunner.apply(migrations, on: db))
    }
}
