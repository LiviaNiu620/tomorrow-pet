import Foundation
import XCTest
@testable import TomorrowPet

@MainActor
final class TaskStoreTests: XCTestCase {
    func testTaskHorizonUsesDatesAndManualOverride() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!

        var task = TaskItem(title: "Tomorrow", dueDate: calendar.date(byAdding: .day, value: 1, to: reference))
        XCTAssertEqual(task.effectiveHorizon(referenceDate: reference, calendar: calendar), .immediate)

        task.dueDate = calendar.date(byAdding: .day, value: 10, to: reference)
        XCTAssertEqual(task.effectiveHorizon(referenceDate: reference, calendar: calendar), .shortTerm)

        task.manualHorizon = .longTerm
        XCTAssertEqual(task.effectiveHorizon(referenceDate: reference, calendar: calendar), .longTerm)
    }

    func testDailyPlanningUpdatesExistingTaskWithoutDuplicate() {
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
        let created = store.addTask(title: "提交报销")!
        let suggestion = AISuggestedTask(
            taskID: created.id.uuidString,
            title: created.title,
            area: "财务",
            reason: "即将截止",
            estimatedMinutes: 20,
            priority: "high",
            source: "existing_task"
        )
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!

        store.apply([suggestion], to: tomorrow, markAsFocus: true)

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertTrue(store.tasks[0].isPlanned(on: tomorrow))
        XCTAssertEqual(store.tasks[0].focusDate, tomorrow)
    }

    func testAIResponseOutputTextExtraction() throws {
        let data = Data("""
        {
          "output": [
            {"type": "message", "content": [
              {"type": "output_text", "text": "{\\"summary\\":\\"ok\\"}"}
            ]}
          ]
        }
        """.utf8)

        XCTAssertEqual(try OpenAIPlanningService.extractOutputText(from: data), "{\"summary\":\"ok\"}")
    }
}
