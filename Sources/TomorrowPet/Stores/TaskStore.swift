import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    struct UndoAction: Identifiable {
        let id = UUID()
        let message: String
        fileprivate let taskSnapshot: [TaskItem]
    }

    static let shared = TaskStore()

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var areas: [TaskArea] = TaskArea.defaults
    @Published private(set) var lastAIPlan: StoredAIPlan?
    @Published private(set) var currentWeeklyPlan: WeeklyPlan?
    @Published private(set) var undoAction: UndoAction?

    private var undoStack: [UndoAction] = []
    private let maximumUndoDepth = 20

    private let fileURL: URL
    private let persistsChanges: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    struct PersistedState: Codable {
        var tasks: [TaskItem]
        var areas: [TaskArea]
        var lastAIPlan: StoredAIPlan?
        var currentWeeklyPlan: WeeklyPlan?
    }

    init(fileURL: URL? = nil, persistsChanges: Bool = true) {
        self.persistsChanges = persistsChanges
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    var activeTasks: [TaskItem] {
        tasks.filter { $0.status.isActive }
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    func task(id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    func tasks(for destination: SidebarDestination, referenceDate: Date = .now) -> [TaskItem] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate

        return tasks.filter { task in
            switch destination {
            case .planner:
                return false
            case .weekly:
                return false
            case .sop:
                return false
            case .inbox:
                return task.status == .inbox
            case .all:
                return task.status.isActive
            case .today:
                return task.status.isActive && task.isPlanned(on: referenceDate, calendar: calendar)
            case .tomorrow:
                return task.status.isActive && task.isPlanned(on: tomorrow, calendar: calendar)
            case .immediate:
                return task.status.isActive && task.effectiveHorizon(referenceDate: referenceDate, calendar: calendar) == .immediate
            case .shortTerm:
                return task.status.isActive && task.effectiveHorizon(referenceDate: referenceDate, calendar: calendar) == .shortTerm
            case .longTerm:
                return task.status.isActive && task.effectiveHorizon(referenceDate: referenceDate, calendar: calendar) == .longTerm
            case .waiting:
                return task.status == .waiting
            case .completed:
                return task.status == .completed
            case .trash:
                return task.status == .trashed
            case .area(let areaID):
                return task.status.isActive && task.areaID == areaID
            }
        }
        .sorted(by: Self.taskSort)
    }

    @discardableResult
    func addTask(
        title: String,
        areaID: UUID? = nil,
        horizon: TaskHorizon? = nil,
        plannedDate: Date? = nil,
        source: TaskSource = .manual
    ) -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        registerUndo(message: "已添加任务")
        let task = TaskItem(
            title: cleanTitle,
            areaID: areaID,
            status: plannedDate == nil ? .inbox : .planned,
            manualHorizon: horizon,
            plannedDate: plannedDate,
            source: source
        )
        tasks.insert(task, at: 0)
        save()
        return task
    }

    func update(_ task: TaskItem) {
        guard tasks.contains(where: { $0.id == task.id }) else { return }
        registerUndo(message: "已更新任务")
        applyUpdate(task)
    }

    private func applyUpdate(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = tasks[index]
        var updated = task
        if updated.status == .completed {
            updated.completedAt = updated.completedAt ?? .now
        } else {
            updated.completedAt = nil
        }
        if previous.status != .completed,
           updated.status == .completed,
           updated.recurrence != nil,
           updated.recurrenceSeriesID == nil {
            updated.recurrenceSeriesID = updated.id
        }
        tasks[index] = updated
        if previous.status != .completed && updated.status == .completed {
            createNextRecurringInstance(after: updated)
        }
        save()
    }

    func setCompleted(_ id: UUID, completed: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        registerUndo(message: completed ? "任务已完成" : "任务已恢复")
        var task = tasks[index]
        task.status = completed ? .completed : .next
        task.completedAt = completed ? .now : nil
        applyUpdate(task)
    }

    func delete(_ ids: Set<UUID>) {
        let count = tasks.lazy.filter { ids.contains($0.id) && $0.status != .trashed }.count
        guard count > 0 else { return }
        registerUndo(message: "已移到垃圾箱 \(count) 个任务")
        let now = Date.now
        for index in tasks.indices where ids.contains(tasks[index].id) && tasks[index].status != .trashed {
            tasks[index].trashedFromStatus = tasks[index].status
            tasks[index].status = .trashed
            tasks[index].deletedAt = now
        }
        save()
    }

    func restoreFromTrash(_ ids: Set<UUID>) {
        let count = tasks.lazy.filter { ids.contains($0.id) && $0.status == .trashed }.count
        guard count > 0 else { return }
        registerUndo(message: "已恢复 \(count) 个任务")
        for index in tasks.indices where ids.contains(tasks[index].id) && tasks[index].status == .trashed {
            let restoredStatus = tasks[index].trashedFromStatus ?? .inbox
            tasks[index].status = restoredStatus == .trashed ? .inbox : restoredStatus
            tasks[index].trashedFromStatus = nil
            tasks[index].deletedAt = nil
            if tasks[index].status != .completed { tasks[index].completedAt = nil }
        }
        save()
    }

    func permanentlyDelete(_ ids: Set<UUID>) {
        tasks.removeAll { ids.contains($0.id) && $0.status == .trashed }
        discardUndoHistory()
        save()
    }

    func emptyTrash() {
        tasks.removeAll { $0.status == .trashed }
        discardUndoHistory()
        save()
    }

    func undoLastAction() {
        guard let action = undoStack.popLast() else { return }
        tasks = action.taskSnapshot
        undoAction = undoStack.last
        save()
    }

    func clearUndo(id: UUID) {
        guard undoAction?.id == id else { return }
        undoAction = nil
    }

    func addArea(name: String, systemImage: String = "folder.fill", colorName: String = "teal") {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !areas.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return
        }
        areas.append(TaskArea(name: cleanName, systemImage: systemImage, colorName: colorName))
        save()
    }

    func count(for destination: SidebarDestination) -> Int {
        tasks(for: destination).count
    }

    func apply(_ suggestions: [AISuggestedTask], to date: Date, markAsFocus: Bool) {
        guard !suggestions.isEmpty else { return }
        registerUndo(message: "已应用 AI 计划")
        for suggestion in suggestions {
            if let rawID = suggestion.taskID,
               let taskID = UUID(uuidString: rawID),
               let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index].plannedDate = date
                tasks[index].focusDate = markAsFocus ? date : tasks[index].focusDate
                tasks[index].status = .planned
                if tasks[index].estimatedMinutes == nil {
                    tasks[index].estimatedMinutes = suggestion.estimatedMinutes
                }
                continue
            }

            let areaID = areas.first(where: { $0.name.caseInsensitiveCompare(suggestion.area) == .orderedSame })?.id
            var task = TaskItem(
                title: suggestion.title,
                notes: suggestion.reason,
                areaID: areaID,
                status: .planned,
                priority: Self.priority(from: suggestion.priority),
                estimatedMinutes: suggestion.estimatedMinutes,
                plannedDate: date,
                focusDate: markAsFocus ? date : nil,
                source: .openAI
            )
            task.manualHorizon = .immediate
            tasks.append(task)
        }
        save()
    }

    func store(plan: AIPlanSuggestion, for date: Date) {
        lastAIPlan = StoredAIPlan(date: date, generatedAt: .now, plan: plan)
        save()
    }

    func storeWeeklyPlan(goals: [String], notes: String, selectedTaskIDs: [UUID], referenceDate: Date = .now) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        let weekStart = calendar.date(from: components) ?? calendar.startOfDay(for: referenceDate)
        currentWeeklyPlan = WeeklyPlan(
            weekStart: weekStart,
            goals: goals,
            notes: notes,
            selectedTaskIDs: selectedTaskIDs,
            updatedAt: .now
        )
        save()
    }

    private func load() {
        guard persistsChanges, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try decoder.decode(PersistedState.self, from: data)
            tasks = state.tasks
            areas = state.areas.isEmpty ? TaskArea.defaults : state.areas
            lastAIPlan = state.lastAIPlan
            currentWeeklyPlan = state.currentWeeklyPlan
        } catch {
            NSLog("TomorrowPet: failed to load local state: %@", error.localizedDescription)
        }
    }

    private func save() {
        guard persistsChanges else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let state = PersistedState(
                tasks: tasks,
                areas: areas,
                lastAIPlan: lastAIPlan,
                currentWeeklyPlan: currentWeeklyPlan
            )
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TomorrowPet: failed to save local state: %@", error.localizedDescription)
        }
    }

    private func registerUndo(message: String) {
        let action = UndoAction(message: message, taskSnapshot: tasks)
        undoStack.append(action)
        if undoStack.count > maximumUndoDepth {
            undoStack.removeFirst(undoStack.count - maximumUndoDepth)
        }
        undoAction = action
    }

    private func discardUndoHistory() {
        undoStack = []
        undoAction = nil
    }

    private func createNextRecurringInstance(after completedTask: TaskItem, calendar: Calendar = .current) {
        guard let rule = completedTask.recurrence else { return }
        let baseDate = completedTask.plannedDate
            ?? completedTask.dueDate
            ?? calendar.startOfDay(for: completedTask.completedAt ?? .now)
        guard let nextBaseDate = rule.nextDate(after: baseDate, calendar: calendar) else { return }

        let seriesID = completedTask.recurrenceSeriesID ?? completedTask.id
        let duplicateExists = tasks.contains { existing in
            guard existing.id != completedTask.id,
                  existing.status.isActive,
                  existing.recurrenceSeriesID == seriesID else { return false }
            let existingDate = existing.plannedDate ?? existing.dueDate
            return existingDate.map { calendar.isDate($0, inSameDayAs: nextBaseDate) } == true
        }
        guard !duplicateExists else { return }

        let baseDay = calendar.startOfDay(for: baseDate)
        let nextDay = calendar.startOfDay(for: nextBaseDate)
        let dayShift = calendar.dateComponents([.day], from: baseDay, to: nextDay).day ?? 0
        func shifted(_ date: Date?) -> Date? {
            date.flatMap { calendar.date(byAdding: .day, value: dayShift, to: $0) }
        }

        var next = completedTask
        next.id = UUID()
        next.status = completedTask.plannedDate == nil ? .next : .planned
        next.plannedDate = shifted(completedTask.plannedDate)
        next.dueDate = shifted(completedTask.dueDate)
        next.reviewDate = shifted(completedTask.reviewDate)
        next.focusDate = nil
        next.completedAt = nil
        next.createdAt = .now
        next.recurrenceSeriesID = seriesID
        next.sourceEventID = nil
        tasks.insert(next, at: 0)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("TomorrowPet", isDirectory: true)
            .appendingPathComponent("task-store.json")
    }

    private static func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let lhsDate = lhs.plannedDate ?? lhs.dueDate ?? .distantFuture
        let rhsDate = rhs.plannedDate ?? rhs.dueDate ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.createdAt > rhs.createdAt
    }

    private static func priority(from value: String) -> TaskPriority {
        switch value.lowercased() {
        case "high": .high
        case "medium": .medium
        case "low": .low
        default: .none
        }
    }
}
