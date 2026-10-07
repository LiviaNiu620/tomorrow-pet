import AppKit
import Combine
import Foundation
import UserNotifications

enum AppSection: String, CaseIterable, Identifiable {
    case today, week, library, habits, review, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .week: "本周"
        case .library: "任务库"
        case .habits: "习惯 · SOP"
        case .review: "复盘"
        case .focus: "专注"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .week: "calendar"
        case .library: "list.bullet"
        case .habits: "checkmark"
        case .review: "chart.bar"
        case .focus: "timer"
        }
    }

    var shortcut: Character {
        switch self {
        case .today: "1"
        case .week: "2"
        case .library: "3"
        case .habits: "4"
        case .review: "5"
        case .focus: "6"
        }
    }
}

enum DayMode: String { case today, tomorrow }

/// 全局导航状态：侧边栏、命令面板、提醒和桌宠都通过它跳转。
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var section: AppSection = .today
    @Published var dayMode: DayMode = .today
    @Published var showPalette = false
    @Published var captureFocusRequest = UUID()
    @Published var libraryFilter: String?
    @Published var selectedLibraryTaskID: UUID?

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ action: @escaping @MainActor (AppRouter) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
            })
        }
        observe(.openTomorrowPlanner) { $0.go(.today, mode: .tomorrow) }
        observe(.openWeeklyPlanner) { $0.go(.week) }
        observe(.openDailySOP) { $0.go(.habits) }
        observe(.openFocus) { $0.go(.focus) }
        observe(.openReview) { $0.go(.review) }
        observe(.showQuickAdd) { router in
            router.go(.today)
            router.captureFocusRequest = UUID()
        }
        observe(.showCommandPalette) { $0.showPalette = true }
    }

    func go(_ section: AppSection, mode: DayMode? = nil) {
        self.section = section
        if let mode { dayMode = mode }
        showPalette = false
    }
}

/// 番茄专注计时，主窗口、桌宠和菜单栏共享同一个实例。
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var length: Int = 25
    @Published private(set) var remaining: Int = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var justFinished = false
    @Published var taskID: UUID?
    @Published var taskTitle: String = ""

    private var ticker: Task<Void, Never>?
    private var startedAt: Date?

    var hasStarted: Bool { remaining < length * 60 && remaining > 0 }
    var clockText: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    var progress: Double { 1 - Double(remaining) / Double(max(1, length * 60)) }

    func setLength(_ minutes: Int) {
        stopTicker()
        length = minutes
        remaining = minutes * 60
        isRunning = false
        justFinished = false
    }

    func choose(taskID: UUID?, title: String) {
        self.taskID = taskID
        taskTitle = title
    }

    func toggle() {
        if isRunning { pause() } else { start() }
    }

    func start() {
        if remaining == 0 { remaining = length * 60 }
        justFinished = false
        isRunning = true
        if startedAt == nil { startedAt = .now }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func pause() {
        isRunning = false
        stopTicker()
    }

    func reset() {
        stopTicker()
        isRunning = false
        remaining = length * 60
        startedAt = nil
    }

    func finishEarly() {
        complete(minutes: max(1, (length * 60 - remaining) / 60))
    }

    private func tick() {
        guard isRunning else { return }
        if remaining <= 1 {
            complete(minutes: length)
        } else {
            remaining -= 1
        }
    }

    private func complete(minutes: Int) {
        stopTicker()
        isRunning = false
        remaining = 0
        justFinished = true
        JournalStore.shared.addSession(
            taskID: taskID,
            taskTitle: taskTitle.isEmpty ? "专注" : taskTitle,
            startedAt: startedAt ?? .now,
            minutes: minutes
        )
        startedAt = nil
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = "吃掉一颗团子"
        content.body = "专注了 \(minutes) 分钟，起来走走，休息 5 分钟吧。"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus-\(UUID())", content: content, trigger: nil))
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
