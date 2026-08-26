import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Key {
        static let dailyHour = "dailyReminderHour"
        static let dailyMinute = "dailyReminderMinute"
        static let weeklyHour = "weeklyReminderHour"
        static let weeklyMinute = "weeklyReminderMinute"
        static let openAIModel = "openAIModel"
        static let petEnabled = "petEnabled"
        static let googleClientID = "googleClientID"
        static let selectedGoogleCalendarIDs = "selectedGoogleCalendarIDs"
        static let googleCalendarSelectionConfigured = "googleCalendarSelectionConfigured"
    }

    @Published var dailyHour: Int { didSet { save() } }
    @Published var dailyMinute: Int { didSet { save() } }
    @Published var weeklyHour: Int { didSet { save() } }
    @Published var weeklyMinute: Int { didSet { save() } }
    @Published var openAIModel: String { didSet { save() } }
    @Published var petEnabled: Bool { didSet { save() } }
    @Published var googleClientID: String { didSet { save() } }
    @Published var selectedGoogleCalendarIDs: Set<String> { didSet { save() } }
    @Published var googleCalendarSelectionConfigured: Bool { didSet { save() } }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dailyHour = defaults.object(forKey: Key.dailyHour) as? Int ?? 21
        dailyMinute = defaults.object(forKey: Key.dailyMinute) as? Int ?? 30
        weeklyHour = defaults.object(forKey: Key.weeklyHour) as? Int ?? 20
        weeklyMinute = defaults.object(forKey: Key.weeklyMinute) as? Int ?? 30
        openAIModel = defaults.string(forKey: Key.openAIModel) ?? AppConstants.defaultModel
        petEnabled = defaults.object(forKey: Key.petEnabled) as? Bool ?? true
        googleClientID = defaults.string(forKey: Key.googleClientID) ?? ""
        selectedGoogleCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedGoogleCalendarIDs) ?? [])
        googleCalendarSelectionConfigured = defaults.bool(forKey: Key.googleCalendarSelectionConfigured)
        isLoading = false
    }

    var dailyTime: Date {
        date(hour: dailyHour, minute: dailyMinute)
    }

    var weeklyTime: Date {
        date(hour: weeklyHour, minute: weeklyMinute)
    }

    func setDailyTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        dailyHour = components.hour ?? 21
        dailyMinute = components.minute ?? 30
    }

    func setWeeklyTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        weeklyHour = components.hour ?? 20
        weeklyMinute = components.minute ?? 30
    }

    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(dailyHour, forKey: Key.dailyHour)
        defaults.set(dailyMinute, forKey: Key.dailyMinute)
        defaults.set(weeklyHour, forKey: Key.weeklyHour)
        defaults.set(weeklyMinute, forKey: Key.weeklyMinute)
        defaults.set(openAIModel, forKey: Key.openAIModel)
        defaults.set(petEnabled, forKey: Key.petEnabled)
        defaults.set(googleClientID, forKey: Key.googleClientID)
        defaults.set(Array(selectedGoogleCalendarIDs).sorted(), forKey: Key.selectedGoogleCalendarIDs)
        defaults.set(googleCalendarSelectionConfigured, forKey: Key.googleCalendarSelectionConfigured)
    }
}
