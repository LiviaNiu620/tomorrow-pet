import Foundation

struct DailySOPItem: Identifiable, Codable, Hashable {
    var id: String
    var time: String?
    var title: String
    var detail: String?
    var sectionID: String
    var sectionTitle: String
    var isPlanningContext: Bool

    init(
        id: String,
        time: String? = nil,
        title: String,
        detail: String? = nil,
        sectionID: String,
        sectionTitle: String,
        isPlanningContext: Bool = true
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.detail = detail
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
        self.isPlanningContext = isPlanningContext
    }
}

struct DailySOPSection: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var systemImage: String
    var tintName: String
    var items: [DailySOPItem]
}

struct DailySOPConfiguration: Codable, Hashable {
    var dailySections: [DailySOPSection]
    var sundaySection: DailySOPSection
    var monthlySection: DailySOPSection
    /// 时间轴上的 SOP 时段；为空时使用默认时段。
    var timeBlocks: [SOPTimeBlock]? = nil
}

enum SOPBlockScope: String, Codable, CaseIterable, Identifiable {
    case everyday
    case sunday
    case monthEnd

    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyday: "工作日"
        case .sunday: "周日"
        case .monthEnd: "月末周日"
        }
    }
}

struct SOPTimeBlock: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var start: Int
    var end: Int
    var scope: SOPBlockScope
    var remind: Bool
    var tintName: String

    var duration: Int { max(0, end - start) }

    static let defaults: [SOPTimeBlock] = [
        SOPTimeBlock(id: "morning", title: "早晨与通勤", start: 420, end: 540, scope: .everyday, remind: true, tintName: "orange"),
        SOPTimeBlock(id: "work-start", title: "工作启动 · Email · Top 3", start: 540, end: 565, scope: .everyday, remind: true, tintName: "blue"),
        SOPTimeBlock(id: "gym", title: "健身", start: 720, end: 800, scope: .everyday, remind: true, tintName: "pink"),
        SOPTimeBlock(id: "email-pm", title: "Email 第二轮", start: 990, end: 1005, scope: .everyday, remind: false, tintName: "blue"),
        SOPTimeBlock(id: "wrap", title: "收尾 · 校车复盘", start: 1035, end: 1090, scope: .everyday, remind: true, tintName: "blue"),
        SOPTimeBlock(id: "dinner", title: "做饭 · 晚饭 · 背 20 词", start: 1100, end: 1220, scope: .everyday, remind: false, tintName: "orange"),
        SOPTimeBlock(id: "night", title: "洗漱放松 · 复盘 · 睡觉", start: 1320, end: 1440, scope: .everyday, remind: true, tintName: "purple"),
        SOPTimeBlock(id: "sunday-plan", title: "周日计划 SOP", start: 1230, end: 1290, scope: .sunday, remind: true, tintName: "green"),
        SOPTimeBlock(id: "month-review", title: "月度复盘", start: 1290, end: 1320, scope: .monthEnd, remind: true, tintName: "pink")
    ]
}

enum DailySOPTemplate {
    static func sections(for date: Date, calendar: Calendar = .current) -> [DailySOPSection] {
        sections(for: date, configuration: defaultConfiguration, calendar: calendar)
    }

    static func sections(
        for date: Date,
        configuration: DailySOPConfiguration,
        calendar: Calendar = .current
    ) -> [DailySOPSection] {
        var result = configuration.dailySections
        if calendar.component(.weekday, from: date) == 1 {
            result.append(configuration.sundaySection)
            if isLastSundayOfMonth(date, calendar: calendar) {
                result.append(configuration.monthlySection)
            }
        }
        return result
    }

    static func blocks(
        for date: Date,
        configuration: DailySOPConfiguration,
        calendar: Calendar = .current
    ) -> [SOPTimeBlock] {
        let all = configuration.timeBlocks ?? SOPTimeBlock.defaults
        let isSunday = calendar.component(.weekday, from: date) == 1
        let isMonthEnd = isSunday && isLastSundayOfMonth(date, calendar: calendar)
        return all.filter { block in
            switch block.scope {
            case .everyday: true
            case .sunday: isSunday
            case .monthEnd: isMonthEnd
            }
        }
        .sorted { $0.start < $1.start }
    }

    /// 解析 “07:00”“08:30–09:00”“09:10 前”“24:00” 等写法中的第一个时间。
    static func startMinute(of time: String?) -> Int? {
        guard let time else { return nil }
        let pattern = try? NSRegularExpression(pattern: "(\\d{1,2})[:：](\\d{2})")
        let range = NSRange(time.startIndex..., in: time)
        guard let match = pattern?.firstMatch(in: time, range: range),
              let hourRange = Range(match.range(at: 1), in: time),
              let minuteRange = Range(match.range(at: 2), in: time),
              let hour = Int(time[hourRange]),
              let minute = Int(time[minuteRange]),
              hour <= 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }

