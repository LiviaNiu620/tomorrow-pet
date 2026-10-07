import Foundation

/// 随手记的解析结果：“明天下午3点 写 CEUS 摘要 #工作 45m !高”。
struct ParsedCapture: Equatable {
    var title: String
    var date: Date?
    var dayLabel: String?
    var minute: Int?
    var duration: Int?
    var areaName: String?
    var unknownTag: String?
    var priority: TaskPriority?

    var hasStructure: Bool {
        date != nil || minute != nil || duration != nil || areaName != nil || unknownTag != nil || priority != nil
    }
}

enum QuickCaptureParser {
    static func parse(
        _ text: String,
        areaNames: [String],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> ParsedCapture {
        var rest = " " + text + " "
        var result = ParsedCapture(title: "")
        let today = calendar.startOfDay(for: referenceDate)

        func take(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            let range = NSRange(rest.startIndex..., in: rest)
            guard let match = regex.firstMatch(in: rest, range: range),
                  let whole = Range(match.range, in: rest) else { return nil }
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: index), in: rest) { groups.append(String(rest[r])) }
                else { groups.append("") }
            }
            rest.replaceSubrange(whole, with: " ")
            return groups
        }

        // 日期
        if take("后天") != nil {
            result.date = calendar.date(byAdding: .day, value: 2, to: today)
            result.dayLabel = "后天"
        } else if take("明天") != nil {
            result.date = calendar.date(byAdding: .day, value: 1, to: today)
            result.dayLabel = "明天"
        } else if take("今天|今晚") != nil {
            result.date = today
            result.dayLabel = "今天"
        } else if let groups = take("(下)?(?:周|星期)([一二三四五六日天])") {
            let names: [String: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
            if let weekday = names[groups[2]] {
                let current = calendar.component(.weekday, from: today)
                var offset = (weekday - current + 7) % 7
                if offset == 0 { offset = 7 }
                if !groups[1].isEmpty && offset < 7 { offset += 7 }
                result.date = calendar.date(byAdding: .day, value: offset, to: today)
                result.dayLabel = (groups[1].isEmpty ? "周" : "下周") + groups[2]
            }
        } else if let groups = take("(\\d{1,2})[/月](\\d{1,2})日?") {
            var components = calendar.dateComponents([.year], from: today)
            components.month = Int(groups[1]); components.day = Int(groups[2])
            if let date = calendar.date(from: components) {
                result.date = date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
                result.dayLabel = "\(groups[1])/\(groups[2])"
            }
        }

        // 时间
        if let groups = take("(上午|早上|中午|下午|晚上)?\\s*(\\d{1,2})\\s*(?:[:：](\\d{2})|点(半|(\\d{1,2})分?)?)") {
            var hour = Int(groups[2]) ?? 0
            var minute = 0
            if !groups[3].isEmpty { minute = Int(groups[3]) ?? 0 }
            else if groups[4] == "半" { minute = 30 }
            else if !groups[5].isEmpty { minute = Int(groups[5]) ?? 0 }
            if ["下午", "晚上"].contains(groups[1]) && hour < 12 { hour += 12 }
            if groups[1] == "中午" && hour < 3 { hour += 12 }
            if hour < 24 && minute < 60 { result.minute = hour * 60 + minute }
        }

        // 时长
        if let groups = take("(\\d+(?:\\.\\d+)?)\\s*(?:h|小时)", options: .caseInsensitive) {
            result.duration = Int(((Double(groups[1]) ?? 0) * 60).rounded())
        } else if let groups = take("(\\d+)\\s*(?:min|分钟|m)(?![a-z])", options: .caseInsensitive) {
            result.duration = Int(groups[1])
        }

        // 领域 / 标签
        if let groups = take("#(\\S+)") {
            if let name = areaNames.first(where: { $0.caseInsensitiveCompare(groups[1]) == .orderedSame }) {
                result.areaName = name
            } else {
                result.unknownTag = groups[1]
            }
        }

        // 优先级
        if let groups = take("[!！](高|中|低)") {
            result.priority = ["高": .high, "中": .medium, "低": .low][groups[1]]
        }

        if result.minute != nil && result.date == nil {
            result.date = today
            result.dayLabel = "今天"
        }
        result.title = rest.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return result
    }
}
