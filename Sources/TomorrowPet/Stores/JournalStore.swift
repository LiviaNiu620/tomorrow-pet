import Combine
import Foundation

enum TriageChoice: String, Codable, CaseIterable, Identifiable {
    case tomorrow
    case thisWeek
    case letGo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tomorrow: "明天"
        case .thisWeek: "本周内"
        case .letGo: "放下"
        }
    }
}

struct DailyReview: Codable, Hashable {
    var energy: Int?
    var mood: Int?
    var progress: String = ""
    var blocker: String = ""
    var firstAction: String = ""
    var triage: [String: TriageChoice] = [:]
    var savedAt: Date?
}

struct FocusSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var taskID: UUID?
    var taskTitle: String
    var startedAt: Date
    var minutes: Int
}

/// 复盘与专注记录，独立于任务文件保存。
@MainActor
final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    @Published private(set) var reviews: [String: DailyReview] = [:]
    @Published private(set) var sessions: [FocusSession] = []

    private struct Persisted: Codable {
        var reviews: [String: DailyReview]
        var sessions: [FocusSession]
    }

    private let fileURL: URL
    private let persistsChanges: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, persistsChanges: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.persistsChanges = persistsChanges
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func review(on date: Date) -> DailyReview {
        reviews[Self.dayKey(date)] ?? DailyReview()
    }

    func updateReview(on date: Date, _ change: (inout DailyReview) -> Void) {
        var value = review(on: date)
        change(&value)
        reviews[Self.dayKey(date)] = value
        save()
    }

    func addSession(taskID: UUID?, taskTitle: String, startedAt: Date, minutes: Int) {
        guard minutes > 0 else { return }
        sessions.append(FocusSession(taskID: taskID, taskTitle: taskTitle, startedAt: startedAt, minutes: minutes))
        save()
    }

    func sessions(on date: Date, calendar: Calendar = .current) -> [FocusSession] {
        sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    func focusMinutes(on date: Date, calendar: Calendar = .current) -> Int {
        sessions(on: date, calendar: calendar).reduce(0) { $0 + $1.minutes }
    }

    func focusMinutes(for taskID: UUID) -> Int {
        sessions.filter { $0.taskID == taskID }.reduce(0) { $0 + $1.minutes }
    }

    private func load() {
        guard persistsChanges, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let state = try decoder.decode(Persisted.self, from: Data(contentsOf: fileURL))
            reviews = state.reviews
            sessions = state.sessions
        } catch {
            NSLog("TomorrowPet: failed to load journal: %@", error.localizedDescription)
        }
    }

    private func save() {
        guard persistsChanges else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Persisted(reviews: reviews, sessions: sessions)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TomorrowPet: failed to save journal: %@", error.localizedDescription)
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TomorrowPet", isDirectory: true).appendingPathComponent("journal.json")
    }
}
