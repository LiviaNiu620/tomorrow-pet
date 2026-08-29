import Foundation

@main
@MainActor
struct TomorrowPetSelfTests {
    static func main() async throws {
        try testHorizonClassification()
        try testResponseExtraction()
        try testPromptSerializationWithMissingOptionalFields()
        try testPlanningUpdatesExistingTask()
        try await testGoogleCredentialValidation()
        try testGoogleDesktopCredentialImport()
        try testPKCEKnownVector()
        try testOAuthCallbackParsing()
        try testGoogleEventDateParsing()
        try testCalendarMergeDeduplicatesSyncedGoogleEvents()
        try testRecurringTaskCreatesOnlyOneNextInstance()
        try testDeleteCanBeUndone()
        try testTrashRestoreAndPermanentDelete()
        try testMultipleUndoSteps()
        try testPromptIncludesCalendarSource()
        try testPromptIncludesWeeklyPlan()
        try testPromptIncludesDailySOP()
        try testDailySOPScheduleVariants()
        try testDailySOPCompletionIsolation()
        try testLegacyTaskDecoding()
        print("TomorrowPet self-tests passed: 20/20")
    }

    private static func testHorizonClassification() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = try require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25)))
        var task = TaskItem(
            title: "Tomorrow",
            dueDate: calendar.date(byAdding: .day, value: 1, to: reference)
        )
        try expect(task.effectiveHorizon(referenceDate: reference, calendar: calendar) == .immediate, "Tomorrow must be immediate")
        task.dueDate = calendar.date(byAdding: .day, value: 10, to: reference)
        try expect(task.effectiveHorizon(referenceDate: reference, calendar: calendar) == .shortTerm, "10 days must be short-term")
        task.manualHorizon = .longTerm
        try expect(task.effectiveHorizon(referenceDate: reference, calendar: calendar) == .longTerm, "Manual horizon must win")
    }

    private static func testResponseExtraction() throws {
        let data = Data("""
        {"output":[{"type":"message","content":[{"type":"output_text","text":"{\\"summary\\":\\"ok\\"}"}]}]}
        """.utf8)
        let text = try OpenAIPlanningService.extractOutputText(from: data)
        try expect(text == "{\"summary\":\"ok\"}", "Responses API output_text extraction failed")
    }

    private static func testPromptSerializationWithMissingOptionalFields() throws {
        let service = OpenAIPlanningService()
        let payload = try service.promptPayload(
            tomorrow: .now,
            tasks: [TaskItem(title: "没有日期和估时的任务")],
            areas: TaskArea.defaults,
            events: []
        )
        try expect(payload.contains("没有日期和估时的任务"), "Prompt serialization must retain task title")
        try expect(payload.contains("null"), "Missing optional task fields must serialize as JSON null")
    }

    @MainActor
    private static func testPlanningUpdatesExistingTask() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TaskStore(fileURL: file, persistsChanges: false)
        let created = try require(store.addTask(title: "提交报销"))
        let suggestion = AISuggestedTask(
            taskID: created.id.uuidString,
            title: created.title,
            area: "财务",
            reason: "即将截止",
            estimatedMinutes: 20,
            priority: "high",
            source: "existing_task"
        )
        let tomorrow = try require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        store.apply([suggestion], to: tomorrow, markAsFocus: true)
        try expect(store.tasks.count == 1, "Existing AI suggestion must not duplicate a task")
        try expect(store.tasks[0].isPlanned(on: tomorrow), "Existing task must be planned for tomorrow")
    }

    private static func testGoogleCredentialValidation() async throws {
        let service = GoogleOAuthService()
        do {
            _ = try await service.authorize(clientID: "", clientSecret: "")
            throw SelfTestError.failed("Empty Google Client ID must be rejected")
        } catch GoogleCalendarError.missingClientID {
            // Expected before any browser or network operation.
        }
        do {
            _ = try await service.authorize(clientID: "desktop-client", clientSecret: "")
            throw SelfTestError.failed("Empty Google Client Secret must be rejected")
        } catch GoogleCalendarError.missingClientSecret {
            // Expected before any browser or network operation.
        }
    }

    private static func testGoogleDesktopCredentialImport() throws {
        let desktop = Data("""
        {
          "installed": {
            "client_id": "desktop-test.apps.googleusercontent.com",
            "project_id": "tomorrow-pet-test",
            "client_secret": "test-secret"
          }
        }
        """.utf8)
        let credentials = try GoogleOAuthService.desktopCredentials(from: desktop)
        try expect(
            credentials.clientID == "desktop-test.apps.googleusercontent.com",
            "Desktop OAuth Client ID import failed"
        )
        try expect(credentials.clientSecret == "test-secret", "Desktop OAuth Client Secret import failed")
        try expect(credentials.projectID == "tomorrow-pet-test", "Desktop OAuth project ID import failed")

        let web = Data("""
        {
          "web": {
            "client_id": "web-test.apps.googleusercontent.com",
            "client_secret": "test-secret"
          }
        }
        """.utf8)
        do {
            _ = try GoogleOAuthService.desktopCredentials(from: web)
            throw SelfTestError.failed("Web OAuth credentials must be rejected")
        } catch GoogleCalendarError.webCredentialFile {
            // Expected: the loopback flow requires a Desktop app client.
        }
    }

    private static func testPKCEKnownVector() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        try expect(GoogleOAuthService.pkceChallenge(for: verifier) == expected, "PKCE S256 known vector failed")
    }

    private static func testOAuthCallbackParsing() throws {
        let callback = try GoogleOAuthService.parseCallback(
            try require(URL(string: "http://127.0.0.1:49152/oauth2callback?code=first&code=second&state=secure"))
        )
        try expect(callback.code == "first", "OAuth callback must safely keep the first duplicate value")
        try expect(callback.state == "secure", "OAuth callback state parsing failed")
    }

    private static func testGoogleEventDateParsing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try require(TimeZone(identifier: "America/Los_Angeles"))
        let allDay = GoogleEvent(
            id: "all-day",
            status: "confirmed",
            summary: "休息",
            start: .init(date: "2026-08-27", dateTime: nil, timeZone: "America/Los_Angeles"),
            end: .init(date: "2026-08-28", dateTime: nil, timeZone: "America/Los_Angeles")
        )
        let dates = try require(GoogleCalendarService.dates(for: allDay, calendar: calendar))
        try expect(dates.allDay, "Google date-only event must be all-day")
        try expect(calendar.component(.day, from: dates.start) == 27, "Google all-day start date parsing failed")

        let timed = GoogleEvent(
            id: "timed",
            status: "confirmed",
            summary: "会议",
            start: .init(date: nil, dateTime: "2026-08-27T09:30:00-07:00", timeZone: nil),
            end: .init(date: nil, dateTime: "2026-08-27T10:00:00-07:00", timeZone: nil)
        )
        try expect(GoogleCalendarService.dates(for: timed, calendar: calendar)?.allDay == false, "Google RFC3339 event parsing failed")
    }

    @MainActor
    private static func testCalendarMergeDeduplicatesSyncedGoogleEvents() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3_600)
        let apple = CalendarEventSummary(
            id: "apple:1",
            title: "Design Review",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarTitle: "工作",
            source: .apple
        )
        let google = CalendarEventSummary(
            id: "google:1",
            title: "  design   review ",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarTitle: "Work · Google",
            source: .google
        )
        let merged = CalendarService.mergeEvents(apple: [apple], google: [google])
        try expect(merged.count == 1, "Apple-synced Google events must be deduplicated")
        try expect(merged[0].source == .apple, "Deduplication must prefer the local Apple event")
    }

    @MainActor
    private static func testRecurringTaskCreatesOnlyOneNextInstance() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try require(TimeZone(identifier: "UTC"))
        let planned = try require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
        let created = try require(store.addTask(title: "每日复盘", plannedDate: planned))
        var recurring = created
        recurring.recurrence = RecurrenceRule(frequency: .daily)
        store.update(recurring)

        store.setCompleted(created.id, completed: true)
        try expect(store.tasks.count == 2, "Completing a recurring task must create the next instance")
        let next = try require(store.tasks.first(where: { $0.id != created.id }))
        let expected = try require(calendar.date(byAdding: .day, value: 1, to: planned))
        try expect(next.plannedDate.map { calendar.isDate($0, inSameDayAs: expected) } == true, "Recurring task next date is wrong")

        store.setCompleted(created.id, completed: true)
        try expect(store.tasks.count == 2, "Completing the same occurrence twice must not duplicate the next instance")
    }

    @MainActor
    private static func testDeleteCanBeUndone() throws {
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
        let created = try require(store.addTask(title: "可恢复任务"))
        store.delete([created.id])
        try expect(store.tasks(for: .trash).map(\.id) == [created.id], "Delete must move the task to trash")
        try expect(store.activeTasks.isEmpty, "Trashed tasks must not remain active")
        try expect(store.undoAction != nil, "Delete must expose an undo action")
        store.undoLastAction()
        try expect(store.tasks.map(\.id) == [created.id], "Undo must restore the deleted task")
        try expect(store.tasks[0].status == .inbox, "Undo must restore the original status")
    }

    private static func testTrashRestoreAndPermanentDelete() throws {
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
        let created = try require(store.addTask(title: "垃圾箱任务"))
        store.delete([created.id])
        let trashed = try require(store.task(id: created.id))
        try expect(trashed.status == .trashed && trashed.trashedFromStatus == .inbox, "Trash must remember the prior status")
        try expect(trashed.deletedAt != nil, "Trash must record deletion time")

        store.restoreFromTrash([created.id])
        try expect(store.task(id: created.id)?.status == .inbox, "Restore must recover the prior status")
        store.delete([created.id])
        store.permanentlyDelete([created.id])
        try expect(store.task(id: created.id) == nil, "Permanent deletion must remove the task")
        try expect(!store.canUndo, "Permanent deletion must discard snapshots that could resurrect the task")
    }

    private static func testMultipleUndoSteps() throws {
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
        let first = try require(store.addTask(title: "第一项"))
        let second = try require(store.addTask(title: "第二项"))
        store.delete([first.id])
        store.delete([second.id])
        try expect(store.count(for: .trash) == 2, "Both tasks must be in trash")
        store.undoLastAction()
        try expect(store.task(id: second.id)?.status == .inbox, "First undo must restore the latest deletion")
        try expect(store.task(id: first.id)?.status == .trashed, "First undo must leave the earlier deletion intact")
        store.undoLastAction()
        try expect(store.task(id: first.id)?.status == .inbox, "Second undo must restore the earlier deletion")
    }

    private static func testPromptIncludesCalendarSource() throws {
        let event = CalendarEventSummary(
            id: "google:event",
            title: "同步会议",
            startDate: .now,
            endDate: .now.addingTimeInterval(1_800),
            isAllDay: false,
            calendarTitle: "工作 · Google",
            source: .google
        )
        let payload = try OpenAIPlanningService().promptPayload(
            tomorrow: .now,
            tasks: [],
            areas: [],
            events: [event]
        )
        try expect(payload.contains("\"source\" : \"google\""), "AI prompt must identify the calendar source")
    }

    private static func testPromptIncludesWeeklyPlan() throws {
        let task = TaskItem(title: "推进 Beta")
        let weekly = WeeklyPlan(
            weekStart: .now,
            goals: ["交付可试用版本", "保持运动"],
            notes: "周五前完成",
            selectedTaskIDs: [task.id],
            updatedAt: .now
        )
        let payload = try OpenAIPlanningService().promptPayload(
            tomorrow: .now,
            tasks: [task],
            areas: [],
            events: [],
            weeklyPlan: weekly
        )
        try expect(payload.contains("交付可试用版本"), "AI prompt must include weekly goals")
        try expect(payload.contains("推进 Beta"), "AI prompt must resolve selected weekly task titles")
        try expect(payload.contains("weekly_plan"), "AI prompt must label weekly context")
    }

    private static func testPromptIncludesDailySOP() throws {
        let items = DailySOPTemplate.planningItems(for: .now)
        let payload = try OpenAIPlanningService().promptPayload(
            tomorrow: .now,
            tasks: [],
            areas: [],
            events: [],
            sopItems: items
        )
        try expect(payload.contains("daily_sop"), "Prompt must label daily SOP context")
        try expect(payload.contains("20:20–22:00"), "Prompt must include fixed evening focus time")
        try expect(payload.contains("个人学习和自己的工作"), "Prompt must include the SOP commitment title")
    }

    private static func testDailySOPScheduleVariants() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try require(TimeZone(identifier: "America/Los_Angeles"))
        let weekday = try require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let lastSunday = try require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30)))

        let weekdayIDs = Set(DailySOPTemplate.sections(for: weekday, calendar: calendar).map(\.id))
        try expect(!weekdayIDs.contains("sunday"), "Weekday SOP must not include Sunday planning")
        try expect(!weekdayIDs.contains("monthly"), "Weekday SOP must not include monthly planning")

        let sundayIDs = Set(DailySOPTemplate.sections(for: lastSunday, calendar: calendar).map(\.id))
        try expect(sundayIDs.contains("sunday"), "Sunday SOP must include weekly planning")
        try expect(sundayIDs.contains("monthly"), "Last Sunday must include monthly planning")
        let sundayItems = DailySOPTemplate.sections(for: lastSunday, calendar: calendar).flatMap(\.items)
        try expect(
            Set(sundayItems.map(\.id)).count == sundayItems.count,
            "SOP item IDs must remain unique when weekly and monthly sections are appended"
        )
        try expect(
            DailySOPTemplate.isLastSundayOfMonth(lastSunday, calendar: calendar),
            "Last-Sunday detection failed"
        )
    }

    @MainActor
    private static func testDailySOPCompletionIsolation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try require(TimeZone(identifier: "UTC"))
        let firstDay = try require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let secondDay = try require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let store = DailySOPStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            persistsChanges: false
        )

        store.setCompleted("wake", completed: true, on: firstDay, calendar: calendar)
        try expect(store.isCompleted("wake", on: firstDay, calendar: calendar), "SOP item must be checked on its date")
        try expect(!store.isCompleted("wake", on: secondDay, calendar: calendar), "SOP completion must not leak into another date")
        store.reset(date: firstDay, calendar: calendar)
        try expect(!store.isCompleted("wake", on: firstDay, calendar: calendar), "SOP reset must clear only that day")
    }

    private static func testLegacyTaskDecoding() throws {
        let encoder = JSONEncoder()
        let current = TaskItem(title: "旧数据")
        let data = try encoder.encode(current)
        var object = try require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "recurrence")
        object.removeValue(forKey: "recurrenceSeriesID")
        object.removeValue(forKey: "trashedFromStatus")
        object.removeValue(forKey: "deletedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: legacyData)
        try expect(decoded.title == "旧数据", "Legacy task data must remain decodable")
        try expect(decoded.deletedAt == nil && decoded.recurrence == nil, "New optional fields must default to nil")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestError.failed(message) }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw SelfTestError.failed("Unexpected nil") }
        return value
    }
}

enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}
