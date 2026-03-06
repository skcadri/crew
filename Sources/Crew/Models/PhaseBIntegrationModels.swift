import Foundation

// MARK: - Shared B1–B5 Workflow Models

enum AgentExecutionStage: String, Codable, CaseIterable {
    case planning
    case awaitingPlanApproval = "awaiting_plan_approval"
    case awaitingQuestionAnswer = "awaiting_question_answer"
    case executing
    case completed
}

enum PlanApprovalStatus: String, Codable, CaseIterable {
    case draft
    case approved
    case approvedWithFeedback = "approved_with_feedback"
    case rejected
}

enum WorkspaceSurfaceTab: String, Codable, CaseIterable, Identifiable {
    case plan
    case questions
    case notes
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .questions: return "Questions"
        case .notes: return "Notes"
        case .summary: return "Summary"
        }
    }
}

struct PlanDraft: Codable, Hashable {
    var id: UUID
    var workspaceId: UUID
    var body: String
    var status: PlanApprovalStatus
    var feedback: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        body: String,
        status: PlanApprovalStatus = .draft,
        feedback: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.body = body
        self.status = status
        self.feedback = feedback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct PendingQuestionPrompt: Codable, Hashable {
    var id: UUID
    var workspaceId: UUID
    var prompt: String
    var suggestedAnswers: [String]
    var isRequired: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        prompt: String,
        suggestedAnswers: [String] = [],
        isRequired: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.prompt = prompt
        self.suggestedAnswers = suggestedAnswers
        self.isRequired = isRequired
        self.createdAt = createdAt
    }
}

struct NotesDocumentState: Codable, Hashable {
    var workspaceId: UUID
    var notesRelativePath: String
    var updatedAt: Date

    init(workspaceId: UUID, notesRelativePath: String = ".context/notes.md", updatedAt: Date = Date()) {
        self.workspaceId = workspaceId
        self.notesRelativePath = notesRelativePath
        self.updatedAt = updatedAt
    }
}

struct SummarySnapshotState: Codable, Hashable {
    var id: UUID
    var workspaceId: UUID
    var heading: String
    var body: String
    var generatedAt: Date

    init(id: UUID = UUID(), workspaceId: UUID, heading: String, body: String, generatedAt: Date = Date()) {
        self.id = id
        self.workspaceId = workspaceId
        self.heading = heading
        self.body = body
        self.generatedAt = generatedAt
    }
}

/// Shared persisted route + workflow state for B1–B5.
struct PhaseBWorkspaceState: Codable, Hashable {
    var workspaceId: UUID
    var selectedTab: WorkspaceSurfaceTab
    var stage: AgentExecutionStage
    var latestPlanStatus: PlanApprovalStatus?
    var hasPendingQuestion: Bool
    var notesPath: String
    var lastSummaryHeading: String?
    var updatedAt: Date

    init(
        workspaceId: UUID,
        selectedTab: WorkspaceSurfaceTab = .plan,
        stage: AgentExecutionStage = .planning,
        latestPlanStatus: PlanApprovalStatus? = nil,
        hasPendingQuestion: Bool = false,
        notesPath: String = ".context/notes.md",
        lastSummaryHeading: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.workspaceId = workspaceId
        self.selectedTab = selectedTab
        self.stage = stage
        self.latestPlanStatus = latestPlanStatus
        self.hasPendingQuestion = hasPendingQuestion
        self.notesPath = notesPath
        self.lastSummaryHeading = lastSummaryHeading
        self.updatedAt = updatedAt
    }
}

// MARK: - Provider Interfaces

protocol PlanStateProviding {
    func fetchLatestPlan(for workspaceId: UUID) throws -> PlanDraft?
}

protocol QuestionsStateProviding {
    func fetchPendingQuestion(for workspaceId: UUID) throws -> PendingQuestionPrompt?
}

protocol NotesStateProviding {
    func fetchNotesState(for workspaceId: UUID) throws -> NotesDocumentState?
}

protocol SummaryStateProviding {
    func fetchLatestSummary(for workspaceId: UUID) throws -> SummarySnapshotState?
}
