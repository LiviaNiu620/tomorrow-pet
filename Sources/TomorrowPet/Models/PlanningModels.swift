import Foundation

enum CalendarSource: String, Codable, Hashable {
    case apple
    case google

    var title: String {
        switch self {
        case .apple: "Apple Calendar"
        case .google: "Google Calendar"
        }
    }
}

struct CalendarEventSummary: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarTitle: String
    var source: CalendarSource = .apple
}

struct PlanningInputItem: Identifiable, Codable, Hashable {
    var id: String
    var text: String
}

struct AISuggestedTask: Identifiable, Codable, Hashable {
    var id = UUID()
    var taskID: String?
    var inputItemID: String? = nil
    var title: String
    var area: String
    var reason: String
    var estimatedMinutes: Int
    var priority: String
    var source: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case inputItemID = "input_item_id"
        case title
        case area
        case reason
        case estimatedMinutes = "estimated_minutes"
        case priority
        case source
    }
}

struct AIPlanSuggestion: Codable, Hashable {
    var summary: String
    var topThree: [AISuggestedTask]
    var additionalTasks: [AISuggestedTask]
    var workloadAssessment: String
    var notes: String

    enum CodingKeys: String, CodingKey {
        case summary
        case topThree = "top_three"
        case additionalTasks = "additional_tasks"
        case workloadAssessment = "workload_assessment"
        case notes
    }
}

struct StoredAIPlan: Codable, Hashable {
    var date: Date
    var generatedAt: Date
    var plan: AIPlanSuggestion
}

struct WeeklyPlan: Codable, Hashable {
    var weekStart: Date
    var goals: [String]
    var notes: String
    var selectedTaskIDs: [UUID]
    var updatedAt: Date
}

struct AITaskBreakdown: Codable, Hashable {
    var summary: String
    var steps: [AIBreakdownStep]
    var risks: [String]
}

struct AIBreakdownStep: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var notes: String
    var area: String
    var estimatedMinutes: Int
    var priority: String
    var plannedDate: Date?
    var dueDate: Date?
    var completionCriteria: String
    var dependsOnStepIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id = "step_id"
        case title
        case notes
        case area
        case estimatedMinutes = "estimated_minutes"
        case priority
        case plannedDate = "planned_date"
        case dueDate = "due_date"
        case completionCriteria = "completion_criteria"
        case dependsOnStepIDs = "depends_on_step_ids"
    }
}
