import XCTest
@testable import Crew

final class DatabaseTests: XCTestCase {

    var db: Database { .shared }

    // MARK: - Repository Tests

    func testInsertAndFetchRepository() throws {
        let repo = Repository(name: "test-repo", url: "https://github.com/example/test", localPath: "/tmp/test-repo")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) }

        let fetched = try db.fetchRepository(id: repo.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "test-repo")
        XCTAssertEqual(fetched?.url, "https://github.com/example/test")
        XCTAssertEqual(fetched?.localPath, "/tmp/test-repo")
    }

    func testUpdateRepository() throws {
        var repo = Repository(name: "original", url: "https://github.com/example/original", localPath: "/tmp/original")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) }

        repo.name = "updated"
        try db.updateRepository(repo)

        let fetched = try db.fetchRepository(id: repo.id)
        XCTAssertEqual(fetched?.name, "updated")
    }

    func testDeleteRepository() throws {
        let repo = Repository(name: "to-delete", url: "https://github.com/example/delete", localPath: "/tmp/delete")
        try db.insertRepository(repo)
        try db.deleteRepository(id: repo.id)

        let fetched = try db.fetchRepository(id: repo.id)
        XCTAssertNil(fetched)
    }

    // MARK: - Worktree Tests

    func testInsertAndFetchWorktree() throws {
        let repo = Repository(name: "wt-repo", url: "https://github.com/example/wt", localPath: "/tmp/wt-repo")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) } // cascades to worktrees

        let wt = Worktree(repoId: repo.id, branch: "feature/test", path: "/tmp/worktree-1")
        try db.insertWorktree(wt)

        let fetched = try db.fetchWorktree(id: wt.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.branch, "feature/test")
        XCTAssertEqual(fetched?.status, .backlog)
    }

    func testUpdateWorktreeStatus() throws {
        let repo = Repository(name: "status-repo", url: "https://github.com/example/status", localPath: "/tmp/status-repo")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) }

        let wt = Worktree(repoId: repo.id, branch: "main", path: "/tmp/status-wt")
        try db.insertWorktree(wt)

        try db.updateWorktreeStatus(id: wt.id, status: .inProgress)
        let fetched = try db.fetchWorktree(id: wt.id)
        XCTAssertEqual(fetched?.status, .inProgress)
    }

    // MARK: - ChatMessage Tests

    func testInsertAndFetchMessages() throws {
        let repo = Repository(name: "msg-repo", url: "https://github.com/example/msg", localPath: "/tmp/msg-repo")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) }

        let wt = Worktree(repoId: repo.id, branch: "chat-branch", path: "/tmp/chat-wt")
        try db.insertWorktree(wt)

        let msg1 = ChatMessage(worktreeId: wt.id, role: .user, content: "Hello!")
        let msg2 = ChatMessage(worktreeId: wt.id, role: .assistant, content: "Hi there!")
        try db.insertMessage(msg1)
        try db.insertMessage(msg2)

        let messages = try db.fetchMessages(forWorktree: wt.id)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testDeleteMessagesForWorktree() throws {
        let repo = Repository(name: "del-msg-repo", url: "https://github.com/example/delmsg", localPath: "/tmp/del-msg-repo")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) }

        let wt = Worktree(repoId: repo.id, branch: "del-branch", path: "/tmp/del-wt")
        try db.insertWorktree(wt)

        try db.insertMessage(ChatMessage(worktreeId: wt.id, role: .user, content: "msg1"))
        try db.insertMessage(ChatMessage(worktreeId: wt.id, role: .assistant, content: "msg2"))

        try db.deleteMessages(forWorktree: wt.id)
        let remaining = try db.fetchMessages(forWorktree: wt.id)
        XCTAssertEqual(remaining.count, 0)
    }

    func testPersistAndFetchChatSummary() throws {
        let repo = Repository(name: "summary-repo", url: "https://github.com/example/summary", localPath: "/tmp/summary-repo")
        try db.insertRepository(repo)
        defer { try? db.deleteRepository(id: repo.id) }

        let wt = Worktree(repoId: repo.id, branch: "summary-branch", path: "/tmp/summary-wt")
        try db.insertWorktree(wt)

        let snapshot = ChatSummarySnapshot(
            worktreeId: wt.id,
            summary: "Long chat summary",
            tocEntries: [ChatTOCEntry(title: "Overview", level: 1, messageId: UUID())],
            messageCount: 20,
            characterCount: 6000
        )

        try db.upsertChatSummary(snapshot)
        let fetched = try db.fetchChatSummary(forWorktree: wt.id)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.summary, "Long chat summary")
        XCTAssertEqual(fetched?.tocEntries.first?.title, "Overview")
        XCTAssertEqual(fetched?.messageCount, 20)
    }

    // MARK: - Review File State Tests

    func testPersistViewedFileStatePerWorkspace() throws {
        let workspaceA = "ws-a"
        let workspaceB = "ws-b"
        let path = "Sources/Crew/File.swift"

        try db.setFileViewed(workspaceId: workspaceA, filePath: path, viewed: true)
        try db.setFileViewed(workspaceId: workspaceB, filePath: path, viewed: false)
        defer {
            try? db.setFileViewed(workspaceId: workspaceA, filePath: path, viewed: false)
            try? db.setFileViewed(workspaceId: workspaceB, filePath: path, viewed: false)
        }

        let aViewed = try db.fetchViewedFiles(workspaceId: workspaceA)
        let bViewed = try db.fetchViewedFiles(workspaceId: workspaceB)

        XCTAssertTrue(aViewed.contains(path))
        XCTAssertFalse(bViewed.contains(path))
    }

    // MARK: - AgentType Tests

    func testAgentTypeDisplayNames() {
        XCTAssertEqual(AgentType.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(AgentType.codex.displayName, "Codex")
        XCTAssertEqual(AgentType.lmStudio.displayName, "LM Studio")
    }

    func testAgentTypeCodable() throws {
        for agentType in AgentType.allCases {
            let encoded = try JSONEncoder().encode(agentType)
            let decoded = try JSONDecoder().decode(AgentType.self, from: encoded)
            XCTAssertEqual(agentType, decoded)
        }
    }
}
