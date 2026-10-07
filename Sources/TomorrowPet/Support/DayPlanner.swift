import Foundation

/// 一天里的一个时间段，单位：距午夜的分钟数。
struct MinuteRange: Hashable {
    var start: Int
    var end: Int
    var length: Int { max(0, end - start) }

    func overlap(with other: MinuteRange) -> Int {
        max(0, min(end, other.end) - max(start, other.start))
    }
}

/// 计算空档、可用时长，并把 AI 建议自动放进空档。
enum DayPlanner {
    static let dayStart = 7 * 60
    static let dayEnd = 24 * 60

    static func minuteRange(of event: CalendarEventSummary, on day: Date, calendar: Calendar = .current) -> MinuteRange? {
        guard !event.isAllDay else { return nil }
        let startOfDay = calendar.startOfDay(for: day)
        let start = Int(event.startDate.timeIntervalSince(startOfDay) / 60)
        let end = Int(event.endDate.timeIntervalSince(startOfDay) / 60)
        let clipped = MinuteRange(start: max(0, start), end: min(dayEnd, end))
        return clipped.length > 0 ? clipped : nil
    }

    /// 去掉 SOP 时段后的空档。
    static func freeWindows(blocks: [SOPTimeBlock]) -> [MinuteRange] {
        var windows: [MinuteRange] = []
        var cursor = dayStart
        for block in blocks.sorted(by: { $0.start < $1.start }) {
            if block.start > cursor { windows.append(MinuteRange(start: cursor, end: min(block.start, dayEnd))) }
            cursor = max(cursor, block.end)
        }
        if cursor < dayEnd { windows.append(MinuteRange(start: cursor, end: dayEnd)) }
        return windows.filter { $0.length >= 15 }
    }

    /// 空档总时长减去落在空档里的日历事件。
    static func availableMinutes(blocks: [SOPTimeBlock], busy: [MinuteRange]) -> Int {
        let windows = freeWindows(blocks: blocks)
        let total = windows.reduce(0) { $0 + $1.length }
        let taken = windows.reduce(0) { sum, window in
            sum + mergedOverlap(of: busy, with: window)
        }
        return max(0, total - taken)
    }

    private static func mergedOverlap(of ranges: [MinuteRange], with window: MinuteRange) -> Int {
        let clipped = ranges
            .map { MinuteRange(start: max($0.start, window.start), end: min($0.end, window.end)) }
            .filter { $0.length > 0 }
            .sorted { $0.start < $1.start }
        var total = 0
        var current: MinuteRange?
        for range in clipped {
            if var c = current, range.start <= c.end {
                c.end = max(c.end, range.end)
                current = c
            } else {
                if let c = current { total += c.length }
                current = range
            }
        }
        if let c = current { total += c.length }
        return total
    }

    /// 依次为每个时长找到最早能放下的空位（避开 SOP、日历和已排任务）。
    static func autoPlace(
        durations: [Int],
        blocks: [SOPTimeBlock],
        busy: [MinuteRange],
        notBefore: Int = dayStart
    ) -> [Int?] {
        var occupied = busy
        var result: [Int?] = []
        let windows = freeWindows(blocks: blocks)
        for duration in durations {
            var placed: Int?
            search: for window in windows where window.end > notBefore {
                var start = max(window.start, notBefore)
                start = Int((Double(start) / 15).rounded(.up)) * 15
                while start + duration <= window.end {
                    let candidate = MinuteRange(start: start, end: start + duration)
                    if let clash = occupied.first(where: { $0.overlap(with: candidate) > 0 }) {
                        start = Int((Double(clash.end) / 15).rounded(.up)) * 15
                        continue
                    }
                    placed = start
                    occupied.append(candidate)
                    break search
                }
            }
            result.append(placed)
        }
        return result
    }

    static func clock(_ minute: Int) -> String {
        let value = max(0, minute)
        if value >= 1440 { return "24:00" }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func duration(_ minutes: Int) -> String {
        let value = max(0, minutes)
        let hours = value / 60, rest = value % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h\(rest)m"
    }
}
