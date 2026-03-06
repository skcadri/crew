import Foundation
import SQLite

// MARK: - SQLite Migration Helper

struct SQLiteMigration {
    let version: Int
    let label: String
    let apply: (Connection) throws -> Void
}

enum SQLiteMigrationError: Error, LocalizedError {
    case duplicateVersions([Int])

    var errorDescription: String? {
        switch self {
        case .duplicateVersions(let versions):
            return "Duplicate migration versions: \(versions.map(String.init).joined(separator: ", "))"
        }
    }
}

struct SQLiteMigrationRunner {

    static func apply(_ migrations: [SQLiteMigration], on db: Connection) throws {
        let duplicates = Dictionary(grouping: migrations.map(\.version), by: { $0 })
            .filter { $1.count > 1 }
            .map(\.key)
            .sorted()
        if !duplicates.isEmpty {
            throw SQLiteMigrationError.duplicateVersions(duplicates)
        }

        let ordered = migrations.sorted { $0.version < $1.version }
        let currentVersion = try userVersion(on: db)

        guard let targetVersion = ordered.last?.version, targetVersion > currentVersion else {
            return
        }

        for migration in ordered where migration.version > currentVersion {
            try db.transaction {
                try migration.apply(db)
                try setUserVersion(migration.version, on: db)
            }
        }
    }

    static func userVersion(on db: Connection) throws -> Int {
        let pragma = try db.scalar("PRAGMA user_version")
        if let intValue = pragma as? Int64 {
            return Int(intValue)
        }
        if let intValue = pragma as? Int {
            return intValue
        }
        return 0
    }

    static func setUserVersion(_ version: Int, on db: Connection) throws {
        try db.run("PRAGMA user_version = \(version)")
    }
}
