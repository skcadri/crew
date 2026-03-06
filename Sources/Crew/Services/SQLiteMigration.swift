import Foundation
import SQLite

struct SQLiteColumnInfo {
    let cid: Int
    let name: String
    let type: String
    let notNull: Bool
    let defaultValue: String?
    let isPrimaryKey: Bool
}

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

    static func tableExists(_ table: String, on db: Connection) throws -> Bool {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(escapedTable)'"
        let value = try db.scalar(sql)
        if let intValue = value as? Int64 { return intValue > 0 }
        if let intValue = value as? Int { return intValue > 0 }
        return false
    }

    static func columnInfo(for table: String, on db: Connection) throws -> [SQLiteColumnInfo] {
        let pragmaSQL = "PRAGMA table_info(\(escapedIdentifier(table)))"
        return try db.prepare(pragmaSQL).map { row in
            SQLiteColumnInfo(
                cid: Int(row[0] as? Int64 ?? 0),
                name: row[1] as? String ?? "",
                type: row[2] as? String ?? "",
                notNull: (row[3] as? Int64 ?? 0) == 1,
                defaultValue: row[4] as? String,
                isPrimaryKey: (row[5] as? Int64 ?? 0) == 1
            )
        }
    }

    static func columnExists(_ column: String, in table: String, on db: Connection) throws -> Bool {
        try columnInfo(for: table, on: db).contains { $0.name == column }
    }

    static func addColumnIfMissing(
        table: String,
        column: String,
        definitionSQL: String,
        on db: Connection
    ) throws {
        guard try tableExists(table, on: db) else { return }
        guard try !columnExists(column, in: table, on: db) else { return }
        let sql = "ALTER TABLE \(escapedIdentifier(table)) ADD COLUMN \(definitionSQL)"
        try db.run(sql)
    }

    private static func escapedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
