import Foundation
import UserNotifications

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
            content.body = "看看明天的 Calendar，用 AI 选出最重要的三件事。"
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            AppWindowActivator.showMainWindow()
            let route = response.notification.request.content.userInfo["route"] as? String
            NotificationCenter.default.post(
                name: route == "weekly" ? .openWeeklyPlanner : .openTomorrowPlanner,
                object: nil
            )
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
