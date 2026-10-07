import Foundation
@preconcurrency import UserNotifications

@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()

    private let center = UNUserNotificationCenter.current()

    func configure(preferences: AppPreferences) async {
        center.delegate = self
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            try await schedule(preferences: preferences)
        } catch {
            NSLog("TomorrowPet: notification setup failed: %@", error.localizedDescription)
        }
    }

    func schedule(preferences: AppPreferences) async throws {
        let dailyIDs = (2...7).map { "tomorrow-pet-daily-\($0)" }
        let weeklyID = "tomorrow-pet-weekly-sunday"
        center.removePendingNotificationRequests(withIdentifiers: dailyIDs + [weeklyID])

        for weekday in 2...7 {
            let content = UNMutableNotificationContent()
            content.title = "团子来找你安排明天了"
            content.body = "团子已经看过明天的日历，帮你把三件重点排进空档吧。"
            content.sound = .default
            content.userInfo = ["route": "planner"]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(
                    hour: preferences.dailyHour,
                    minute: preferences.dailyMinute,
                    weekday: weekday
                ),
                repeats: true
            )
            try await center.add(UNNotificationRequest(identifier: "tomorrow-pet-daily-\(weekday)", content: content, trigger: trigger))
        }

        let weeklyContent = UNMutableNotificationContent()
        weeklyContent.title = "一起安排新的一周"
        weeklyContent.body = "先看下周日历和长期任务，再一起安排周一。"
        weeklyContent.sound = .default
        weeklyContent.userInfo = ["route": "weekly"]
        let weeklyTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(
                hour: preferences.weeklyHour,
                minute: preferences.weeklyMinute,
                weekday: 1
            ),
            repeats: true
        )
        try await center.add(UNNotificationRequest(identifier: weeklyID, content: weeklyContent, trigger: weeklyTrigger))
    }

    /// 为开启“到点提醒”的 SOP 时段安排每日通知。
    func scheduleSOPReminders(blocks: [SOPTimeBlock]) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("tomorrow-pet-sop-") })
        for block in blocks where block.remind && block.start < 24 * 60 {
            let content = UNMutableNotificationContent()
            content.title = "团子：\(block.title)"
            content.body = "\(DayPlanner.clock(block.start))–\(DayPlanner.clock(block.end)) 的节奏开始了。"
            content.sound = .default
            content.userInfo = ["route": "today"]
            var components = DateComponents(hour: block.start / 60, minute: block.start % 60)
            switch block.scope {
            case .everyday: break
            case .sunday: components.weekday = 1
            case .monthEnd: continue
            }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "tomorrow-pet-sop-\(block.id)", content: content, trigger: trigger))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = response.notification.request.content.userInfo["route"] as? String
        Task { @MainActor in
            AppWindowActivator.showMainWindow()
            switch route {
            case "weekly": NotificationCenter.default.post(name: .openWeeklyPlanner, object: nil)
            case "today": AppRouter.shared.go(.today, mode: .today)
            default: NotificationCenter.default.post(name: .openTomorrowPlanner, object: nil)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
