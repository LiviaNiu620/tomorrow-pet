import SwiftUI

/// 任务库：所有任务的唯一入口，列表 / 看板两种视图，右侧即时编辑。
struct LibraryView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var router: AppRouter

    enum ViewMode: Hashable { case list, board }
    enum Filter: String, CaseIterable, Identifiable {
        case all, today, week, overdue, waiting, nodate, done, trash
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部"
            case .today: "今天"
            case .week: "本周"
            case .overdue: "逾期"
            case .waiting: "等待中"
            case .nodate: "无日期"
            case .done: "已完成"
            case .trash: "垃圾箱"
            }
        }
    }

    @State private var mode: ViewMode = .list
    @State private var filter: Filter = .all
    @State private var areaFilter: UUID?
    @State private var query = ""
    @State private var newTitle = ""
    @State private var selectedID: UUID?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DangoPageHeader(eyebrow: "所有任务都在这里 · 今天、本周只是它的不同视图", title: "任务库") {
                    DangoSegmented(selection: $mode, options: [(.list, "列表"), (.board, "看板")])
                }
                filterBar
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        addBar
                        if mode == .list { listView } else { boardView }
                    }
                    .frame(maxWidth: .infinity)
                    LibraryDetailPanel(
                        store: store,
                        sopStore: sopStore,
                        calendarService: calendarService,
                        preferences: preferences,
                        router: router,
                        taskID: selectedID
                    )
                    .frame(width: 370)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
        .onAppear(perform: consumeRouter)
        .onChange(of: router.libraryFilter) { _, _ in consumeRouter() }
        .onChange(of: router.selectedLibraryTaskID) { _, _ in consumeRouter() }
    }

    private func consumeRouter() {
        if let raw = router.libraryFilter {
            if raw.hasPrefix("area:"), let id = UUID(uuidString: String(raw.dropFirst(5))) {
                areaFilter = id
                filter = .all
            } else if let value = Filter(rawValue: raw) {
                filter = value
                areaFilter = nil
            }
            router.libraryFilter = nil
        }
        if let id = router.selectedLibraryTaskID {
            selectedID = id
            router.selectedLibraryTaskID = nil
        }
    }

    // MARK: Filtering

    private var today: Date { calendar.startOfDay(for: .now) }

    private func matches(_ task: TaskItem, _ filter: Filter) -> Bool {
        switch filter {
        case .trash: return task.status == .trashed
        case .done: return task.status == .completed
        default: break
        }
        guard task.status.isActive else { return false }
        switch filter {
        case .all: return true
        case .today: return task.isPlanned(on: today)
        case .week:
            guard let planned = task.plannedDate, let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return false }
            return week.contains(planned)
        case .overdue: return (task.dueDate.map { $0 < today } ?? false)
        case .waiting: return task.status == .waiting
        case .nodate: return task.plannedDate == nil && task.dueDate == nil
        default: return false
        }
    }

    private var shown: [TaskItem] {
        var text = query.trimmingCharacters(in: .whitespaces)
        var area = areaFilter
        if let range = text.range(of: #"#(\S+)"#, options: .regularExpression) {
            let name = String(text[range].dropFirst())
            if let match = store.areas.first(where: { $0.name == name }) {
                area = match.id
                text.removeSubrange(range)
                text = text.trimmingCharacters(in: .whitespaces)
            }
        }
        return store.tasks.filter { task in
            matches(task, filter) && (task.parentTaskID == nil || !text.isEmpty)
        }
        .filter { task in
            (area == nil || task.areaID == area)
                && (text.isEmpty
                    || task.title.localizedCaseInsensitiveContains(text)
                    || task.notes.localizedCaseInsensitiveContains(text)
                    || task.project.localizedCaseInsensitiveContains(text)
                    || task.tags.contains { $0.localizedCaseInsensitiveContains(text) })
        }
        .sorted(by: Self.sort)
    }

    private static func sort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let l = lhs.plannedDate ?? lhs.dueDate ?? .distantFuture
        let r = rhs.plannedDate ?? rhs.dueDate ?? .distantFuture
        if l != r { return l < r }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.createdAt > rhs.createdAt
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .bold))
                TextField("搜索标题、备注、项目，或 #工作", text: $query)
                    .textFieldStyle(.plain)
                    .font(Dango.font(14))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(width: 320)
            .background(Capsule().fill(Dango.paper))
            .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { item in
                        let on = filter == item
                        Button { filter = item } label: {
                            HStack(spacing: 5) {
                                Text(item.title).font(Dango.font(13, .heavy))
                                Text("\(store.tasks.filter { matches($0, item) && $0.parentTaskID == nil }.count)").font(Dango.mono(11))
                            }
                            .foregroundStyle(on ? Color.white : Dango.ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(on ? Dango.ink : Dango.paper))
                            .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if let areaFilter, let area = store.areas.first(where: { $0.id == areaFilter }) {
                        Button { self.areaFilter = nil } label: {
                            HStack(spacing: 6) {
                                Text("#\(area.name)").font(Dango.font(13, .heavy))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Dango.areaFill(area.colorName)))
                            .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(2)
            }
        }
    }

    private var addBar: some View {
        let parsed = QuickCaptureParser.parse(newTitle, areaNames: store.areas.map(\.name))
        return HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
            TextField("加到任务库：写论文引言 #工作 下周三 1h", text: $newTitle)
                .textFieldStyle(.plain)
                .font(Dango.font(14))
                .onSubmit(add)
            if parsed.hasStructure {
                Text([parsed.dayLabel, parsed.minute.map(DayPlanner.clock), parsed.duration.map(DayPlanner.duration), parsed.areaName.map { "#\($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
            }
            Button("添加", action: add).buttonStyle(.dango(.pink, small: true)).disabled(parsed.title.isEmpty)
        }
        .dangoCard(radius: 16, offset: 3, padding: 12)
    }

    private func add() {
        let parsed = QuickCaptureParser.parse(newTitle, areaNames: store.areas.map(\.name))
        var value = parsed
        if value.areaName == nil, let areaFilter { value.areaName = store.areas.first { $0.id == areaFilter }?.name }
        if let task = store.addTask(from: value, fallbackDate: filter == .today ? today : nil) {
            selectedID = task.id
            newTitle = ""
        }
    }

    // MARK: List

    private var listView: some View {
        let tasks = shown
        let groups: [(TaskArea?, [TaskItem])] = (store.areas.map { area in (Optional(area), tasks.filter { $0.areaID == area.id }) }
            + [(nil, tasks.filter { task in !store.areas.contains { $0.id == task.areaID } })])
            .filter { !$0.1.isEmpty }
        return VStack(spacing: 16) {
            if groups.isEmpty {
                VStack(spacing: 10) {
                    DangoMascot(mood: .sleepy, size: 44)
                    Text(filter == .trash ? "垃圾箱是空的" : "这里没有任务").font(Dango.font(15, .heavy))
                    if !query.isEmpty || areaFilter != nil || filter != .all {
                        Button("清除筛选") { query = ""; areaFilter = nil; filter = .all }.buttonStyle(.dango(small: true))
                    }
                }
                .frame(maxWidth: .infinity)
                .dangoCard(padding: 36)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        DangoSquareDot(fill: Dango.areaFill(group.0?.colorName), size: 14)
                        Text(group.0?.name ?? "未分类").font(Dango.font(15, .heavy))
                        Text("\(group.1.count)").font(Dango.mono(12)).foregroundStyle(Dango.muted)
                    }
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                    ForEach(group.1) { task in
                        DashedDivider()
                        LibraryRow(store: store, task: task, selected: selectedID == task.id) {
                            selectedID = task.id
                        }
                    }
                }
                .padding(.bottom, 6)
                .dangoCard(padding: 0)
            }
        }
    }

    // MARK: Board

    private static let boardStatuses: [TaskStatus] = [.inbox, .next, .planned, .inProgress, .waiting, .completed]

    private var boardView: some View {
        let tasks = shown
        let statuses = filter == .trash ? [TaskStatus.trashed] : Self.boardStatuses
        return HStack(alignment: .top, spacing: 10) {
            ForEach(statuses) { status in
                let items = (filter == .done || status != .completed)
                    ? tasks.filter { $0.status == status }
                    : store.tasks.filter { $0.status == .completed && $0.parentTaskID == nil && (areaFilter == nil || $0.areaID == areaFilter) }
                        .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                        .prefix(12).map { $0 }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(status.title).font(Dango.font(14, .heavy))
                        Spacer()
                        Text("\(items.count)").font(Dango.mono(12)).foregroundStyle(Dango.muted)
                    }
                    ForEach(items) { task in
                        boardCard(task, status: status)
                    }
                    Spacer(minLength: 40)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 16).fill(Dango.softer))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0x9AA394), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                .dropDestination(for: String.self) { values, _ in
                    guard let raw = values.first, raw.hasPrefix("task:"), let id = UUID(uuidString: String(raw.dropFirst(5))) else { return false }
                    if status == .completed { store.setCompleted(id, completed: true) }
                    else { store.mutate(id, message: "已移到\(status.title)") { $0.status = status } }
                    return true
                }
            }
        }
    }

    private func boardCard(_ task: TaskItem, status: TaskStatus) -> some View {
        let index = Self.boardStatuses.firstIndex(of: status)
        let next = index.flatMap { $0 + 1 < Self.boardStatuses.count ? Self.boardStatuses[$0 + 1] : nil }
        return VStack(alignment: .leading, spacing: 8) {
            Button { selectedID = task.id } label: {
                Text(task.title).font(Dango.font(12.5, .heavy)).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PressableStyle())
            HStack(spacing: 6) {
                Text(DayPlanner.duration(task.plannedDuration) + (task.plannedDate.map { " · " + LibraryRow.dateLabel($0) } ?? ""))
                    .font(Dango.mono(11))
                Spacer()
                if let next, status != .trashed {
                    Button("→") {
                        if next == .completed { store.setCompleted(task.id, completed: true) }
                        else { store.mutate(task.id, message: "已移到\(next.title)") { $0.status = next } }
                    }
                    .buttonStyle(.dango(small: true))
                    .help("移到\(next.title)")
                }
            }
        }
        .padding(10)
        .dangoBlock(fill: store.fill(for: task), radius: 12, shadow: 2, highlighted: selectedID == task.id)
        .draggable("task:\(task.id.uuidString)")
    }
}

