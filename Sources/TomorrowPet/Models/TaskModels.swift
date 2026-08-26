import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case inbox
    case next
    case planned
    case inProgress
    case waiting
    case completed
    case cancelled
    case archived
    case trashed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "收件箱"
        case .next: "下一步"
        case .planned: "已计划"
        case .inProgress: "进行中"
        case .waiting: "等待中"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .archived: "已归档"
        case .trashed: "垃圾箱"
        }
    }

    var isActive: Bool {
        ![.completed, .cancelled, .archived, .trashed].contains(self)
    }
}

enum TaskHorizon: String, Codable, CaseIterable, Identifiable {
    case immediate
    case shortTerm
    case longTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediate: "即时"
        case .shortTerm: "短期"
        case .longTerm: "长期"
        }
    }

    var systemImage: String {
        switch self {
        case .immediate: "bolt.fill"
        case .shortTerm: "calendar"
        case .longTerm: "mountain.2"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case high
    case medium
    case low
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        case .none: "无"
        }
    }

    private var rank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        case .none: 3
        }
    }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum TaskSource: String, Codable {
    case manual
    case calendar
    case openAI
    case imported

    var title: String {
        switch self {
        case .manual: "手动添加"
        case .calendar: "来自 Calendar"
        case .openAI: "OpenAI 建议"
        case .imported: "外部导入"
        }
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "天"
        case .weekly: "周"
        case .monthly: "月"
        }
    }
}

struct RecurrenceRule: Codable, Hashable {
    var frequency: RecurrenceFrequency
    var interval: Int
    var weekdays: Set<Int>
    var endDate: Date?

    init(
        frequency: RecurrenceFrequency = .daily,
        interval: Int = 1,
        weekdays: Set<Int> = [],
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.endDate = endDate
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let step = max(1, interval)
        let next: Date?
        switch frequency {
        case .daily:
            next = calendar.date(byAdding: .day, value: step, to: date)
        case .monthly:
            next = calendar.date(byAdding: .month, value: step, to: date)
        case .weekly:
            next = nextWeeklyDate(after: date, calendar: calendar, interval: step)
        }
        guard let next else { return nil }
        if let endDate,
           calendar.startOfDay(for: next) > calendar.startOfDay(for: endDate) {
            return nil
        }
        return next
    }

    private func nextWeeklyDate(after date: Date, calendar: Calendar, interval: Int) -> Date? {
        guard !weekdays.isEmpty else {
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        }

        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        }
        let firstWeekday = calendar.component(.weekday, from: week.start)
        let currentOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: week.start),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        let offsets = weekdays.map { ($0 - firstWeekday + 7) % 7 }.sorted()
        if let nextOffset = offsets.first(where: { $0 > currentOffset }) {
            return calendar.date(byAdding: .day, value: nextOffset - currentOffset, to: date)
        }
        let targetOffset = offsets.first ?? 0
        return calendar.date(byAdding: .day, value: interval * 7 - currentOffset + targetOffset, to: date)
    }
}

struct TaskArea: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var systemImage: String
    var colorName: String

    init(id: UUID = UUID(), name: String, systemImage: String, colorName: String) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.colorName = colorName
    }

    static let defaults: [TaskArea] = [
        TaskArea(name: "个人", systemImage: "person.fill", colorName: "teal"),
        TaskArea(name: "工作", systemImage: "briefcase.fill", colorName: "blue"),
        TaskArea(name: "学习", systemImage: "book.fill", colorName: "purple"),
        TaskArea(name: "健康", systemImage: "heart.fill", colorName: "pink"),
        TaskArea(name: "家庭", systemImage: "house.fill", colorName: "orange"),
        TaskArea(name: "财务", systemImage: "creditcard.fill", colorName: "green")
    ]
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var areaID: UUID?
    var project: String
    var tags: [String]
    var status: TaskStatus
    var manualHorizon: TaskHorizon?
    var priority: TaskPriority
    var estimatedMinutes: Int?
    var dueDate: Date?
    var plannedDate: Date?
    var focusDate: Date?
    var reviewDate: Date?
    var source: TaskSource
    var sourceEventID: String?
    var createdAt: Date
    var completedAt: Date?
    var recurrence: RecurrenceRule?
    var recurrenceSeriesID: UUID?
    var trashedFromStatus: TaskStatus?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        areaID: UUID? = nil,
        project: String = "",
        tags: [String] = [],
        status: TaskStatus = .inbox,
        manualHorizon: TaskHorizon? = nil,
        priority: TaskPriority = .none,
        estimatedMinutes: Int? = nil,
        dueDate: Date? = nil,
        plannedDate: Date? = nil,
        focusDate: Date? = nil,
        reviewDate: Date? = nil,
        source: TaskSource = .manual,
        sourceEventID: String? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        recurrence: RecurrenceRule? = nil,
        recurrenceSeriesID: UUID? = nil,
        trashedFromStatus: TaskStatus? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.areaID = areaID
        self.project = project
        self.tags = tags
        self.status = status
        self.manualHorizon = manualHorizon
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
        self.plannedDate = plannedDate
        self.focusDate = focusDate
        self.reviewDate = reviewDate
        self.source = source
        self.sourceEventID = sourceEventID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.recurrence = recurrence
        self.recurrenceSeriesID = recurrenceSeriesID
        self.trashedFromStatus = trashedFromStatus
        self.deletedAt = deletedAt
    }

    func effectiveHorizon(referenceDate: Date = .now, calendar: Calendar = .current) -> TaskHorizon {
        if let manualHorizon { return manualHorizon }

        let start = calendar.startOfDay(for: referenceDate)
        let immediateBoundary = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        let shortTermBoundary = calendar.date(byAdding: .day, value: 30, to: start) ?? start
        let target = dueDate ?? plannedDate

        guard let target else { return .longTerm }
        if target < immediateBoundary { return .immediate }
        if target < shortTermBoundary { return .shortTerm }
        return .longTerm
    }

    func isPlanned(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let plannedDate else { return false }
        return calendar.isDate(plannedDate, inSameDayAs: date)
    }
}

enum SidebarDestination: Hashable, Identifiable {
    case planner
    case weekly
    case inbox
    case all
    case today
    case tomorrow
    case immediate
    case shortTerm
    case longTerm
    case waiting
    case completed
    case trash
    case area(UUID)

    var id: String {
        switch self {
        case .planner: "planner"
        case .weekly: "weekly"
        case .inbox: "inbox"
        case .all: "all"
        case .today: "today"
        case .tomorrow: "tomorrow"
        case .immediate: "immediate"
        case .shortTerm: "shortTerm"
        case .longTerm: "longTerm"
        case .waiting: "waiting"
        case .completed: "completed"
        case .trash: "trash"
        case .area(let id): "area-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .planner: "明日 AI 计划"
        case .weekly: "本周计划"
        case .inbox: "收件箱"
        case .all: "全部任务"
        case .today: "今天"
        case .tomorrow: "明天"
        case .immediate: "即时任务"
        case .shortTerm: "短期任务"
        case .longTerm: "长期任务"
        case .waiting: "等待中"
        case .completed: "已完成"
        case .trash: "垃圾箱"
        case .area: "领域"
        }
    }
}
