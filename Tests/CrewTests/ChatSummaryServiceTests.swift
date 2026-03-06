import XCTest
@testable import Crew

final class ChatSummaryServiceTests: XCTestCase {

    func testExtractTOCEntriesFromMarkdownHeadings() {
        let worktreeId = UUID()
        let messages = [
            ChatMessage(worktreeId: worktreeId, role: .assistant, content: "# Plan\n## API\nShip it"),
            ChatMessage(worktreeId: worktreeId, role: .assistant, content: "Section 2: Implementation\nDone")
        ]

        let entries = ChatSummaryService.shared.extractTOCEntries(from: messages)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].title, "Plan")
        XCTAssertEqual(entries[0].level, 1)
        XCTAssertEqual(entries[1].title, "API")
        XCTAssertEqual(entries[2].title, "Implementation")
    }

    func testShouldCreateSnapshotForLongChat() {
        let worktreeId = UUID()
        let messages = (0..<12).map { idx in
            ChatMessage(worktreeId: worktreeId, role: idx % 2 == 0 ? .user : .assistant, content: "Message \(idx)")
        }

        XCTAssertTrue(ChatSummaryService.shared.shouldCreateSnapshot(messages: messages, previous: nil))
    }
}
