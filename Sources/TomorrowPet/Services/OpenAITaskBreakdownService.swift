import Foundation

struct OpenAITaskBreakdownService {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func createBreakdown(
        apiKey: String,
        model: String,
        task: TaskItem,
        tasks: [TaskItem],
        areas: [TaskArea],
        events: [CalendarEventSummary],
        weeklyPlan: WeeklyPlan?,
        sopItems: [DailySOPItem]
    ) async throws -> AITaskBreakdown {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw PlanningError.missingAPIKey }

        let input = try promptPayload(
            task: task,
            tasks: tasks,
            areas: areas,
            events: events,
            weeklyPlan: weeklyPlan,
            sopItems: sopItems
        )
        let body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": """
                    你是一只务实、温和的中文任务规划宠物。请把 selected_task 拆成 3–12 个可执行、可验证的步骤，并根据用户已有安排给出合理日期。
                    规则：
                    1. 每一步都必须是具体行动，并写明完成标准；不要把原任务标题原样当作步骤。
                    2. 日期使用 ISO 8601（例如 2026-08-30T09:00:00-07:00）；无法合理确定时返回 null。
                    3. 如果原任务有截止日期，所有步骤的 due_date 不得晚于该日期；计划日期不得晚于步骤截止日期。
                    4. 每步预计 5–480 分钟。步骤太大时继续拆细，但不要制造无意义的微步骤。
                    5. step_id 使用简短且唯一的英文或数字标识；依赖关系只能引用本次结果中更早出现的 step_id。
                    6. area 只能优先使用 available_areas 中已有名称；priority 只能是 high、medium、low、none。
                    7. calendar_events、daily_sop 和 weekly_plan 只用于避开冲突和判断负荷，不得虚构会议内容或修改日历。
                    8. 周期任务只拆解当前一次执行，不修改原任务的周期规则。
                    9. 所有说明使用简体中文，不制造内疚。结果仅供预览，用户确认后才会创建任务。
                    """
                ],
                ["role": "user", "content": input]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "task_breakdown",
                    "strict": true,
                    "schema": Self.breakdownSchema
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlanningError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw PlanningError.api(status: http.statusCode, message: Self.apiErrorMessage(from: data))
        }

        let text = try OpenAIPlanningService.extractOutputText(from: data)
        do {
            let decoder = Self.makeDecoder()
            let result = try decoder.decode(AITaskBreakdown.self, from: Data(text.utf8))
            try Self.validate(result, parentTask: task)
            return result
        } catch {
            if let planningError = error as? PlanningError { throw planningError }
            throw PlanningError.invalidPlan(error.localizedDescription)
        }
    }

    func promptPayload(
        task: TaskItem,
        tasks: [TaskItem],
        areas: [TaskArea],
        events: [CalendarEventSummary],
        weeklyPlan: WeeklyPlan?,
        sopItems: [DailySOPItem]
    ) throws -> String {
        let formatter = ISO8601DateFormatter()
        let areaNames = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.name) })

        func optionalDate(_ date: Date?) -> Any {
            date.map { formatter.string(from: $0) as Any } ?? NSNull()
        }

        let selectedTask: [String: Any] = [
            "task_id": task.id.uuidString,
            "title": task.title,
            "notes": task.notes,
            "area": task.areaID.flatMap { areaNames[$0] } ?? "未分类",
            "project": task.project,
            "priority": task.priority.rawValue,
            "estimated_minutes": task.estimatedMinutes.map { $0 as Any } ?? NSNull(),
            "planned_date": optionalDate(task.plannedDate),
            "due_date": optionalDate(task.dueDate),
            "review_date": optionalDate(task.reviewDate),
            "recurrence": recurrencePayload(task.recurrence, formatter: formatter)
        ]

        let otherTasks = tasks
            .filter { $0.status.isActive && $0.id != task.id }
            .prefix(80)
            .map { item in
                [
                    "task_id": item.id.uuidString,
                    "title": item.title,
                    "area": item.areaID.flatMap { areaNames[$0] } ?? "未分类",
                    "priority": item.priority.rawValue,
                    "estimated_minutes": item.estimatedMinutes.map { $0 as Any } ?? NSNull(),
                    "planned_date": optionalDate(item.plannedDate),
                    "due_date": optionalDate(item.dueDate)
                ] as [String: Any]
            }

        let weeklyPayload: Any
        if let weeklyPlan {
            weeklyPayload = [
                "goals": weeklyPlan.goals,
                "notes": weeklyPlan.notes,
                "selected_task_ids": weeklyPlan.selectedTaskIDs.map(\.uuidString)
            ] as [String: Any]
        } else {
            weeklyPayload = NSNull()
        }

        let payload: [String: Any] = [
            "current_time": formatter.string(from: .now),
            "selected_task": selectedTask,
            "available_areas": areas.map(\.name),
            "active_tasks": otherTasks,
            "calendar_events": events.map { event in
                [
                    "title": event.title,
                    "start": formatter.string(from: event.startDate),
                    "end": formatter.string(from: event.endDate),
                    "all_day": event.isAllDay,
                    "source": event.source.rawValue
                ] as [String: Any]
            },
            "weekly_plan": weeklyPayload,
            "daily_sop": sopItems.map { item in
                [
                    "time": item.time.map { $0 as Any } ?? NSNull(),
                    "title": item.title,
                    "section": item.sectionTitle
                ] as [String: Any]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func validate(_ result: AITaskBreakdown, parentTask: TaskItem) throws {
        guard (3...12).contains(result.steps.count) else {
            throw PlanningError.invalidPlan("任务拆解必须包含 3–12 个步骤。")
        }
        let ids = result.steps.map(\.id)
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(ids).count == ids.count else {
            throw PlanningError.invalidPlan("步骤标识为空或重复。")
        }

        var seen = Set<String>()
        for step in result.steps {
            guard !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !step.completionCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (5...480).contains(step.estimatedMinutes),
                  Set(step.dependsOnStepIDs).isSubset(of: seen) else {
                throw PlanningError.invalidPlan("步骤内容、估时或依赖关系无效。")
            }
            let calendar = Calendar.current
            if let planned = step.plannedDate,
               let due = step.dueDate,
               calendar.startOfDay(for: planned) > calendar.startOfDay(for: due) {
                throw PlanningError.invalidPlan("步骤的计划日期晚于截止日期。")
            }
            if let parentDue = parentTask.dueDate,
               let due = step.dueDate,
               calendar.startOfDay(for: due) > calendar.startOfDay(for: parentDue) {
                throw PlanningError.invalidPlan("步骤截止日期晚于原任务期限。")
            }
            seen.insert(step.id)
        }
    }

    private func recurrencePayload(_ rule: RecurrenceRule?, formatter: ISO8601DateFormatter) -> Any {
        guard let rule else { return NSNull() }
        return [
            "frequency": rule.frequency.rawValue,
            "interval": rule.interval,
            "weekdays": rule.weekdays.sorted(),
            "end_date": rule.endDate.map { formatter.string(from: $0) as Any } ?? NSNull()
        ] as [String: Any]
    }

    private static func apiErrorMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "OpenAI 返回了无法读取的错误。"
        }
        return message
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }

            let internet = ISO8601DateFormatter()
            if let date = internet.date(from: value) { return date }

            let dateOnly = DateFormatter()
            dateOnly.calendar = Calendar(identifier: .gregorian)
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = .current
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: value) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析 ISO 8601 日期：\(value)"
            )
        }
        return decoder
    }

    private static var stepSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "step_id": ["type": "string"],
            "title": ["type": "string"],
            "notes": ["type": "string"],
            "area": ["type": "string"],
            "estimated_minutes": ["type": "integer", "minimum": 5, "maximum": 480],
            "priority": ["type": "string", "enum": ["high", "medium", "low", "none"]],
            "planned_date": ["type": ["string", "null"]],
            "due_date": ["type": ["string", "null"]],
            "completion_criteria": ["type": "string"],
            "depends_on_step_ids": ["type": "array", "items": ["type": "string"]]
        ],
        "required": [
            "step_id", "title", "notes", "area", "estimated_minutes", "priority",
            "planned_date", "due_date", "completion_criteria", "depends_on_step_ids"
        ],
        "additionalProperties": false
    ] }

    private static var breakdownSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "steps": ["type": "array", "items": stepSchema, "minItems": 3, "maxItems": 12],
            "risks": ["type": "array", "items": ["type": "string"], "maxItems": 6]
        ],
        "required": ["summary", "steps", "risks"],
        "additionalProperties": false
    ] }
}
