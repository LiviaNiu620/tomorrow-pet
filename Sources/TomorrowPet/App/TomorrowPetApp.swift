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

    var body: some Scene {
        WindowGroup(AppConstants.name, id: "main") {
            ContentView(
                store: store,
                sopStore: sopStore,
                preferences: preferences,
                calendarService: calendarService
            )
            .tint(AppTheme.accent)
        }
        .defaultSize(width: 1180, height: 760)
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

                Button("打开每日 SOP") {
                    NotificationCenter.default.post(name: .openDailySOP, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(AppConstants.name, systemImage: "dog.fill") {
            MenuBarContentView()
        }

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
            Task { @MainActor in
                if notification.object as? Bool == true {
                    self?.petPanelController?.show()
                } else {
                    self?.petPanelController?.hide()
                }
            }
        }

        Task {
            await ReminderService.shared.configure(preferences: AppPreferences.shared)
            await GoogleCalendarService.shared.restoreConnection()
            await CalendarService.shared.refreshTomorrow()
            await CalendarService.shared.refreshUpcomingWeek()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let petObserver { NotificationCenter.default.removeObserver(petObserver) }
    }
}
