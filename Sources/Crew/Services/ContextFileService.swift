import Foundation

struct ContextFileReference: Identifiable, Hashable, Codable {
    let id: String
    let relativePath: String
    let updatedAt: Date

    init(relativePath: String, updatedAt: Date = Date()) {
        self.id = relativePath
        self.relativePath = relativePath
        self.updatedAt = updatedAt
    }
}

enum ContextFileServiceError: Error, LocalizedError {
    case invalidWorkspacePath
    case fileNotFound(String)
    case invalidRelativePath(String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspacePath:
            return "Invalid workspace path"
        case .fileNotFound(let path):
            return "Context file not found: \(path)"
        case .invalidRelativePath(let path):
            return "Invalid context file path: \(path)"
        }
    }
}

final class ContextFileService {
    static let shared = ContextFileService()

    private let fm = FileManager.default
    private init() {}

    func ensureContextDirectory(workspacePath: String) throws -> URL {
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let contextURL = workspaceURL.appendingPathComponent(".context", isDirectory: true)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: contextURL.path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw ContextFileServiceError.invalidWorkspacePath
            }
            return contextURL
        }

        try fm.createDirectory(at: contextURL, withIntermediateDirectories: true)
        return contextURL
    }

    func listFiles(workspacePath: String) throws -> [String] {
        let contextURL = try ensureContextDirectory(workspacePath: workspacePath)
        let urls = try fm.contentsOfDirectory(at: contextURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

        return urls
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            }
            .map { $0.lastPathComponent }
            .sorted()
    }

    func readFile(workspacePath: String, relativePath: String) throws -> String {
        let fileURL = try resolveContextFileURL(workspacePath: workspacePath, relativePath: relativePath)
        guard fm.fileExists(atPath: fileURL.path) else {
            throw ContextFileServiceError.fileNotFound(relativePath)
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func writeFile(workspacePath: String, relativePath: String, content: String) throws {
        let fileURL = try resolveContextFileURL(workspacePath: workspacePath, relativePath: relativePath)
        let parent = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func resolveContextFileURL(workspacePath: String, relativePath: String) throws -> URL {
        let contextURL = try ensureContextDirectory(workspacePath: workspacePath)

        guard !relativePath.isEmpty,
              !relativePath.contains(".."),
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("~") else {
            throw ContextFileServiceError.invalidRelativePath(relativePath)
        }

        let target = contextURL.appendingPathComponent(relativePath)
        let standardizedTarget = target.standardizedFileURL.path
        let standardizedContext = contextURL.standardizedFileURL.path + "/"

        guard standardizedTarget.hasPrefix(standardizedContext) else {
            throw ContextFileServiceError.invalidRelativePath(relativePath)
        }

        return target
    }
}
