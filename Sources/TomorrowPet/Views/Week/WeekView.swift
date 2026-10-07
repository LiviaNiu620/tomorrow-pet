import SwiftUI

/// 本周：三个周目标、待安排任务池、七天容量，以及周日计划清单。
struct WeekView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var router: AppRouter

    @State private var weekOffset = 0
    @State private var weekEvents: [CalendarEventSummary] = []
    @State private var selectedID: UUID?
    @State private var goalDrafts = ["", "", ""]
    @State private var showAllTray = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                goalsRow
                tray
                if let selectedID, let task = store.task(id: selectedID) {
                    HStack(spacing: 10) {
                        Text("已选中「\(task.title)」· 点某一天的「放到这天」，或直接拖过去")
                            .font(Dango.font(13, .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if task.plannedDate != nil {
                            Button("移回待安排") { store.clearPlannedDate(selectedID); self.selectedID = nil }
                                .buttonStyle(.dango(small: true))
                        }
                        Button("取消") { self.selectedID = nil }.buttonStyle(.dango(small: true))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .dangoBlock(fill: Dango.blush, radius: 12, shadow: 0)
                }
                columns
                HStack(alignment: .top, spacing: 20) {
                    sundayCard.frame(maxWidth: .infinity)
                    deadlinesCard.frame(width: 360)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
        .task(id: weekOffset) {
            weekEvents = await calendarService.fetchEvents(from: weekStart, to: calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart)
            loadGoals()
        }
    }

    // MARK: Dates

    private var today: Date { calendar.startOfDay(for: .now) }

    private var weekStart: Date {
        let weekday = calendar.component(.weekday, from: today)
        let fromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -fromMonday, to: today) ?? today
        return calendar.date(byAdding: .day, value: weekOffset * 7, to: monday) ?? monday
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekNumber: Int { calendar.component(.weekOfYear, from: weekStart.addingTimeInterval(86_400)) }

    private var header: some View {
        let end = days.last ?? weekStart
        let title = "\(weekStart.formatted(.dateTime.month(.defaultDigits).day())) – \(end.formatted(.dateTime.month(.defaultDigits).day()))"
        let planned = days.reduce(0) { sum, day in sum + store.tasks(plannedOn: day).reduce(0) { $0 + $1.plannedDuration } }
        let available = days.reduce(0) { $0 + availableMinutes(on: $1) }
        let weekTasks = days.flatMap { store.tasks(plannedOn: $0) }
        return DangoPageHeader(eyebrow: "第 \(weekNumber) 周 · 周日 \(DayPlanner.clock(AppPreferences.shared.weeklyHour * 60 + AppPreferences.shared.weeklyMinute)) 团子会提醒你做下周计划", title: title) {
            HStack(spacing: 10) {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.dango(small: true))
                Button("本周") { weekOffset = 0 }.buttonStyle(.dango(small: true)).disabled(weekOffset == 0)
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.dango(small: true))
                statPill("已排 \(DayPlanner.duration(planned)) / \(DayPlanner.duration(available))", fill: Dango.paper)
                statPill("完成 \(weekTasks.filter { $0.status == .completed }.count)/\(weekTasks.count)", fill: Dango.green)
            }
        }
    }

    private func statPill(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(Dango.font(13, .heavy))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .dangoBlock(fill: fill, radius: 14, shadow: 2)
    }

    private func availableMinutes(on day: Date) -> Int {
        let ranges = weekEvents.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .compactMap { DayPlanner.minuteRange(of: $0, on: day) }
        return DayPlanner.availableMinutes(blocks: sopStore.blocks(for: day), busy: ranges)
    }

    // MARK: Goals

    private var isPlanForThisWeek: Bool {
        guard let plan = store.currentWeeklyPlan else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: plan.weekStart), to: weekStart).day ?? 99
        return abs(days) < 7
    }

    private func loadGoals() {
        if isPlanForThisWeek, let plan = store.currentWeeklyPlan {
            goalDrafts = (0..<3).map { $0 < plan.goals.count ? plan.goals[$0] : "" }
        } else {
            goalDrafts = ["", "", ""]
        }
    }

    private func saveGoals() {
        guard weekOffset == 0 else { return }
        let plan = isPlanForThisWeek ? store.currentWeeklyPlan : nil
        let cleaned = goalDrafts.map { $0.trimmingCharacters(in: .whitespaces) }
        if let plan, plan.goals == cleaned { return }
        if plan == nil && cleaned.allSatisfy(\.isEmpty) { return }
        store.storeWeeklyPlan(
            goals: goalDrafts.map { $0.trimmingCharacters(in: .whitespaces) },
            notes: plan?.notes ?? "",
            selectedTaskIDs: plan?.selectedTaskIDs ?? [],
            referenceDate: weekStart.addingTimeInterval(86_400)
        )
    }

    private static let goalFills = [Dango.sky, Dango.lavender, Color(hex: 0xC6EBDD)]

    private var goalsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                let linked = store.tasks.filter { $0.weeklyGoalIndex == index && $0.status != .trashed && $0.status != .archived }
                let done = linked.filter { $0.status == .completed }.count
                let unplanned = linked.filter { $0.plannedDate == nil && $0.status.isActive }.count
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(Dango.font(14, .heavy))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Dango.paper))
                            .overlay(Circle().strokeBorder(Dango.ink, lineWidth: 2))
                        TextField("本周第 \(index + 1) 个结果", text: $goalDrafts[index], axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(Dango.font(16, .heavy))
                            .lineLimit(1...3)
                            .onSubmit(saveGoals)
                            .disabled(weekOffset != 0)
                    }
                    DangoProgressBar(value: linked.isEmpty ? 0 : Double(done) / Double(linked.count), fill: Dango.ink, height: 12)
                    Text(linked.isEmpty ? "右键任务 → 关联到这个目标" : "\(done)/\(linked.count) 个关联任务完成" + (unplanned > 0 ? " · \(unplanned) 个还没排进某天" : " · 全部已排"))
                        .font(Dango.font(12, .bold))
                }
                .dangoCard(fill: Self.goalFills[index], padding: 16)
            }
        }
        .onChange(of: goalDrafts) { _, _ in
            // 输入停顿后自动保存。
            Task {
                let snapshot = goalDrafts
                try? await Task.sleep(for: .milliseconds(800))
                if snapshot == goalDrafts { saveGoals() }
            }
        }
    }

    // MARK: Tray

    private var trayTasks: [TaskItem] {
        store.activeTasks
            .filter { $0.plannedDate == nil && $0.parentTaskID == nil && $0.status != .waiting }
            .sorted { lhs, rhs in
                let lg = lhs.weeklyGoalIndex ?? 9, rg = rhs.weeklyGoalIndex ?? 9
                if lg != rg { return lg < rg }
                let ld = lhs.dueDate ?? .distantFuture, rd = rhs.dueDate ?? .distantFuture
                if ld != rd { return ld < rd }
                return lhs.priority < rhs.priority
            }
    }

    private var tray: some View {
        let tasks = trayTasks
        let visible = showAllTray ? tasks : Array(tasks.prefix(12))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("待安排").font(Dango.font(16, .heavy))
                Text("没有日期的任务。点选后放到某天，或直接拖到下面的列里。").font(Dango.font(12)).foregroundStyle(Dango.muted)
                Spacer()
                if tasks.count > 12 {
                    Button(showAllTray ? "收起" : "全部 \(tasks.count) 件") { showAllTray.toggle() }.buttonStyle(.dango(small: true))
                }
            }
            if tasks.isEmpty {
                Text("全部分配到具体某天了。").font(Dango.font(13)).foregroundStyle(Dango.muted)
            }
            FlowChips(spacing: 10).callAsFunction {
                ForEach(visible) { task in
                    let selected = selectedID == task.id
                    Button { selectedID = selected ? nil : task.id } label: {
                        HStack(spacing: 8) {
                            Text(task.title).font(Dango.font(13, .heavy)).lineLimit(1)
                            Text(DayPlanner.duration(task.plannedDuration) + (task.weeklyGoalIndex.map { " · 目标\($0 + 1)" } ?? ""))
                                .font(Dango.mono(11))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .dangoBlock(fill: store.fill(for: task), radius: 999, shadow: 2, highlighted: selected)
                    }
                    .buttonStyle(PressableStyle())
                    .draggable("task:\(task.id.uuidString)")
                    .contextMenu { taskMenu(task) }
                }
            }
        }
        .dangoCard()
    }

    @ViewBuilder
    private func taskMenu(_ task: TaskItem) -> some View {
        ForEach(0..<3, id: \.self) { index in
            let title = goalDrafts[index].isEmpty ? "目标 \(index + 1)" : "目标 \(index + 1)：\(goalDrafts[index])"
            Button(task.weeklyGoalIndex == index ? "✓ \(title)" : "关联到\(title)") {
                store.mutate(task.id, message: "已关联周目标") { $0.weeklyGoalIndex = $0.weeklyGoalIndex == index ? nil : index }
            }
        }
        Divider()
        if task.plannedDate != nil {
            Button("移回待安排") { store.clearPlannedDate(task.id) }
        }
        Button("在任务库中打开") { router.selectedLibraryTaskID = task.id; router.go(.library) }
    }

    // MARK: Columns

    private var columns: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(days, id: \.self) { day in
                dayColumn(day)
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let tasks = store.tasks(plannedOn: day).filter { $0.parentTaskID == nil }
            .sorted { ($0.scheduledMinute ?? 9_999) < ($1.scheduledMinute ?? 9_999) }
        let events = weekEvents.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
        let available = availableMinutes(on: day)
        let planned = tasks.reduce(0) { $0 + $1.plannedDuration }
        let ratio = available > 0 ? Double(planned) / Double(available) : 0
        let weekday = day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
        let isSunday = calendar.component(.weekday, from: day) == 1
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "\(weekday) · 今天" : weekday).font(Dango.font(15, .heavy))
                    .foregroundStyle(isToday ? Dango.pinkText : Dango.ink)
                Text(day.formatted(.dateTime.month(.defaultDigits).day())).font(Dango.mono(12)).foregroundStyle(Dango.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                DangoProgressBar(value: max(0.03, ratio), fill: Dango.capacityFill(ratio), height: 10, track: Dango.soft)
                Text("\(DayPlanner.duration(planned)) / \(DayPlanner.duration(available))\(ratio > 0.85 ? " 偏满" : "")")
                    .font(Dango.mono(11))
                    .foregroundStyle(ratio > 0.85 ? Dango.pinkText : Dango.ink)
            }
            if isSunday {
                DangoChip(text: "周计划日", fill: Dango.lavender)
            }
            ForEach(events.prefix(4)) { event in
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(Dango.font(12, .heavy)).foregroundStyle(.white).lineLimit(2)
                    Text(event.isAllDay ? "全天" : event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(Dango.mono(11)).foregroundStyle(Color(hex: 0xD8D3CB))
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Dango.ink))
            }
            if events.count > 4 {
                Text("另有 \(events.count - 4) 个日程").font(Dango.font(11)).foregroundStyle(Dango.muted)
            }
            ForEach(tasks) { task in
                taskChip(task)
            }
            Spacer(minLength: 0)
            if selectedID != nil {
                Button {
                    if let id = selectedID { store.schedule(id, on: day, minute: nil) }
                    selectedID = nil
                } label: {
                    Text("放到这天")
                        .font(Dango.font(12, .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .dangoBlock(fill: Dango.blush, radius: 10, shadow: 0, dashed: true)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 540, alignment: .top)
        .dangoBlock(fill: isToday ? Dango.blushSoft : Dango.paper, radius: 16, shadow: 3)
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Dango.pinkDeep, lineWidth: 2.5)
            }
        }
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, raw.hasPrefix("task:"), let id = UUID(uuidString: String(raw.dropFirst(5))) else { return false }
            store.schedule(id, on: day, minute: nil)
            return true
        }
    }

    private func taskChip(_ task: TaskItem) -> some View {
        let done = task.status == .completed
        let selected = selectedID == task.id
        return HStack(alignment: .top, spacing: 8) {
            DangoCheck(done: done, size: 16) { store.setCompleted(task.id, completed: !done) }
                .padding(.top, 1)
            Button { selectedID = selected ? nil : task.id } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(Dango.font(12, .heavy)).strikethrough(done)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([task.scheduledMinute.map(DayPlanner.clock), DayPlanner.duration(task.plannedDuration), task.weeklyGoalIndex.map { "目标\($0 + 1)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(Dango.mono(10.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(8)
        .dangoBlock(fill: store.fill(for: task), radius: 10, shadow: 2, highlighted: selected)
        .opacity(done ? 0.55 : 1)
        .draggable("task:\(task.id.uuidString)")
        .contextMenu { taskMenu(task) }
    }

    // MARK: Bottom

    private var sundayCard: some View {
        let sunday = days.last ?? weekStart
        let items = sopStore.configuration.sundaySection.items
        let done = items.filter { sopStore.isCompleted($0.id, on: sunday) }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("周日计划 SOP").font(Dango.font(16, .heavy))
                Text("来自你的模板 · 周日晚上逐项完成").font(Dango.font(12)).foregroundStyle(Dango.muted)
                Spacer()
                Text("\(done)/\(items.count)").font(Dango.mono(12))
            }
            .padding(.bottom, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    let itemDone = sopStore.isCompleted(item.id, on: sunday)
                    VStack(spacing: 0) {
                        DashedDivider()
                        Button { sopStore.toggle(item.id, on: sunday) } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(itemDone ? Dango.greenDeep : Dango.paper)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Dango.ink, lineWidth: 1.5))
                                    .frame(width: 16, height: 16)
                                Text(item.title).font(Dango.font(13)).strikethrough(itemDone)
                                    .foregroundStyle(itemDone ? Dango.faint : Dango.ink)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .dangoCard()
    }

    private var deadlinesCard: some View {
        let end = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let due = store.activeTasks.filter { task in
            guard let date = task.dueDate else { return false }
            return date < end
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("未来两周的 Deadline").font(Dango.font(16, .heavy))
            if due.isEmpty {
                Text("两周内没有截止日期。").font(Dango.font(13)).foregroundStyle(Dango.muted)
            }
            ForEach(due.prefix(8)) { task in
                let overdue = (task.dueDate ?? .distantFuture) < today
                HStack(spacing: 10) {
                    Text(task.dueDate.map(LibraryRow.dateLabel) ?? "")
                        .font(Dango.mono(12))
                        .foregroundStyle(overdue ? Dango.pinkText : Dango.ink)
                        .frame(width: 52, alignment: .leading)
                    DangoSquareDot(fill: store.fill(for: task), size: 10)
                    Text(task.title).font(Dango.font(13, .bold)).lineLimit(1)
                    Spacer()
                    if task.plannedDate == nil {
                        Text("未排").font(Dango.font(11, .bold)).foregroundStyle(Dango.pinkText)
                    }
                }
            }
        }
        .dangoCard(fill: Dango.blushSoft)
    }
}
