import Combine
import Foundation

@MainActor
final class DailySOPStore: ObservableObject {
    static let shared = DailySOPStore()

    @Published private(set) var completionByDay: [String: Set<String>] = [:]

    private let fileURL: URL
    private let persistsChanges: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, persistsChanges: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.persistsChanges = persistsChanges
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func isCompleted(_ itemID: String, on date: Date, calendar: Calendar = .current) -> Bool {
        completionByDay[dayKey(for: date, calendar: calendar)]?.contains(itemID) == true
    }

    func setCompleted(
        _ itemID: String,
        completed: Bool,
        on date: Date,
        calendar: Calendar = .current
    ) {
        let key = dayKey(for: date, calendar: calendar)
        var values = completionByDay[key] ?? []
        if completed { values.insert(itemID) }
        else { values.remove(itemID) }
        if values.isEmpty { completionByDay.removeValue(forKey: key) }
        else { completionByDay[key] = values }
        save()
    }

    func toggle(_ itemID: String, on date: Date, calendar: Calendar = .current) {
        setCompleted(
            itemID,
            completed: !isCompleted(itemID, on: date, calendar: calendar),
            on: date,
            calendar: calendar
        )
    }

    func completedCount(on date: Date, calendar: Calendar = .current) -> Int {
        completionByDay[dayKey(for: date, calendar: calendar)]?.count ?? 0
    }

    func reset(date: Date, calendar: Calendar = .current) {
        completionByDay.removeValue(forKey: dayKey(for: date, calendar: calendar))
        save()
    }

    func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private func load() {
        guard persistsChanges, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            completionByDay = try decoder.decode([String: Set<String>].self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("TomorrowPet: failed to load SOP state: %@", error.localizedDescription)
        }
    }

    private func save() {
        guard persistsChanges else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(completionByDay).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TomorrowPet: failed to save SOP state: %@", error.localizedDescription)
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("TomorrowPet", isDirectory: true)
            .appendingPathComponent("daily-sop.json")
    }
}
