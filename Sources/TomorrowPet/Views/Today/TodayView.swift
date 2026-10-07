import AppKit
import SwiftUI

/// 「今天 / 明天」：日历、SOP 节奏和任务排在同一条时间轴上。
struct TodayView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var journal: JournalStore
    @ObservedObject var router: AppRouter
    @ObservedObject var focus: FocusTimer

    @State private var now = Date()
    @State private var dayEvents: [CalendarEventSummary] = []
    @State private var selection: TimelineSelection?
    @State private var capture = ""
    @State private var toast: String?
    @State private var openSections: Set<String> = []
    @State private var ghostStatus: [UUID: GhostStatus] = [:]
    @State private var ghostOverrides: [UUID: Int] = [:]
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @AppStorage("tomorrowPlannerAdditionalInput") private var additionalInput = ""
    @FocusState private var captureFocused: Bool

    private let calendar = Calendar.current
    private let planningService = OpenAIPlanningService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                captureBar
                if let toast {
                    Text(toast)
                        .font(Dango.font(13, .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dangoBlock(fill: Dango.green, radius: 12, shadow: 0)
                        .transition(.opacity)
                }
                HStack(alignment: .top, spacing: 20) {
                    timelineCard
                        .frame(minWidth: 520, maxWidth: .infinity)
                    sideColumn
                        .frame(width: 340)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
        .scrollContentBackground(.hidden)
        .task(id: router.dayMode) { await loadEvents() }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: router.captureFocusRequest) { _, _ in captureFocused = true }
        .onChange(of: router.dayMode) { _, _ in selection = nil }
        .alert("没能生成草稿", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Derived data

    private var isToday: Bool { router.dayMode == .today }
    private var today: Date { calendar.startOfDay(for: now) }
    private var day: Date { isToday ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today) }
    private var nowMinute: Int { calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now) }
    private var blocks: [SOPTimeBlock] { sopStore.blocks(for: day) }
    private var dayTasks: [TaskItem] { store.tasks(plannedOn: day) }
    private var scheduledTasks: [TaskItem] { dayTasks.filter { $0.scheduledMinute != nil } }
    private var looseTasks: [TaskItem] {
        dayTasks.filter { $0.scheduledMinute == nil && $0.status.isActive }
            .sorted { $0.priority < $1.priority }
    }
    private var eventRanges: [MinuteRange] { dayEvents.compactMap { DayPlanner.minuteRange(of: $0, on: day) } }
    private var allDayEvents: [CalendarEventSummary] { dayEvents.filter(\.isAllDay) }
    private var available: Int { DayPlanner.availableMinutes(blocks: blocks, busy: eventRanges) }
    private var plannedMinutes: Int {
        scheduledTasks.reduce(0) { $0 + $1.plannedDuration }
    }

    private var plan: AIPlanSuggestion? {
        guard !isToday, let stored = store.lastAIPlan, calendar.isDate(stored.date, inSameDayAs: day) else { return nil }
        return stored.plan
    }

    private var topSuggestionIDs: Set<UUID> { Set(plan?.topThree.map(\.id) ?? []) }

    /// 尚未处理的 AI 建议及其在时间轴上的位置。
    private var ghosts: [GhostPlacement] {
        guard let plan else { return [] }
        let alreadyScheduled = Set(scheduledTasks.map { $0.id.uuidString })
        let pending = (plan.topThree + plan.additionalTasks).filter { suggestion in
            (ghostStatus[suggestion.id] ?? .pending) == .pending
                && !(suggestion.taskID.map { alreadyScheduled.contains($0) } ?? false)
        }
        var busy = eventRanges + scheduledTasks.compactMap { task in
            task.scheduledMinute.map { MinuteRange(start: $0, end: $0 + task.plannedDuration) }
        }
        var result: [GhostPlacement] = []
        for suggestion in pending {
            if let minute = ghostOverrides[suggestion.id] {
                let duration = max(15, suggestion.estimatedMinutes)
                busy.append(MinuteRange(start: minute, end: minute + duration))
                result.append(GhostPlacement(suggestion: suggestion, minute: minute))
            }
        }
        let auto = pending.filter { ghostOverrides[$0.id] == nil }
        let minutes = DayPlanner.autoPlace(
            durations: auto.map { max(15, $0.estimatedMinutes) },
            blocks: blocks,
            busy: busy,
            notBefore: 9 * 60
        )
        for (suggestion, minute) in zip(auto, minutes) {
            result.append(GhostPlacement(suggestion: suggestion, minute: minute))
        }
        return result
    }

    // MARK: Header

    private var header: some View {
        DangoPageHeader(eyebrow: eyebrow, title: titleText) {
            HStack(alignment: .bottom, spacing: 18) {
                DangoSegmented(selection: $router.dayMode, options: [(.today, "今天"), (.tomorrow, "明天 · 规划")])
                capacityMeter.frame(width: 230)
                Button { router.showPalette = true } label: {
                    HStack(spacing: 6) {
                        Text("⌘K").font(Dango.mono(12))
                        Text("命令")
                    }
                }
                .buttonStyle(.dango(.ink))
            }
        }
    }

    private var eyebrow: String {
        let weekday = day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
        let week = calendar.component(.weekOfYear, from: day)
        return isToday ? "\(weekday) · 第 \(week) 周" : "\(weekday) · 晚间规划"
    }

    private var titleText: String {
        let date = day.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
        return isToday ? "\(date)，今天" : "\(date)，明天"
    }

    private var capacityMeter: some View {
        let ratio = available > 0 ? Double(plannedMinutes) / Double(available) : 0
        let pending = ghosts.reduce(0) { $0 + max(15, $1.suggestion.estimatedMinutes) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已排 ").font(Dango.font(12, .bold))
                    + Text(DayPlanner.duration(plannedMinutes)).font(Dango.mono(12))
                    + Text(" / 可用 ").font(Dango.font(12, .bold))
                    + Text(DayPlanner.duration(available)).font(Dango.mono(12))
                Spacer()
                Text(ratio > 0.85 ? "太满了" : (pending > 0 ? "+\(DayPlanner.duration(pending)) 待定" : "弹性 \(max(0, Int((1 - ratio) * 100)))%"))
                    .font(Dango.font(12, .bold))
                    .foregroundStyle(ratio > 0.85 ? Dango.pinkText : Dango.muted)
            }
            DangoProgressBar(value: max(0.03, ratio), fill: Dango.capacityFill(ratio), height: 14)
        }
        .foregroundStyle(Dango.ink)
    }

    // MARK: Capture

    private var parsed: ParsedCapture {
        QuickCaptureParser.parse(capture, areaNames: store.areas.map(\.name), referenceDate: now)
    }

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("随手记").font(Dango.font(13, .heavy))
                TextField("明天下午3点 写 CEUS 摘要 #工作 45m !高", text: $capture)
                    .textFieldStyle(.plain)
                    .font(Dango.font(15))
                    .focused($captureFocused)
                    .onSubmit(addCapture)
                Button("添加 ↵", action: addCapture)
                    .buttonStyle(.dango(.pink))
                    .disabled(parsed.title.isEmpty)
            }
            if !capture.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    Text("团子听懂了").font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
                    if !parsed.title.isEmpty { DangoChip(text: "「\(parsed.title)」") }
                    if let label = parsed.dayLabel { DangoChip(text: label, fill: Dango.apricot) }
                    if let minute = parsed.minute { DangoChip(text: DayPlanner.clock(minute), fill: Dango.apricot, mono: true) }
                    if let duration = parsed.duration { DangoChip(text: DayPlanner.duration(duration), fill: Color(hex: 0xE2EFBE), mono: true) }
                    if let area = parsed.areaName {
                        DangoChip(text: "#\(area)", fill: Dango.areaFill(store.areas.first { $0.name == area }?.colorName))
                    }
                    if let tag = parsed.unknownTag { DangoChip(text: "#\(tag)（标签）") }
                    if let priority = parsed.priority { DangoChip(text: "\(priority.title)优先级", fill: Dango.priorityFill(priority)) }
                }
            }
        }
        .dangoCard(padding: 14)
    }

    private func addCapture() {
        let value = parsed
        guard !value.title.isEmpty else { return }
        let fallback = day
        guard let task = store.addTask(from: value, fallbackDate: fallback) else { return }
        capture = ""
        let target = task.plannedDate.map { calendar.isDate($0, inSameDayAs: today) ? "今天" : (calendar.isDate($0, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today) ?? today) ? "明天" : $0.formatted(.dateTime.month().day())) } ?? "收件箱"
        let time = task.scheduledMinute.map { " \(DayPlanner.clock($0))" } ?? (task.plannedDate == nil ? "" : "的「未排时间」")
        showToast("已加入\(target)\(time) · ⌘Z 撤销")
        if let date = task.plannedDate, !calendar.isDate(date, inSameDayAs: day) {
            if calendar.isDate(date, inSameDayAs: today) { router.dayMode = .today }
            else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today) ?? today) { router.dayMode = .tomorrow }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if toast == text { toast = nil } }
        }
    }

    // MARK: Timeline

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            legend
            if !allDayEvents.isEmpty {
                HStack(spacing: 8) {
                    Text("全天").font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
                    ForEach(allDayEvents) { event in
                        Text(event.title)
                            .font(Dango.font(12, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Dango.ink))
                    }
                }
            }
            if let selection {
                selectionBanner(selection)
            }
            TimelineCanvas(
                blocks: blocks,
                events: dayEvents.filter { !$0.isAllDay },
                day: day,
                tasks: scheduledTasks,
                ghosts: ghosts,
                topSuggestionIDs: topSuggestionIDs,
                nowMinute: isToday ? nowMinute : nil,
                sopDone: { id in sopStore.isCompleted(id, on: day) },
                sopItems: sopStore.items(for: day),
                selection: $selection,
                store: store,
                place: place,
                dropTask: { id, minute in store.schedule(id, on: day, minute: minute) },
                acceptGhost: accept,
                rejectGhost: { ghostStatus[$0.id] = .rejected; if selection == .ghost($0.id) { selection = nil } },
                startFocus: startFocus
            )
            Text(calendarService.hasAnyCalendarAccess ? "日历：\(calendarService.sourceSummary) · SOP 时段可在「习惯 · SOP」里调整" : "还没连接日历，时间轴只显示 SOP 和任务。可以在设置里连接 Apple / Google Calendar。")
                .font(Dango.font(12))
                .foregroundStyle(Dango.muted)
        }
        .dangoCard(padding: 16)
    }

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem("日历（固定）") { RoundedRectangle(cornerRadius: 4).fill(Dango.ink) }
            legendItem("任务") { RoundedRectangle(cornerRadius: 4).fill(Dango.sky).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Dango.ink, lineWidth: 2)) }
            legendItem("SOP 节奏") { RoundedRectangle(cornerRadius: 4).fill(SOPStripes()) }
            if !isToday {
                legendItem("AI 草稿") { RoundedRectangle(cornerRadius: 4).strokeBorder(Dango.ink, style: StrokeStyle(lineWidth: 2, dash: [3, 2])) }
            }
            Spacer()
            Text(selection == nil ? "空白处可安排 · 可拖入" : "点空白处放置")
                .font(Dango.font(12, .bold))
                .foregroundStyle(Dango.muted)
        }
    }

    private func legendItem<S: View>(_ text: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 6) {
            swatch().frame(width: 14, height: 14)
            Text(text).font(Dango.font(12, .bold))
        }
    }

    private func selectionBanner(_ selection: TimelineSelection) -> some View {
        let title: String
        var scheduled = false
        switch selection {
        case .task(let id):
            let task = store.task(id: id)
            title = task?.title ?? ""
            scheduled = task?.scheduledMinute != nil
        case .ghost(let id):
            title = plan.flatMap { ($0.topThree + $0.additionalTasks).first { $0.id == id }?.title } ?? ""
        }
        return HStack(spacing: 10) {
            Text("已选中「\(title)」· 点时间轴上的空位放置")
                .font(Dango.font(13, .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if scheduled, case .task(let id) = selection {
                Button("移出时间轴") { store.unschedule(id); self.selection = nil }
                    .buttonStyle(.dango(small: true))
            }
            Button("取消") { self.selection = nil }
                .buttonStyle(.dango(small: true))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .dangoBlock(fill: Dango.blush, radius: 12, shadow: 0)
    }

    private func place(_ minute: Int) {
        guard let selection else { return }
        switch selection {
        case .task(let id):
            store.schedule(id, on: day, minute: minute)
        case .ghost(let id):
            ghostOverrides[id] = minute
        }
        self.selection = nil
    }

    private func accept(_ ghost: GhostPlacement) {
        let suggestion = ghost.suggestion
        var minutes: [UUID: Int] = [:]
        if let minute = ghost.minute { minutes[suggestion.id] = minute }
        store.apply([suggestion], to: day, markAsFocus: topSuggestionIDs.contains(suggestion.id), scheduledMinutes: minutes)
        ghostStatus[suggestion.id] = .accepted
        if selection == .ghost(suggestion.id) { selection = nil }
    }

    private func acceptAll() {
        for ghost in ghosts { accept(ghost) }
        showToast("明天的计划已保存 · 团子会在开工前提醒你 Top 1")
    }

    private func startFocus(_ task: TaskItem) {
        focus.choose(taskID: task.id, title: task.title)
        if !focus.isRunning { focus.start() }
        router.go(.focus)
    }

    private func loadEvents() async {
        let start = day
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        dayEvents = await calendarService.fetchEvents(from: start, to: end)
    }

    // MARK: Side column

    private var sideColumn: some View {
        VStack(spacing: 18) {
            if isToday { nowCard } else { aiCard }
            topCard
            looseCard
            if isToday { sopCard }
        }
    }

    private var nowCard: some View {
        let band = blocks.first { nowMinute >= $0.start && nowMinute < $0.end }
        let event = dayEvents.first { event in
            DayPlanner.minuteRange(of: event, on: day).map { nowMinute >= $0.start && nowMinute < $0.end } ?? false
        }
        let current = scheduledTasks.first { task in
            guard let start = task.scheduledMinute, task.status.isActive else { return false }
            return nowMinute >= start && nowMinute < start + task.plannedDuration
        }
        let items = sopStore.items(for: day)
        let next = items.compactMap { item -> (DailySOPItem, Int)? in
            guard let start = DailySOPTemplate.startMinute(of: item.time), start > nowMinute else { return nil }
            return (item, start)
        }.min { $0.1 < $1.1 }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("此刻 \(DayPlanner.clock(nowMinute))").font(Dango.mono(12)).foregroundStyle(Dango.pinkLight)
                Spacer()
                Text(band != nil ? "SOP 时段" : (event != nil ? "日历" : (current != nil ? "专注时段" : "空档")))
                    .font(Dango.font(12, .bold)).foregroundStyle(Dango.sidebarMuted)
            }
            if let band {
                Text(band.title).font(Dango.font(19, .heavy)).foregroundStyle(.white)
                let bandItems = items.filter { item in
                    DailySOPTemplate.startMinute(of: item.time).map { $0 >= band.start && $0 < band.end } ?? false
                }
                ForEach(bandItems.prefix(4)) { item in
                    let done = sopStore.isCompleted(item.id, on: day)
                    Button { sopStore.toggle(item.id, on: day) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(done ? Dango.greenDeep : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Dango.sidebarText, lineWidth: 2))
                                .frame(width: 16, height: 16)
                            Text(item.title)
                                .font(Dango.font(13, .semibold))
                                .strikethrough(done)
                                .foregroundStyle(done ? Dango.sidebarMuted : .white)
                            Spacer()
                            Text(item.time ?? "").font(Dango.mono(11)).foregroundStyle(Dango.sidebarMuted)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Dango.ink2))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Dango.ink3, lineWidth: 1.5))
                    }
                    .buttonStyle(PressableStyle())
                }
            } else if let event {
                Text("\(event.title)，到 \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(Dango.font(19, .heavy)).foregroundStyle(.white)
            } else if let current {
                Text(current.title).font(Dango.font(19, .heavy)).foregroundStyle(.white)
                Button(focus.isRunning && focus.taskID == current.id ? "专注中 · \(focus.clockText) →" : "开始专注 \(focus.length) 分钟 →") {
                    startFocus(current)
                }
                .buttonStyle(.dango(.pink, fullWidth: true))
            } else {
                Text(looseTasks.isEmpty ? "现在是空档，休息一下也很好。" : "现在有空档，从「未排时间」里挑一件放进来。")
                    .font(Dango.font(17, .heavy)).foregroundStyle(.white)
            }
            DashedDivider(color: Dango.ink3)
            Text(next.map { "接下来 · \(DayPlanner.clock($0.1)) \($0.0.title)（\(DayPlanner.duration($0.1 - nowMinute)) 后）" } ?? "今天的 SOP 已经走完")
                .font(Dango.font(12)).foregroundStyle(Dango.sidebarText)
        }
        .dangoCard(fill: Dango.ink, shadow: Dango.pink)
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                DangoTag(text: "AI")
                Text("团子的明日草稿").font(Dango.font(16, .heavy))
                Spacer()
                if plan != nil {
                    Text("待定 \(ghosts.count)").font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
                }
            }
            if let plan {
                Text(plan.summary).font(Dango.font(13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                Text(plan.workloadAssessment)
                    .font(Dango.font(12, .bold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dangoBlock(fill: Dango.soft, radius: 12, shadow: 0, dashed: true)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("团子会看明天的日历、SOP 节奏、本周目标和任务库，挑出三件重点，并直接排进空档。草稿需要你逐条接受。")
                    .font(Dango.font(13)).foregroundStyle(Dango.muted).fixedSize(horizontal: false, vertical: true)
            }
            DangoTextArea(placeholder: "日历之外还有什么？一行一件，比如：\n给导师回实验进度", text: $additionalInput, minHeight: 64)
            HStack(spacing: 10) {
                Button(isGenerating ? "正在规划…" : (plan == nil ? "生成明日草稿" : "重新生成")) { generate() }
                    .buttonStyle(.dango(plan == nil ? .pink : .plain, fullWidth: true))
                    .disabled(isGenerating)
                if !ghosts.isEmpty {
                    Button("全部接受", action: acceptAll)
                        .buttonStyle(.dango(.pink, fullWidth: true))
                }
            }
        }
        .dangoCard(shadow: Dango.pink)
    }

    private func generate() {
        isGenerating = true
        Task {
            do {
                let events = await calendarService.fetchEvents(from: day, to: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
                let items = try OpenAIPlanningService.additionalInputItems(from: additionalInput)
                let result = try await planningService.createTomorrowPlan(
                    apiKey: KeychainService.readAPIKey(),
                    model: preferences.openAIModel,
                    tomorrow: day,
                    tasks: store.activeTasks,
                    areas: store.areas,
                    events: events,
                    weeklyPlan: store.currentWeeklyPlan,
                    sopItems: sopStore.planningItems(for: day),
                    userInputItems: items
                )
                store.store(plan: result, for: day)
                ghostStatus = [:]
                ghostOverrides = [:]
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private var topCard: some View {
        let focusTasks = Array(store.focusTasks(on: day).prefix(3))
        let pendingTop = isToday ? [] : ghosts.filter { topSuggestionIDs.contains($0.suggestion.id) }
        let doneCount = focusTasks.filter { $0.status == .completed }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isToday ? "今天的 Top 3" : "明天的 Top 3").font(Dango.font(16, .heavy))
                Spacer()
                Text(focusTasks.isEmpty ? "" : "\(doneCount)/\(focusTasks.count) 完成")
                    .font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
            }
            .padding(.bottom, 8)
            ForEach(Array(focusTasks.enumerated()), id: \.element.id) { index, task in
                DashedDivider()
                topRow(index: index + 1, title: task.title, fill: store.fill(for: task), done: task.status == .completed,
                       meta: topMeta(task),
                       metaColor: task.scheduledMinute == nil && task.status.isActive ? Dango.pinkText : Dango.muted)
                    .contextMenu { Button("移出 Top 3") { store.setFocus(task.id, on: day, isFocus: false) } }
            }
            ForEach(Array(pendingTop.prefix(max(0, 3 - focusTasks.count)).enumerated()), id: \.element.id) { index, ghost in
                DashedDivider()
                topRow(index: focusTasks.count + index + 1, title: ghost.suggestion.title, fill: Dango.paper, done: false,
                       meta: (ghost.minute.map { DayPlanner.clock($0) + " · " } ?? "") + "AI 建议 · 待确认", metaColor: Dango.muted)
            }
            if focusTasks.isEmpty && pendingTop.isEmpty {
                DashedDivider()
                Text("右键任务 → 设为 Top 3。每天最多三件，给最重要的事留时间。")
                    .font(Dango.font(12)).foregroundStyle(Dango.muted)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dangoCard()
    }

    private func topMeta(_ task: TaskItem) -> String {
        if task.status == .completed { return "已完成" }
        if let minute = task.scheduledMinute {
            return "\(DayPlanner.clock(minute)) 开始 · \(DayPlanner.duration(task.plannedDuration))"
        }
        let postponed = task.postponeCount ?? 0
        return postponed > 0 ? "还没排时间 · 已顺延 \(postponed) 次" : "还没排时间"
    }

    private func topRow(index: Int, title: String, fill: Color, done: Bool, meta: String, metaColor: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(Dango.font(13, .heavy))
                .frame(width: 26, height: 26)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(Dango.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Dango.font(13, .heavy)).strikethrough(done).fixedSize(horizontal: false, vertical: true)
                Text(meta).font(Dango.font(12, .bold)).foregroundStyle(metaColor)
            }
        }
        .padding(.vertical, 9)
    }

    private var looseCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("未排时间").font(Dango.font(16, .heavy))
                Spacer()
                Text("选中或拖到时间轴").font(Dango.font(12)).foregroundStyle(Dango.muted)
            }
            .padding(.bottom, 6)
            if looseTasks.isEmpty {
                Text(dayTasks.isEmpty ? "这一天还没有任务。用上面的「随手记」加一件，或去任务库挑。" : "全部排进时间轴了。")
                    .font(Dango.font(13)).foregroundStyle(Dango.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("去任务库挑") { router.libraryFilter = "nodate"; router.go(.library) }
                    .buttonStyle(.dango(small: true))
                    .padding(.top, 6)
            }
            ForEach(looseTasks) { task in
                let selected = selection == .task(task.id)
                Button { selection = selected ? nil : .task(task.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        DangoSquareDot(fill: store.fill(for: task)).padding(.top, 3)
                        Text(task.title).font(Dango.font(13, .bold)).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(DayPlanner.duration(task.plannedDuration)).font(Dango.mono(12)).foregroundStyle(Dango.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Dango.blush : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Dango.ink : Color.clear, lineWidth: 2))
                }
                .buttonStyle(PressableStyle())
                .draggable("task:\(task.id.uuidString)")
                .contextMenu { taskMenu(task) }
            }
        }
        .dangoCard()
    }

    @ViewBuilder
    private func taskMenu(_ task: TaskItem) -> some View {
        let isFocus = task.focusDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        Button(isFocus ? "移出 Top 3" : "设为 Top 3") { store.setFocus(task.id, on: day, isFocus: !isFocus) }
        Button("开始专注") { startFocus(task) }
        Button("顺延到明天") { store.postpone(task.id, to: calendar.date(byAdding: .day, value: 1, to: day) ?? day) }
        Button("在任务库中编辑") { router.selectedLibraryTaskID = task.id; router.go(.library) }
    }

    private var sopCard: some View {
        let sections = sopStore.sections(for: day)
        let all = sections.flatMap(\.items)
        let done = all.filter { sopStore.isCompleted($0.id, on: day) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                DangoRing(progress: all.isEmpty ? 0 : Double(done) / Double(all.count), color: Dango.greenDeep, lineWidth: 7)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日 SOP").font(Dango.font(16, .heavy))
                    Text("\(done)/\(all.count) 项 · 点分组展开打卡").font(Dango.font(12)).foregroundStyle(Dango.muted)
                }
                Spacer()
                Button("编辑") { router.go(.habits) }.buttonStyle(.dango(small: true))
            }
            .padding(.bottom, 6)
            ForEach(sections) { section in
                let sectionDone = section.items.filter { sopStore.isCompleted($0.id, on: day) }.count
                let open = openSections.contains(section.id)
                DashedDivider()
                Button {
                    if open { openSections.remove(section.id) } else { openSections.insert(section.id) }
                } label: {
                    HStack(spacing: 10) {
                        Text(section.title).font(Dango.font(13, .heavy)).frame(maxWidth: .infinity, alignment: .leading)
                        DangoProgressBar(value: section.items.isEmpty ? 0 : Double(sectionDone) / Double(section.items.count),
                                         fill: Dango.areaFill(section.tintName), height: 10, track: Dango.soft)
                            .frame(width: 76)
                        Text("\(sectionDone)/\(section.items.count)").font(Dango.mono(12)).foregroundStyle(Dango.muted).frame(width: 40, alignment: .trailing)
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                if open {
                    VStack(spacing: 2) {
                        ForEach(section.items) { item in
                            let itemDone = sopStore.isCompleted(item.id, on: day)
                            Button { sopStore.toggle(item.id, on: day) } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(itemDone ? Dango.greenDeep : Dango.paper)
                                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Dango.ink, lineWidth: 1.5))
                                        .overlay { if itemDone { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) } }
                                        .frame(width: 16, height: 16)
                                    Text(item.time.map { DailySOPTemplate.startMinute(of: $0).map(DayPlanner.clock) ?? $0 } ?? "")
                                        .font(Dango.mono(11)).foregroundStyle(Dango.muted).frame(width: 42, alignment: .leading)
                                    Text(item.title).font(Dango.font(13))
                                        .strikethrough(itemDone).foregroundStyle(itemDone ? Dango.faint : Dango.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .dangoCard()
    }
}

enum TimelineSelection: Equatable {
    case task(UUID)
    case ghost(UUID)
}

enum GhostStatus { case pending, accepted, rejected }

struct GhostPlacement: Identifiable {
    let suggestion: AISuggestedTask
    let minute: Int?
    var id: UUID { suggestion.id }
}

/// 斜纹填充，用来表示 SOP 节奏占用的时间。
struct SOPStripes: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        ImagePaint(image: Image(nsImage: SOPStripes.tile), scale: 1)
    }

    private static let tile: NSImage = {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.957, green: 0.969, blue: 0.941, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let path = NSBezierPath()
        path.lineWidth = 2
        NSColor(red: 0.867, green: 0.902, blue: 0.827, alpha: 1).setStroke()
        path.move(to: NSPoint(x: -2, y: 12)); path.line(to: NSPoint(x: 12, y: -2))
        path.move(to: NSPoint(x: -7, y: 7)); path.line(to: NSPoint(x: 7, y: -7))
        path.move(to: NSPoint(x: 3, y: 17)); path.line(to: NSPoint(x: 17, y: 3))
        path.stroke()
        image.unlockFocus()
        return image
    }()
}
