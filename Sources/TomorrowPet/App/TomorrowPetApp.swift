import AppKit
import SwiftUI

@main
struct TomorrowPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore.shared
    @StateObject private var sopStore = DailySOPStore.shared
    @StateObject private var preferences = AppPreferences.shared
    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var googleCalendarService = GoogleCalendarService.shared
    @StateObject private var journal = JournalStore.shared
    @StateObject private var router = AppRouter.shared
    @StateObject private var focus = FocusTimer.shared

    var body: some Scene {
        WindowGroup(AppConstants.name, id: "main") {
            RootView(
                store: store,
                sopStore: sopStore,
                preferences: preferences,
                calendarService: calendarService,
                journal: journal,
                router: router,
                focus: focus
            )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("撤销任务操作") {
                    TaskStore.shared.undoLastAction()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
            }

            CommandMenu("任务") {
                Button("新建任务") {
                    NotificationCenter.default.post(name: .showQuickAdd, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("安排明天") {
                    NotificationCenter.default.post(name: .openTomorrowPlanner, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("打开习惯 · SOP") {
                    NotificationCenter.default.post(name: .openDailySOP, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("开始 / 暂停专注") {
                    FocusTimer.shared.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("今日复盘") {
                    NotificationCenter.default.post(name: .openReview, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarContentView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                preferences: preferences,
                calendarService: calendarService,
                googleCalendarService: googleCalendarService
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanelController: PetPanelController?
    private var petObserver: NSObjectProtocol?
    private var sopObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        petPanelController = PetPanelController(store: TaskStore.shared)
        if AppPreferences.shared.petEnabled {
            petPanelController?.show()
        }

        petObserver = NotificationCenter.default.addObserver(
            forName: .petVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let shouldShow = notification.object as? Bool == true
            Task { @MainActor [weak self] in
                if shouldShow {
                    self?.petPanelController?.show()
                } else {
                    self?.petPanelController?.hide()
                }
            }
        }

        _ = AppRouter.shared
        GlobalHotKey.shared.onPress = {
            AppWindowActivator.showMainWindow()
            AppRouter.shared.go(.today)
            AppRouter.shared.captureFocusRequest = UUID()
        }
        GlobalHotKey.shared.register()

        sopObserver = NotificationCenter.default.addObserver(
            forName: .sopRemindersChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await ReminderService.shared.scheduleSOPReminders(blocks: DailySOPStore.shared.allTimeBlocks)
            }
        }

        Task {
            await ReminderService.shared.configure(preferences: AppPreferences.shared)
            await ReminderService.shared.scheduleSOPReminders(blocks: DailySOPStore.shared.allTimeBlocks)
            await GoogleCalendarService.shared.restoreConnection()
            await CalendarService.shared.refreshTomorrow()
            await CalendarService.shared.refreshUpcomingWeek()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let petObserver { NotificationCenter.default.removeObserver(petObserver) }
    }
}
