import Combine
import Foundation

@MainActor
final class DailySOPStore: ObservableObject {
    static let shared = DailySOPStore()

    @Published private(set) var completionByDay: [String: Set<String>] = [:]
    @Published private(set) var configuration: DailySOPConfiguration = DailySOPTemplate.defaultConfiguration

    private let fileURL: URL
    private let persistsChanges: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct PersistedSOPState: Codable {
        var configuration: DailySOPConfiguration
        var completionByDay: [String: Set<String>]
    }

    init(fileURL: URL? = nil, persistsChanges: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.persistsChanges = persistsChanges
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func isCompleted(_ itemID: String, on date: Date, calendar: Calendar = .current) -> Bool {
        completionByDay[dayKey(for: date, calendar: calendar)]?.contains(itemID) == true
    }

    func sections(for date: Date, calendar: Calendar = .current) -> [DailySOPSection] {
        DailySOPTemplate.sections(for: date, configuration: configuration, calendar: calendar)
    }

    func planningItems(for date: Date, calendar: Calendar = .current) -> [DailySOPItem] {
        DailySOPTemplate.planningItems(for: date, configuration: configuration, calendar: calendar)
    }

    func blocks(for date: Date, calendar: Calendar = .current) -> [SOPTimeBlock] {
        DailySOPTemplate.blocks(for: date, configuration: configuration, calendar: calendar)
    }

    var allTimeBlocks: [SOPTimeBlock] {
        configuration.timeBlocks ?? SOPTimeBlock.defaults
    }

    func updateTimeBlock(_ block: SOPTimeBlock) {
        var blocks = allTimeBlocks
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
        configuration.timeBlocks = blocks.sorted { $0.start < $1.start }
        save()
        NotificationCenter.default.post(name: .sopRemindersChanged, object: nil)
    }

    func removeTimeBlock(id: String) {
        configuration.timeBlocks = allTimeBlocks.filter { $0.id != id }
        save()
        NotificationCenter.default.post(name: .sopRemindersChanged, object: nil)
    }

    /// 某一天全部打卡项（含周日、月末追加分组）。
    func items(for date: Date, calendar: Calendar = .current) -> [DailySOPItem] {
        sections(for: date, calendar: calendar).flatMap(\.items)
    }

    func updateConfiguration(_ value: DailySOPConfiguration) {
        configuration = Self.normalized(value)
        save()
    }

    func restoreDefaultConfiguration() {
        configuration = DailySOPTemplate.defaultConfiguration
        save()
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
            let data = try Data(contentsOf: fileURL)
            if let state = try? decoder.decode(PersistedSOPState.self, from: data) {
                configuration = Self.normalized(state.configuration)
                completionByDay = state.completionByDay
            } else {
                // 兼容 1.0 仅保存每日打卡字典的格式。
                completionByDay = try decoder.decode([String: Set<String>].self, from: data)
                configuration = DailySOPTemplate.defaultConfiguration
            }
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
            let state = PersistedSOPState(
                configuration: configuration,
                completionByDay: completionByDay
            )
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TomorrowPet: failed to save SOP state: %@", error.localizedDescription)
        }
    }

    private static func normalized(_ source: DailySOPConfiguration) -> DailySOPConfiguration {
        var value = source
        var usedSectionIDs = Set<String>()
        var usedItemIDs = Set<String>()

        func normalize(_ section: inout DailySOPSection) {
            if section.id.isEmpty || !usedSectionIDs.insert(section.id).inserted {
                section.id = "section-\(UUID().uuidString)"
                usedSectionIDs.insert(section.id)
            }
            section.title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if section.title.isEmpty { section.title = "未命名分组" }
            for index in section.items.indices {
                if section.items[index].id.isEmpty || !usedItemIDs.insert(section.items[index].id).inserted {
                    section.items[index].id = "sop-\(UUID().uuidString)"
                    usedItemIDs.insert(section.items[index].id)
                }
                section.items[index].title = section.items[index].title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if section.items[index].title.isEmpty { section.items[index].title = "未命名步骤" }
                section.items[index].sectionID = section.id
                section.items[index].sectionTitle = section.title
            }
        }

        for index in value.dailySections.indices { normalize(&value.dailySections[index]) }
        normalize(&value.sundaySection)
        normalize(&value.monthlySection)
        return value
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("TomorrowPet", isDirectory: true)
            .appendingPathComponent("daily-sop.json")
    }
}
