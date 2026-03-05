import XCTest
@testable import Crew

final class AgentTests: XCTestCase {

    // MARK: - AgentFactory tests

    func testFactoryCreatesClaudeCodeAgent() {
        let agent = AgentFactory.makeAgent(.claudeCode)
        XCTAssertEqual(agent.type, .claudeCode)
        XCTAssertFalse(agent.isRunning)
    }

    func testFactoryCreatesStubForCodex() {
        let agent = AgentFactory.makeAgent(.codex)
        XCTAssertEqual(agent.type, .codex)
    }

    func testFactoryCreatesStubForLMStudio() {
        let agent = AgentFactory.makeAgent(.lmStudio)
        XCTAssertEqual(agent.type, .lmStudio)
    }

    // MARK: - JSON parser tests

    func testParseTextLine() {
        let json = #"{"type":"text","content":"Hello, world!"}"#
        let event = ClaudeCodeAgent.parseJSONLine(json)
        if case .text(let msg) = event {
            XCTAssertEqual(msg, "Hello, world!")
        } else {
            XCTFail("Expected .text, got \(event)")
        }
    }

    func testParseToolUseLine() {
        let json = #"{"type":"tool_use","name":"bash","input":{"command":"ls"}}"#
        let event = ClaudeCodeAgent.parseJSONLine(json)
        if case .toolUse(let summary) = event {
            XCTAssertTrue(summary.hasPrefix("bash:"))
        } else {
            XCTFail("Expected .toolUse, got \(event)")
        }
    }

    func testParseErrorLine() {
        let json = #"{"type":"error","message":"Something went wrong"}"#
        let event = ClaudeCodeAgent.parseJSONLine(json)
        if case .error(let msg) = event {
            XCTAssertEqual(msg, "Something went wrong")
        } else {
            XCTFail("Expected .error, got \(event)")
        }
    }

    func testParseResultSuccess() {
        let json = #"{"type":"result","subtype":"success"}"#
        let event = ClaudeCodeAgent.parseJSONLine(json)
        if case .done = event {
            // Pass
        } else {
            XCTFail("Expected .done, got \(event)")
        }
    }

    func testParseUnknownFallsBackToText() {
        let raw = "plain text line (no JSON)"
        let event = ClaudeCodeAgent.parseJSONLine(raw)
        if case .text(let msg) = event {
            XCTAssertEqual(msg, raw)
        } else {
            XCTFail("Expected .text fallback, got \(event)")
        }
    }

    // MARK: - AgentManager tests

    func testAgentManagerNoActiveAgent() async {
        let manager = AgentManager()
        let id = UUID()
        let isRunning = await manager.isRunning(worktreeID: id)
        XCTAssertFalse(isRunning)
        let agentRef = await manager.agent(for: id)
        XCTAssertNil(agentRef)
    }

    func testAgentManagerCancelNonexistentIsNoop() async {
        let manager = AgentManager()
        // Should not throw or crash.
        await manager.cancel(worktreeID: UUID())
    }

    func testAgentManagerSendWithoutSpawnThrows() async {
        let manager = AgentManager()
        do {
            _ = try await manager.send(worktreeID: UUID(), message: "hi")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is AgentManagerError)
        }
    }

    // MARK: - AgentType tests

    func testAgentTypeRawValues() {
        XCTAssertEqual(AgentType.claudeCode.rawValue, "claude_code")
        XCTAssertEqual(AgentType.codex.rawValue, "codex")
        XCTAssertEqual(AgentType.lmStudio.rawValue, "lm_studio")
    }

    func testAgentTypeDisplayNames() {
        XCTAssertEqual(AgentType.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(AgentType.codex.displayName, "Codex")
        XCTAssertEqual(AgentType.lmStudio.displayName, "LM Studio")
    }
}
