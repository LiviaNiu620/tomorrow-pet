import Foundation

struct OpenAIPlanningService {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func createTomorrowPlan(
        apiKey: String,
        model: String,
        tomorrow: Date,
        tasks: [TaskItem],
        areas: [TaskArea],
        events: [CalendarEventSummary],
        weeklyPlan: WeeklyPlan? = nil
    ) async throws -> AIPlanSuggestion {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw PlanningError.missingAPIKey }

        let input = try promptPayload(
            tomorrow: tomorrow,
            tasks: tasks,
            areas: areas,
            events: events,
            weeklyPlan: weeklyPlan
        )
        let body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": """
                    你是一只温和、务实的中文桌面规划宠物。请根据用户明天的日历和统一任务库，制定不过载的明日计划。
                    规则：
                    1. 最多选择三个 top_three；优先截止日期、已计划任务、本周推进价值和日历准备事项。
                    2. 不要假设所有空闲时间都可用，保留至少 30% 弹性。
                    3. 已有任务必须原样返回 task_id；只有日历确实暗示准备动作时才可创建 task_id 为 null 的新建议。
                    4. 不要重复任务，不要虚构会议内容，不要替用户修改日历。
                    5. 所有文字使用简体中文，理由具体、简短、不制造内疚。
                    6. 如果提供了本周计划，把周目标和已选周任务作为方向性上下文；它们不能覆盖截止日期、日历约束和合理负荷。
                    """
                ],
                [
                    "role": "user",
                    "content": input
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "tomorrow_plan",
                    "strict": true,
                    "schema": Self.planSchema
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

        let text = try Self.extractOutputText(from: data)
        do {
            return try JSONDecoder().decode(AIPlanSuggestion.self, from: Data(text.utf8))
        } catch {
            throw PlanningError.invalidPlan(error.localizedDescription)
        }
    }

    func promptPayload(
        tomorrow: Date,
        tasks: [TaskItem],
        areas: [TaskArea],
        events: [CalendarEventSummary],
        weeklyPlan: WeeklyPlan? = nil
    ) throws -> String {
        let formatter = ISO8601DateFormatter()
        let areaNames = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.name) })
        let taskPayload: [[String: Any]] = tasks.filter(\.status.isActive).map { task in
            var value: [String: Any] = [
                "task_id": task.id.uuidString,
                "title": task.title,
                "area": task.areaID.flatMap { areaNames[$0] } ?? "未分类",
                "status": task.status.rawValue,
                "horizon": task.effectiveHorizon().rawValue,
                "priority": task.priority.rawValue,
                "estimated_minutes": task.estimatedMinutes.map { $0 as Any } ?? NSNull()
            ]
            value["due_date"] = task.dueDate.map { formatter.string(from: $0) as Any } ?? NSNull()
            value["planned_date"] = task.plannedDate.map { formatter.string(from: $0) as Any } ?? NSNull()
            return value
        }

        let eventPayload: [[String: Any]] = events.map { event in
            [
                "title": event.title,
                "start": formatter.string(from: event.startDate),
                "end": formatter.string(from: event.endDate),
                "all_day": event.isAllDay,
                "calendar": event.calendarTitle,
                "source": event.source.rawValue
            ]
        }

        let weeklyPayload: Any
        if let weeklyPlan {
            let taskTitles = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
            weeklyPayload = [
                "week_start": formatter.string(from: weeklyPlan.weekStart),
                "goals": weeklyPlan.goals,
                "notes": weeklyPlan.notes,
                "selected_task_ids": weeklyPlan.selectedTaskIDs.map(\.uuidString),
                "selected_task_titles": weeklyPlan.selectedTaskIDs.compactMap { taskTitles[$0] }
            ] as [String: Any]
        } else {
            weeklyPayload = NSNull()
        }

        let payload: [String: Any] = [
            "tomorrow": formatter.string(from: Calendar.current.startOfDay(for: tomorrow)),
            "calendar_events": eventPayload,
            "active_tasks": taskPayload,
            "weekly_plan": weeklyPayload
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func extractOutputText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]] else {
            throw PlanningError.invalidResponse
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content where block["type"] as? String == "output_text" {
                if let text = block["text"] as? String { return text }
            }
        }
        throw PlanningError.missingOutput
    }

    private static func apiErrorMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "OpenAI 返回了无法读取的错误。"
        }
        return message
    }

    private static let suggestedTaskSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "task_id": ["type": ["string", "null"]],
            "title": ["type": "string"],
            "area": ["type": "string"],
            "reason": ["type": "string"],
            "estimated_minutes": ["type": "integer", "minimum": 5, "maximum": 480],
            "priority": ["type": "string", "enum": ["high", "medium", "low", "none"]],
            "source": ["type": "string", "enum": ["existing_task", "calendar_preparation"]]
        ],
        "required": ["task_id", "title", "area", "reason", "estimated_minutes", "priority", "source"],
        "additionalProperties": false
    ]

    private static let planSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "top_three": [
                "type": "array",
                "items": suggestedTaskSchema,
                "maxItems": 3
            ],
            "additional_tasks": [
                "type": "array",
                "items": suggestedTaskSchema,
                "maxItems": 5
            ],
            "workload_assessment": ["type": "string"],
            "notes": ["type": "string"]
        ],
        "required": ["summary", "top_three", "additional_tasks", "workload_assessment", "notes"],
        "additionalProperties": false
    ]
}

enum PlanningError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case missingOutput
    case invalidPlan(String)
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请先在设置中填写 OpenAI API Key。"
        case .invalidResponse:
            "OpenAI 返回了无法识别的响应。"
        case .missingOutput:
            "OpenAI 没有返回规划文本，请稍后重试。"
        case .invalidPlan(let message):
            "AI 计划格式校验失败：\(message)"
        case .api(let status, let message):
            "OpenAI 请求失败（HTTP \(status)）：\(message)"
        }
    }
}