    static func planningItems(for date: Date, calendar: Calendar = .current) -> [DailySOPItem] {
        sections(for: date, calendar: calendar)
            .flatMap(\.items)
            .filter(\.isPlanningContext)
    }

    static func planningItems(
        for date: Date,
        configuration: DailySOPConfiguration,
        calendar: Calendar = .current
    ) -> [DailySOPItem] {
        sections(for: date, configuration: configuration, calendar: calendar)
            .flatMap(\.items)
            .filter(\.isPlanningContext)
    }

    static var defaultConfiguration: DailySOPConfiguration {
        DailySOPConfiguration(
            dailySections: dailySections,
            sundaySection: sundaySection,
            monthlySection: monthlySection
        )
    }

    static func isLastSundayOfMonth(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.weekday, from: date) == 1,
              let nextSunday = calendar.date(byAdding: .day, value: 7, to: date) else {
            return false
        }
        return calendar.component(.month, from: date) != calendar.component(.month, from: nextSunday)
    }

    private static func item(
        _ id: String,
        _ time: String? = nil,
        _ title: String,
        detail: String? = nil,
        section: String,
        sectionTitle: String,
        planning: Bool = true
    ) -> DailySOPItem {
        DailySOPItem(
            id: id,
            time: time,
            title: title,
            detail: detail,
            sectionID: section,
            sectionTitle: sectionTitle,
            isPlanningContext: planning
        )
    }

    private static let dailySections: [DailySOPSection] = [
        DailySOPSection(
            id: "morning",
            title: "早晨与通勤",
            systemImage: "sunrise.fill",
            tintName: "orange",
            items: [
                item("wake", "07:00", "起床", detail: "直接离床，不在床上看手机", section: "morning", sectionTitle: "早晨与通勤"),
                item("wash", "07:20", "完成洗漱、换衣服", section: "morning", sectionTitle: "早晨与通勤"),
                item("makeup", "07:55", "完成化妆", detail: "可以同时听一节 TED", section: "morning", sectionTitle: "早晨与通勤"),
                item("pack", "08:00", "收好随身物品", detail: "检查电脑、钥匙、饭、水杯", section: "morning", sectionTitle: "早晨与通勤"),
                item("coffee", "08:00–08:20", "制作并装好带走的咖啡", section: "morning", sectionTitle: "早晨与通勤"),
                item("leave-home", "08:20", "出门前往校车站", section: "morning", sectionTitle: "早晨与通勤"),
                item("morning-bus", "08:30", "坐校车去学校", section: "morning", sectionTitle: "早晨与通勤"),
                item("morning-words", "08:30–09:00", "背当天前 30 个单词", section: "morning", sectionTitle: "早晨与通勤"),
                item("arrive-work", "09:00", "到达工位", section: "morning", sectionTitle: "早晨与通勤")
            ]
        ),
        DailySOPSection(
            id: "work-start",
            title: "到工位后的启动 SOP",
            systemImage: "play.circle.fill",
            tintName: "blue",
            items: [
                item("email-scan", "09:00–09:04", "快速 Check Email", detail: "只识别紧急邮件、Deadline 和今天必须处理的事项", section: "work-start", sectionTitle: "工作启动"),
                item("record-deadlines", "09:00–09:04", "记录新增的紧急事项和 Deadline", section: "work-start", sectionTitle: "工作启动"),
                item("work-order", "09:04–09:10", "完成今日工作排序", section: "work-start", sectionTitle: "工作启动"),
                item("daily-top-three", "09:10 前", "写出今日 Top 3", section: "work-start", sectionTitle: "工作启动"),
                item("top-one-action", "09:10 前", "明确 Top 1 的启动动作", section: "work-start", sectionTitle: "工作启动"),
                item("email-process-am", "09:10–09:25", "集中回复和处理 Email", detail: "长邮件转成任务；Deadline 进入任务系统", section: "work-start", sectionTitle: "工作启动")
            ]
        ),
        DailySOPSection(
            id: "workday",
            title: "白天工作与健身",
            systemImage: "briefcase.fill",
            tintName: "indigo",
            items: [
                item("gym-leave", "12:00", "去健身", section: "workday", sectionTitle: "白天"),
                item("gym-return", "13:20", "健身后回到工位", section: "workday", sectionTitle: "白天"),
                item("email-process-pm", "16:30–16:45", "第二次 Check 和回复 Email", section: "workday", sectionTitle: "白天"),
                item("work-wrap", "17:15", "开始工作收尾", section: "workday", sectionTitle: "白天"),
                item("record-unfinished", "17:15–17:25", "记录未完成事项", section: "workday", sectionTitle: "白天"),
                item("record-first-action", "17:15–17:25", "记录明天第一件要做的事", section: "workday", sectionTitle: "白天"),
                item("leave-work", "17:25", "下班去等车", section: "workday", sectionTitle: "白天"),
                item("evening-bus", "17:45", "坐校车回家", section: "workday", sectionTitle: "白天"),
                item("work-review-bus", "17:45–18:10", "校车上复盘今日工作", detail: "完成、进展、问题、明日第一行动", section: "workday", sectionTitle: "白天"),
                item("arrive-home", "18:10", "到家", section: "workday", sectionTitle: "白天")
            ]
        ),
        DailySOPSection(
            id: "evening",
            title: "晚间 SOP",
            systemImage: "moon.stars.fill",
            tintName: "purple",
            items: [
                item("cook", "18:20", "开始做饭", detail: "可以听 TED", section: "evening", sectionTitle: "晚上"),
                item("dinner", "19:00", "开始吃饭", section: "evening", sectionTitle: "晚上"),
                item("breakfast-prep", "20:00 前", "完成第二天早餐准备", section: "evening", sectionTitle: "晚上"),
                item("evening-words", "20:00–20:20", "背剩余 20 个单词", detail: "全天合计 50 个", section: "evening", sectionTitle: "晚上"),
                item("personal-work", "20:20–22:00", "个人学习和自己的工作", section: "evening", sectionTitle: "晚上"),
                item("night-routine", "22:00–23:00", "卸妆、洗漱、洗澡、放松", detail: "不再开始大型任务", section: "evening", sectionTitle: "晚上"),
                item("watch-show", "23:00", "看剧、放松", section: "evening", sectionTitle: "晚上"),
                item("stop-show", "23:40", "停止看剧", section: "evening", sectionTitle: "晚上"),
                item("daily-review", "23:40–24:00", "写每日复盘", detail: "核对计划、分析问题、记录经验", section: "evening", sectionTitle: "晚上"),
                item("tomorrow-plan", "23:40–24:00", "列出第二天计划", detail: "参考 Calendar、未完成事项、本周目标和 Deadline", section: "evening", sectionTitle: "晚上"),
                item("sleep", "24:00", "睡觉", detail: "关灯，手机离床", section: "evening", sectionTitle: "晚上")
            ]
        ),
        DailySOPSection(
            id: "daily-goals",
            title: "每日固定目标",
            systemImage: "target",
            tintName: "teal",
            items: [
                item("read-paper", nil, "阅读至少一篇文献", detail: "完成一篇有效快速阅读", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("leetcode-one", nil, "LeetCode 第 1 题", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("leetcode-two", nil, "LeetCode 第 2 题", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("data-structure", nil, "学习一节数据结构课", detail: "至少 20–25 分钟并记录要点", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("words-fifty", nil, "背 50 个单词", detail: "早校车 30 个 + 晚上 20 个", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("ted", nil, "看或听一节 TED", detail: "记录一句核心观点", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("journal", nil, "写日记", detail: "至少记录情绪、收获与明日状态", section: "daily-goals", sectionTitle: "每日固定目标"),
                item("fitness", nil, "完成健身", section: "daily-goals", sectionTitle: "每日固定目标")
            ]
        )
    ]

    private static let sundaySection = DailySOPSection(
        id: "sunday",
        title: "周日计划 SOP",
        systemImage: "calendar.badge.clock",
        tintName: "blue",
        items: [
            item("weekly-review", "周日晚上", "完成本周复盘", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("next-week-deadlines", nil, "检查下周所有 Deadline", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("two-week-deadlines", nil, "检查未来两周的重要 Deadline", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("next-week-calendar", nil, "检查下周会议和固定安排", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("email-deadlines", nil, "检查邮箱中遗漏的 Deadline", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("waiting-followup", nil, "检查等待别人回复的事项", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("weekly-outcomes", nil, "列出下周三个核心结果", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("weekly-allocation", nil, "将核心结果初步分配到每天", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("monday-top-three", nil, "明确周一的 Top 3", section: "sunday", sectionTitle: "周日计划", planning: false),
            item("monday-first-action", nil, "明确周一到工位后的第一项行动", section: "sunday", sectionTitle: "周日计划", planning: false)
        ]
    )

    private static let monthlySection = DailySOPSection(
        id: "monthly",
        title: "月末额外 SOP",
        systemImage: "calendar.badge.exclamationmark",
        tintName: "pink",
        items: [
            item("monthly-review", nil, "完成本月复盘", section: "monthly", sectionTitle: "月度计划", planning: false),
            item("next-month-dates", nil, "检查下月重要日期与 Deadline", section: "monthly", sectionTitle: "月度计划", planning: false),
            item("next-month-domains", nil, "制定工作、学习、健康、生活目标", section: "monthly", sectionTitle: "月度计划", planning: false),
            item("next-month-top-three", nil, "列出下月三个最重要的结果", section: "monthly", sectionTitle: "月度计划", planning: false),
            item("next-month-weeks", nil, "把月度结果初步分配到各周", section: "monthly", sectionTitle: "月度计划", planning: false),
            item("stop-start-continue", nil, "写下需要停止、开始和继续的事情", section: "monthly", sectionTitle: "月度计划", planning: false)
        ]
    )
}