// MARK: - Row

struct LibraryRow: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem
    let selected: Bool
    let select: () -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        let done = task.status == .completed
        let children = store.children(of: task.id)
        HStack(spacing: 10) {
            if task.status == .trashed {
                Image(systemName: "trash").frame(width: 20)
            } else {
                DangoCheck(done: done) { store.setCompleted(task.id, completed: !done) }
            }
            Button(action: select) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(Dango.font(14, .bold)).strikethrough(done)
                        .foregroundStyle(done ? Dango.faint : Dango.ink)
                        .multilineTextAlignment(.leading)
                    let sub = [
                        task.project.isEmpty ? nil : task.project,
                        children.isEmpty ? nil : "\(children.filter { $0.status == .completed }.count)/\(children.count) 子任务",
                        task.recurrence == nil ? nil : "重复",
                        isOverdue ? "已逾期" : nil,
                        task.status == .waiting ? "等待中" : nil
                    ].compactMap { $0 }
                    if !sub.isEmpty {
                        Text(sub.joined(separator: " · ")).font(Dango.font(12)).foregroundStyle(isOverdue ? Dango.pinkText : Dango.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            if task.status != .trashed {
                TaskDateMenu(store: store, task: task)
                TaskDurationMenu(store: store, task: task)
                TaskPriorityMenu(store: store, task: task)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(selected ? Dango.blushSoft : Color.clear)
        .draggable("task:\(task.id.uuidString)")
        .contextMenu {
            if task.status == .trashed {
                Button("恢复") { store.restoreFromTrash([task.id]) }
            } else {
                Button("今天做") { store.schedule(task.id, on: .now, minute: nil) }
                Button("设为今天 Top 3") { store.setFocus(task.id, on: .now, isFocus: true) }
                Divider()
                Button("移到垃圾箱", role: .destructive) { store.delete([task.id]) }
            }
        }
    }

    private var isOverdue: Bool {
        guard task.status.isActive, let due = task.dueDate else { return false }
        return due < calendar.startOfDay(for: .now)
    }

    static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInTomorrow(date) { return "明天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }
}

// MARK: - Inline chip menus

struct TaskDateMenu: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem
    @State private var showPicker = false

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let overdue = task.status.isActive && (task.dueDate.map { $0 < today } ?? false)
        Menu {
            Button("今天") { store.schedule(task.id, on: today, minute: nil) }
            Button("明天") { store.schedule(task.id, on: calendar.date(byAdding: .day, value: 1, to: today) ?? today, minute: nil) }
            Button("本周六") { store.schedule(task.id, on: nextWeekday(7, from: today), minute: nil) }
            Button("下周一") { store.schedule(task.id, on: nextWeekday(2, from: today), minute: nil) }
            Button("选日期…") { showPicker = true }
            Divider()
            Button("清除计划日期") { store.clearPlannedDate(task.id) }
        } label: {
            DangoChip(text: task.plannedDate.map(LibraryRow.dateLabel) ?? (overdue ? "已逾期" : "无日期"),
                      fill: overdue ? Dango.pink : (task.plannedDate.map { calendar.isDateInToday($0) } == true ? Dango.apricot : Dango.paper))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showPicker) {
            DatePicker("计划日期", selection: Binding(
                get: { task.plannedDate ?? today },
                set: { store.schedule(task.id, on: $0, minute: nil) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
        }
        .help("计划日期")
    }

    private func nextWeekday(_ weekday: Int, from date: Date) -> Date {
        let calendar = Calendar.current
        let current = calendar.component(.weekday, from: date)
        var offset = (weekday - current + 7) % 7
        if offset == 0 { offset = 7 }
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }
}

struct TaskDurationMenu: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem

    var body: some View {
        Menu {
            ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                Button(DayPlanner.duration(minutes)) {
                    store.mutate(task.id, message: "已修改时长") { $0.estimatedMinutes = minutes }
                }
            }
            Divider()
            Button("不估时") { store.mutate(task.id, message: "已修改时长") { $0.estimatedMinutes = nil } }
        } label: {
            DangoChip(text: task.estimatedMinutes.map(DayPlanner.duration) ?? "—", mono: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("预计时长")
    }
}

struct TaskPriorityMenu: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem

    var body: some View {
        Menu {
            ForEach(TaskPriority.allCases) { priority in
                Button(priority == .none ? "无优先级" : "\(priority.title)优先级") {
                    store.mutate(task.id, message: "已修改优先级") { $0.priority = priority }
                }
            }
        } label: {
            DangoChip(text: task.priority == .none ? "—" : "\(task.priority.title)优", fill: Dango.priorityFill(task.priority))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("优先级")
    }
}
