import Combine
import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService(googleService: .shared)

    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var tomorrowEvents: [CalendarEventSummary] = []
    @Published private(set) var upcomingWeekEvents: [CalendarEventSummary] = []
    @Published private(set) var upcomingPlanningEvents: [CalendarEventSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSuccessfulSyncAt: Date?
    @Published var errorMessage: String?

    private let eventStore = EKEventStore()
    private let googleService: GoogleCalendarService

    init(googleService: GoogleCalendarService) {
        self.googleService = googleService
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var hasAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var hasAnyCalendarAccess: Bool {
        hasAccess || googleService.isConnected
    }

    var sourceSummary: String {
        switch (hasAccess, googleService.isConnected) {
        case (true, true): "Apple + Google Calendar"
        case (true, false): "Apple Calendar"
        case (false, true): "Google Calendar"
        case (false, false): "尚未连接日历"
        }
    }

    func requestAppleAccessAndRefresh(referenceDate: Date = .now) async {
        do {
            if !hasAccess {
                _ = try await eventStore.requestFullAccessToEvents()
                authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            }
            guard hasAccess else {
                errorMessage = "尚未获得 Apple Calendar 读取权限。"
                return
            }
            await refreshTomorrow(referenceDate: referenceDate)
            await refreshUpcomingWeek(referenceDate: referenceDate)
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            errorMessage = "Apple Calendar 授权失败：\(error.localizedDescription)"
        }
    }

    // 保留旧调用名，避免菜单或旧视图在迁移期间失效。
    func requestAccessAndLoadTomorrow() async {
        await requestAppleAccessAndRefresh()
    }

    func refreshTomorrow(referenceDate: Date = .now) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        guard let start = calendar.date(byAdding: .day, value: 1, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        isLoading = true
        defer { isLoading = false }
        let result = await loadEvents(from: start, to: end)
        tomorrowEvents = result.events
        errorMessage = result.errorMessage
        if hasAnyCalendarAccess { lastSuccessfulSyncAt = .now }
    }

    func refreshUpcomingWeek(referenceDate: Date = .now) async {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }

        isLoading = true
        defer { isLoading = false }
        let result = await loadEvents(from: start, to: end)
        upcomingWeekEvents = result.events
        errorMessage = result.errorMessage
        if hasAnyCalendarAccess { lastSuccessfulSyncAt = .now }
    }

    func refreshPlanningHorizon(referenceDate: Date = .now, days: Int = 14) async {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: max(1, days), to: start) else { return }

        isLoading = true
        defer { isLoading = false }
        let result = await loadEvents(from: start, to: end)
        upcomingPlanningEvents = result.events
        errorMessage = result.errorMessage
        if hasAnyCalendarAccess { lastSuccessfulSyncAt = .now }
    }

    /// 读取任意时间段的合并事件（不改变已发布的状态），供时间轴和周视图使用。
    func fetchEvents(from start: Date, to end: Date) async -> [CalendarEventSummary] {
        await loadEvents(from: start, to: end).events
    }

    // 同步包装保留给现有代码；Google 数据由异步 refresh 方法合并。
    func loadTomorrow(referenceDate: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        guard let start = calendar.date(byAdding: .day, value: 1, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        tomorrowEvents = Self.mergeEvents(apple: appleEvents(from: start, to: end), google: [])
    }

    func loadUpcomingWeek(referenceDate: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        upcomingWeekEvents = Self.mergeEvents(apple: appleEvents(from: start, to: end), google: [])
    }

    private func loadEvents(from start: Date, to end: Date) async -> (events: [CalendarEventSummary], errorMessage: String?) {
        let apple = appleEvents(from: start, to: end)
        var google: [CalendarEventSummary] = []
        var errors: [String] = []

        if googleService.isConnected {
            do {
                google = try await googleService.events(from: start, to: end)
            } catch {
                errors.append("Google Calendar 同步失败：\(error.localizedDescription)")
            }
        }

        if !hasAccess && !googleService.isConnected {
            errors.append("尚未连接日历；任务规划仍可使用。")
        }

        return (Self.mergeEvents(apple: apple, google: google), errors.isEmpty ? nil : errors.joined(separator: "\n"))
    }

    private func appleEvents(from start: Date, to end: Date) -> [CalendarEventSummary] {
        guard hasAccess else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).map {
            CalendarEventSummary(
                id: "apple:\($0.eventIdentifier ?? UUID().uuidString)",
                title: $0.title.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名事件",
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay,
                calendarTitle: $0.calendar.title,
                source: .apple
            )
        }
    }

    static func mergeEvents(
        apple: [CalendarEventSummary],
        google: [CalendarEventSummary]
    ) -> [CalendarEventSummary] {
        var seen = Set<String>()
        var result: [CalendarEventSummary] = []

        // Apple Calendar 可能已经同步了 Google；先保留本机条目，再跳过 API 重复项。
        for event in apple + google {
            let normalizedTitle = event.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let key = [
                normalizedTitle,
                String(Int64((event.startDate.timeIntervalSince1970 * 1_000).rounded())),
                String(Int64((event.endDate.timeIntervalSince1970 * 1_000).rounded())),
                event.isAllDay ? "all-day" : "timed"
            ].joined(separator: "|")
            if seen.insert(key).inserted { result.append(event) }
        }
        return result.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}
