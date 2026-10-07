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
        try testAdditionalInputParsingAndPrompt()
        try testUserInputCoverageValidation()
        try testUserInputCreatesTaskWithoutDuplicates()
        try testEditedSuggestionUpdatesExistingTask()
        try testDailySOPScheduleVariants()
        try testDailySOPCompletionIsolation()
        try testLegacySOPStateMigration()
        try testSOPConfigurationPersistence()
        try testBreakdownPromptIncludesTaskContext()
        try testBreakdownResponseDecodingAndValidation()
        try testBreakdownCreatesLinkedTasksWithoutDuplicates()
        try testLegacyTaskDecoding()
        try testQuickAddStaysInDestinationAndUndoesOnce()
        try testQuickCaptureParsing()
        try testDayPlannerCapacityAndPlacement()
        try testScheduleAndPostpone()
        try testSOPBlocksAndTimeParsing()
        print("TomorrowPet self-tests passed: 35/35")
    }

    private static func testQuickAddStaysInDestinationAndUndoesOnce() throws {
        let reference = try require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let areaID = TaskArea.defaults[0].id
        let destinations: [SidebarDestination] = [.inbox, .all, .today, .tomorrow, .immediate, .shortTerm, .longTerm, .waiting, .area(areaID)]
        for destination in destinations {
            let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
            let task = try require(store.addTask(title: "  当前视图的新任务  ", areaID: areaID, in: destination, referenceDate: reference))
            try expect(store.tasks(for: destination, referenceDate: reference).contains(where: { $0.id == task.id }), "Quick add must appear in \(destination.title)")
            try expect(task.title == "当前视图的新任务", "Quick add must trim the title")
            try expect(task.areaID == areaID, "Quick add must preserve the selected area")
            store.undoLastAction()
            try expect(store.tasks.isEmpty, "One undo must remove the quick-added task")
            try expect(!store.canUndo, "Quick add must create a single undo entry")
            try expect(store.addTask(title: "  ", areaID: nil, in: destination) == nil, "Empty titles must not create tasks")
        }
    }

    private static func testQuickCaptureParsing() throws {
        let calendar = Calendar(identifier: .gregorian)
        let monday = try require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let areas = ["工作", "学习"]
        var parsed = QuickCaptureParser.parse("明天下午3点 写 CEUS 摘要 #工作 45m !高", areaNames: areas, referenceDate: monday, calendar: calendar)
        try expect(parsed.title == "写 CEUS 摘要", "Title must exclude parsed tokens, got \(parsed.title)")
        try expect(parsed.minute == 15 * 60, "下午3点 must be 15:00")
        try expect(parsed.duration == 45, "45m must be 45 minutes")
        try expect(parsed.areaName == "工作", "#工作 must match the area")
        try expect(parsed.priority == .high, "!高 must be high priority")
        try expect(parsed.date.map { calendar.isDate($0, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: monday)!) } == true, "明天 must be Tuesday")
        parsed = QuickCaptureParser.parse("周四 投递 3 个岗位 1.5h #求职", areaNames: areas, referenceDate: monday, calendar: calendar)
        try expect(parsed.duration == 90, "1.5h must be 90 minutes")
        try expect(parsed.unknownTag == "求职" && parsed.areaName == nil, "Unknown tags stay tags")
        try expect(parsed.date.map { calendar.component(.weekday, from: $0) } == 5, "周四 must be Thursday")
        try expect(parsed.title == "投递 3 个岗位", "Plain numbers must stay in the title")
        parsed = QuickCaptureParser.parse("回复 R2 第 3 条", areaNames: areas, referenceDate: monday, calendar: calendar)
        try expect(parsed.title == "回复 R2 第 3 条" && !parsed.hasStructure, "Text without tokens must be untouched")
    }

    private static func testDayPlannerCapacityAndPlacement() throws {
        let blocks = [
            SOPTimeBlock(id: "a", title: "早晨", start: 420, end: 540, scope: .everyday, remind: false, tintName: "orange"),
            SOPTimeBlock(id: "b", title: "午饭", start: 720, end: 780, scope: .everyday, remind: false, tintName: "pink")
        ]
        let windows = DayPlanner.freeWindows(blocks: blocks)
        try expect(windows == [MinuteRange(start: 540, end: 720), MinuteRange(start: 780, end: 1440)], "Free windows must skip SOP blocks")
        let available = DayPlanner.availableMinutes(blocks: blocks, busy: [MinuteRange(start: 600, end: 660), MinuteRange(start: 630, end: 690)])
        try expect(available == 180 + 660 - 90, "Overlapping events must be merged, got \(available)")
        let placed = DayPlanner.autoPlace(durations: [90, 60], blocks: blocks, busy: [MinuteRange(start: 600, end: 660)], notBefore: 540)
        try expect(placed[0] == 780, "90 minutes must skip the 60-minute gap and land after lunch, got \(String(describing: placed[0]))")
        try expect(placed[1] == 540, "60 minutes must fit before the meeting")
    }

    private static func testScheduleAndPostpone() throws {
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), persistsChanges: false)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = try require(calendar.date(byAdding: .day, value: 1, to: today))
        let task = try require(store.addTask(title: "写方法部分"))
        store.schedule(task.id, on: today, minute: 570)
        try expect(store.task(id: task.id)?.scheduledMinute == 570 && store.task(id: task.id)?.status == .planned, "Schedule must set minute and status")
        store.setFocus(task.id, on: today, isFocus: true)
        try expect(store.focusTasks(on: today).map(\.id) == [task.id], "Focus task must appear in Top 3")
        store.postpone(task.id, to: tomorrow)
        let moved = try require(store.task(id: task.id))
        try expect(moved.isPlanned(on: tomorrow) && moved.scheduledMinute == nil && moved.postponeCount == 1, "Postpone must move the task and count it")
        try expect(store.focusTasks(on: tomorrow).count == 1, "A postponed focus task stays a focus task")
        store.undoLastAction()
        try expect(store.task(id: task.id)?.isPlanned(on: today) == true, "Postpone must be undoable")
    }

    private static func testSOPBlocksAndTimeParsing() throws {
        try expect(DailySOPTemplate.startMinute(of: "08:30–09:00") == 510, "Ranges must parse their start")
        try expect(DailySOPTemplate.startMinute(of: "09:10 前") == 550, "Suffixes must be ignored")
        try expect(DailySOPTemplate.startMinute(of: "24:00") == 1440, "24:00 must parse")
        try expect(DailySOPTemplate.startMinute(of: "周日晚上") == nil, "Text without a time must be nil")
        let calendar = Calendar(identifier: .gregorian)
        let monday = try require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let sunday = try require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let config = DailySOPTemplate.defaultConfiguration
        try expect(!DailySOPTemplate.blocks(for: monday, configuration: config, calendar: calendar).contains { $0.scope == .sunday }, "Weekdays must not include Sunday blocks")
        try expect(DailySOPTemplate.blocks(for: sunday, configuration: config, calendar: calendar).contains { $0.scope == .sunday }, "Sundays must include Sunday blocks")
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

    private static func testAdditionalInputParsingAndPrompt() throws {
        let items = try OpenAIPlanningService.additionalInputItems(from: """
        - [ ] 给导师回复实验进度
        2. 买猫粮

        【 】整理周五汇报的三张图
        """)
        try expect(items.map(\.text) == ["给导师回复实验进度", "买猫粮", "整理周五汇报的三张图"], "Additional-input line parsing failed")
        try expect(Set(items.map(\.id)).count == 3, "Each additional input must receive a unique ID")

        let payload = try OpenAIPlanningService().promptPayload(
            tomorrow: .now,
            tasks: [],
            areas: [],
            events: [],
            userInputItems: items
        )
        try expect(payload.contains("user_input_items"), "Prompt must label user input context")
        try expect(payload.contains("给导师回复实验进度"), "Prompt must preserve the user's additional input")
    }

    private static func testUserInputCoverageValidation() throws {
        let items = [
            PlanningInputItem(id: "input-a", text: "回复导师"),
            PlanningInputItem(id: "input-b", text: "买猫粮")
        ]
        let suggestions = items.map { item in
            AISuggestedTask(
                taskID: nil,
                inputItemID: item.id,
                title: item.text,
                area: "个人",
                reason: "用户补充",
                estimatedMinutes: 20,
                priority: "medium",
                source: "user_input"
            )
        }
        let complete = AIPlanSuggestion(
            summary: "ok",
            topThree: suggestions,
            additionalTasks: [],
            workloadAssessment: "合理",
            notes: ""
        )
        try OpenAIPlanningService.validateUserInputCoverage(plan: complete, items: items)

        let incomplete = AIPlanSuggestion(
            summary: "missing",
            topThree: [suggestions[0]],
            additionalTasks: [],
            workloadAssessment: "合理",
            notes: ""
        )
        do {
            try OpenAIPlanningService.validateUserInputCoverage(plan: incomplete, items: items)
            throw SelfTestError.failed("Missing user input must be rejected")
        } catch PlanningError.incompleteUserInputMapping {
            // Expected: no user-supplied item may be silently dropped.
        }
    }

    @MainActor
    private static func testUserInputCreatesTaskWithoutDuplicates() throws {
        let store = TaskStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            persistsChanges: false
        )
        let suggestion = AISuggestedTask(
            taskID: nil,
            inputItemID: "input-stable-id",
            title: "给导师回复实验进度",
            area: "工作",
            reason: "来自明日补充事项",
            estimatedMinutes: 25,
            priority: "high",
            source: "user_input"
        )
        let tomorrow = try require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        store.apply([suggestion], to: tomorrow, markAsFocus: true)
        try expect(store.tasks.count == 1, "User input must become a task after confirmation")
        try expect(store.tasks[0].sourceEventID == "input-stable-id", "Created task must retain its user-input identity")
        try expect(store.tasks[0].isPlanned(on: tomorrow), "Created user-input task must be planned for tomorrow")

        store.apply([suggestion], to: tomorrow, markAsFocus: true)
        try expect(store.tasks.count == 1, "Accepting the same plan twice must not duplicate a user-input task")
    }

    @MainActor
    private static func testEditedSuggestionUpdatesExistingTask() throws {
        let store = TaskStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            persistsChanges: false
        )
        let created = try require(store.addTask(title: "旧标题"))
        let workArea = try require(store.areas.first { $0.name == "工作" })
        let suggestion = AISuggestedTask(
            taskID: created.id.uuidString,
            title: "编辑后的标题",
            area: workArea.name,
            reason: "用户确认了编辑",
            estimatedMinutes: 45,
            priority: "high",
            source: "existing_task"
        )
        store.apply([suggestion], to: .now, markAsFocus: true)
        let updated = try require(store.task(id: created.id))
        try expect(updated.title == "编辑后的标题", "Edited AI title must update the existing task")
        try expect(updated.areaID == workArea.id, "Edited AI area must update the existing task")
        try expect(updated.priority == .high && updated.estimatedMinutes == 45, "Edited AI planning fields must be saved")
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

    @MainActor
    private static func testLegacySOPStateMigration() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sop-legacy-\(UUID().uuidString).json")
        let legacy = ["2026-08-27": Set(["wake", "wash"])]
        try JSONEncoder().encode(legacy).write(to: file)
        let store = DailySOPStore(fileURL: file, persistsChanges: true)
        try expect(store.completionByDay["2026-08-27"] == Set(["wake", "wash"]), "Legacy SOP completions must migrate")
        try expect(!store.configuration.dailySections.isEmpty, "Legacy SOP state must receive the default editable template")
    }

    @MainActor
    private static func testSOPConfigurationPersistence() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sop-config-\(UUID().uuidString).json")
        let store = DailySOPStore(fileURL: file, persistsChanges: true)
        var configuration = store.configuration
        let stableID = try require(configuration.dailySections.first?.items.first?.id)
        configuration.dailySections[0].title = "我的早晨节奏"
        configuration.dailySections[0].items[0].title = "七点立即起床"
        configuration.dailySections[0].items.append(
            DailySOPItem(
                id: "sop-test-added",
                time: "08:25",
                title: "检查随身物品",
                sectionID: configuration.dailySections[0].id,
                sectionTitle: configuration.dailySections[0].title
            )
        )
        store.setCompleted(stableID, completed: true, on: .now)
        store.updateConfiguration(configuration)

        let reloaded = DailySOPStore(fileURL: file, persistsChanges: true)
        try expect(reloaded.configuration.dailySections[0].title == "我的早晨节奏", "Edited SOP section must persist")
        try expect(reloaded.configuration.dailySections[0].items[0].id == stableID, "Existing SOP IDs must remain stable")
        try expect(reloaded.configuration.dailySections[0].items.contains { $0.id == "sop-test-added" }, "Added SOP item must persist")
        try expect(reloaded.isCompleted(stableID, on: .now), "Editing SOP must preserve completion history")
        try expect(reloaded.planningItems(for: .now).contains { $0.title == "七点立即起床" }, "AI context must use the edited SOP")
    }

    private static func testBreakdownPromptIncludesTaskContext() throws {
        let task = TaskItem(
            title: "完成论文实验",
            notes: "需要整理基线和消融结果",
            priority: .high,
            estimatedMinutes: 240,
            dueDate: .now.addingTimeInterval(86_400 * 5),
            recurrence: RecurrenceRule(frequency: .weekly)
        )
        let payload = try OpenAITaskBreakdownService().promptPayload(
            task: task,
            tasks: [task, TaskItem(title: "准备组会")],
            areas: TaskArea.defaults,
            events: [],
            weeklyPlan: WeeklyPlan(
                weekStart: .now,
                goals: ["完成实验"],
                notes: "优先跑通",
                selectedTaskIDs: [task.id],
                updatedAt: .now
            ),
            sopItems: DailySOPTemplate.planningItems(for: .now)
        )
        try expect(payload.contains("完成论文实验"), "Breakdown prompt must contain the selected task")
        try expect(payload.contains("需要整理基线和消融结果"), "Breakdown prompt must contain task notes")
        try expect(payload.contains("weekly"), "Breakdown prompt must contain recurrence")
        try expect(payload.contains("完成实验"), "Breakdown prompt must contain weekly direction")
        try expect(payload.contains("daily_sop"), "Breakdown prompt must include SOP context")
    }

    private static func testBreakdownResponseDecodingAndValidation() throws {
        let json = """
        {
          "summary": "先准备，再执行，最后检查。",
          "steps": [
            {"step_id":"prepare","title":"准备材料","notes":"列出输入","area":"工作","estimated_minutes":20,"priority":"high","planned_date":null,"due_date":null,"completion_criteria":"材料列表完整","depends_on_step_ids":[]},
            {"step_id":"execute","title":"执行主要工作","notes":"完成核心产出","area":"工作","estimated_minutes":90,"priority":"high","planned_date":null,"due_date":null,"completion_criteria":"核心产出可查看","depends_on_step_ids":["prepare"]},
            {"step_id":"review","title":"检查并提交","notes":"核对要求","area":"工作","estimated_minutes":30,"priority":"medium","planned_date":null,"due_date":null,"completion_criteria":"已提交并留存记录","depends_on_step_ids":["execute"]}
          ],
          "risks": ["预留返工时间"]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(AITaskBreakdown.self, from: Data(json.utf8))
        try OpenAITaskBreakdownService.validate(result, parentTask: TaskItem(title: "大任务"))
        try expect(result.steps[1].dependsOnStepIDs == ["prepare"], "Breakdown dependencies must decode")

        var invalid = result
        invalid.steps[0].estimatedMinutes = 600
        do {
            try OpenAITaskBreakdownService.validate(invalid, parentTask: TaskItem(title: "大任务"))
            throw SelfTestError.failed("Invalid breakdown duration must be rejected")
        } catch PlanningError.invalidPlan {
            // Expected.
        }
    }

    @MainActor
    private static func testBreakdownCreatesLinkedTasksWithoutDuplicates() throws {
        let store = TaskStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            persistsChanges: false
        )
        let parent = try require(store.addTask(title: "发布新版本"))
        let steps = [
            AIBreakdownStep(id: "one", title: "整理变更", notes: "汇总内容", area: "工作", estimatedMinutes: 20, priority: "high", plannedDate: nil, dueDate: nil, completionCriteria: "变更清单完成", dependsOnStepIDs: []),
            AIBreakdownStep(id: "two", title: "构建版本", notes: "运行构建", area: "工作", estimatedMinutes: 30, priority: "high", plannedDate: .now, dueDate: nil, completionCriteria: "构建成功", dependsOnStepIDs: ["one"]),
            AIBreakdownStep(id: "three", title: "发布并检查", notes: "检查下载", area: "工作", estimatedMinutes: 25, priority: "medium", plannedDate: nil, dueDate: nil, completionCriteria: "发布可用", dependsOnStepIDs: ["two"])
        ]
        store.applyBreakdown(steps, to: parent)
        let children = store.tasks.filter { $0.parentTaskID == parent.id }
        try expect(children.count == 3, "Confirmed breakdown must create child tasks")
        try expect(children.allSatisfy { $0.source == .openAI }, "Breakdown children must retain their AI source")
        try expect(children.contains { $0.notes.contains("完成标准") }, "Breakdown children must keep completion criteria")
        store.applyBreakdown(steps, to: parent)
        try expect(store.tasks.filter { $0.parentTaskID == parent.id }.count == 3, "Confirming the same breakdown twice must not duplicate children")
    }

    private static func testLegacyTaskDecoding() throws {
        let encoder = JSONEncoder()
        let current = TaskItem(title: "旧数据")
        let data = try encoder.encode(current)
        var object = try require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "recurrence")
        object.removeValue(forKey: "recurrenceSeriesID")
        object.removeValue(forKey: "parentTaskID")
        object.removeValue(forKey: "trashedFromStatus")
        object.removeValue(forKey: "deletedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: legacyData)
        try expect(decoded.title == "旧数据", "Legacy task data must remain decodable")
        try expect(decoded.deletedAt == nil && decoded.recurrence == nil && decoded.parentTaskID == nil, "New optional fields must default to nil")
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
