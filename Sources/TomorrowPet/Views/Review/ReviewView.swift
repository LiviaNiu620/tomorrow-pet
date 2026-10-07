import SwiftUI

/// 复盘：今天（完成 / 没完成怎么办 / 状态 / 三句话）与本周（统计）。
struct ReviewView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var journal: JournalStore
    @ObservedObject var router: AppRouter

    enum Tab: Hashable { case day, week }
    @State private var tab: Tab = .day
    @State private var toast: String?

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today) ?? today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DangoPageHeader(
                    eyebrow: tab == .day ? today.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))) + " · 23:40 团子会把这页推给你" : "最近 7 天",
                    title: tab == .day ? "今天过得怎么样" : "这一周，回头看看"
                ) {
                    DangoSegmented(selection: $tab, options: [(.day, "今日复盘"), (.week, "本周复盘")])
                }
                if let toast {
                    Text(toast)
                        .font(Dango.font(13, .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dangoBlock(fill: Dango.green, radius: 12, shadow: 0)
                }
                if tab == .day { dayReview } else { weekReview }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
    }

    // MARK: Day

    private var review: DailyReview { journal.review(on: today) }

    private func reviewBinding(_ keyPath: WritableKeyPath<DailyReview, String>) -> Binding<String> {
        Binding(get: { journal.review(on: today)[keyPath: keyPath] },
                set: { value in journal.updateReview(on: today) { $0[keyPath: keyPath] = value } })
    }

    private var doneToday: [TaskItem] {
        store.tasks.filter { task in
            task.status == .completed && (task.completedAt.map { calendar.isDate($0, inSameDayAs: today) } ?? false)
        }
        .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    private var undone: [TaskItem] {
        let triaged = Set(review.triage.keys)
        return store.tasks.filter { task in
            guard task.parentTaskID == nil, task.status != .trashed else { return false }
            if triaged.contains(task.id.uuidString) { return true }
            return task.status.isActive && task.isPlanned(on: today)
        }
        .sorted { $0.priority < $1.priority }
    }

    private var dayReview: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                doneCard
                undoneCard
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 20) {
                moodCard
                writingCard
            }
            .frame(width: 400)
        }
    }

    private var doneCard: some View {
        let sopItems = sopStore.items(for: today)
        let sopDone = sopItems.filter { sopStore.isCompleted($0.id, on: today) }.count
        let maxMinutes = max(60, doneToday.map { max($0.estimatedMinutes ?? 0, journal.focusMinutes(for: $0.id)) }.max() ?? 60)
        let over = doneToday.first { task in
            let actual = journal.focusMinutes(for: task.id)
            return actual > Int(Double(task.estimatedMinutes ?? 9_999) * 1.15)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("今天吃掉的团子").font(Dango.font(17, .heavy))
                Text("计划 vs 专注用时").font(Dango.font(12)).foregroundStyle(Dango.muted)
                Spacer()
                DangoChip(text: "SOP \(sopDone)/\(sopItems.count)", fill: Dango.green)
            }
            if doneToday.isEmpty {
                Text("今天还没有勾掉任务。完成一件，就会出现在这里。").font(Dango.font(13)).foregroundStyle(Dango.muted)
            }
            ForEach(doneToday) { task in
                let planned = task.estimatedMinutes ?? 0
                let actual = journal.focusMinutes(for: task.id)
                VStack(spacing: 0) {
                    DashedDivider()
                    HStack(spacing: 14) {
                        DangoSquareDot(fill: store.fill(for: task))
                        Text(task.title).font(Dango.font(13, .bold)).frame(width: 240, alignment: .leading).lineLimit(2)
                        VStack(alignment: .leading, spacing: 4) {
                            bar(minutes: planned, max: maxMinutes, fill: Dango.soft, label: planned > 0 ? "计划 \(DayPlanner.duration(planned))" : "没估时")
                            bar(minutes: actual, max: maxMinutes, fill: actual > Int(Double(planned) * 1.1) && planned > 0 ? Dango.pink : Dango.greenDeep,
                                label: actual > 0 ? "专注 \(DayPlanner.duration(actual))" : "没用专注计时")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            if let over {
                Text("团子发现：「\(over.title)」比预计多用了 \(DayPlanner.duration(journal.focusMinutes(for: over.id) - (over.estimatedMinutes ?? 0)))。类似的任务下次可以估宽一点。")
                    .font(Dango.font(12, .bold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dangoBlock(fill: Dango.blushSoft, radius: 12, shadow: 0, dashed: true)
            }
        }
        .dangoCard(padding: 20)
    }

    private func bar(minutes: Int, max: Int, fill: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(fill)
                .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 1.5))
                .frame(width: minutes > 0 ? Swift.max(8, CGFloat(minutes) / CGFloat(max) * 220) : 8, height: 10)
            Text(label).font(Dango.mono(11)).foregroundStyle(Dango.muted)
        }
    }

    private var undoneCard: some View {
        let list = undone
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("没吃完的，怎么处理").font(Dango.font(17, .heavy))
                Spacer()
                Text("已处理 \(review.triage.count)/\(list.count)").font(Dango.mono(12))
            }
            if list.isEmpty {
                Text("今天计划的事都完成了。").font(Dango.font(13)).foregroundStyle(Dango.muted)
            }
            ForEach(list) { task in
                let choice = review.triage[task.id.uuidString]
                VStack(spacing: 0) {
                    DashedDivider()
                    HStack(spacing: 12) {
                        DangoSquareDot(fill: store.fill(for: task))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(Dango.font(13, .heavy))
                            Text(note(for: task, choice: choice))
                                .font(Dango.font(12))
                                .foregroundStyle(choice != nil ? Dango.greenText : ((task.postponeCount ?? 0) > 0 ? Dango.pinkText : Dango.muted))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(TriageChoice.allCases) { option in
                            Button(option.title) { triage(task, option) }
                                .buttonStyle(.dango(choice == option ? (option == .letGo ? .plain : .green) : .plain, small: true))
                                .disabled(choice != nil)
                                .opacity(choice != nil && choice != option ? 0.4 : 1)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .dangoCard(padding: 20)
    }

    private func note(for task: TaskItem, choice: TriageChoice?) -> String {
        switch choice {
        case .tomorrow: return "→ 已加到明天，团子规划时会优先考虑"
        case .thisWeek: return "→ 放回本周待安排"
        case .letGo: return "→ 放下了，移到长期任务"
        case nil:
            let count = task.postponeCount ?? 0
            return count > 0 ? "已经顺延 \(count) 次了" : (task.scheduledMinute == nil ? "没排进时间轴" : "排了时间但没做完")
        }
    }

    private func triage(_ task: TaskItem, _ choice: TriageChoice) {
        switch choice {
        case .tomorrow:
            store.postpone(task.id, to: tomorrow)
        case .thisWeek:
            store.clearPlannedDate(task.id)
        case .letGo:
            store.mutate(task.id, message: "已放下") {
                $0.plannedDate = nil
                $0.scheduledMinute = nil
                $0.focusDate = nil
                $0.manualHorizon = .longTerm
                if $0.status == .planned { $0.status = .next }
            }
        }
        journal.updateReview(on: today) { $0.triage[task.id.uuidString] = choice }
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今天的状态").font(Dango.font(17, .heavy))
            scale("精力", value: review.energy) { value in journal.updateReview(on: today) { $0.energy = value } }
            scale("心情", value: review.mood) { value in journal.updateReview(on: today) { $0.mood = value } }
        }
        .dangoCard(padding: 20)
    }

    private func scale(_ title: String, value: Int?, set: @escaping (Int) -> Void) -> some View {
        let words = ["很低", "偏低", "一般", "不错", "很好"]
        let fills = [Dango.pink, Dango.pinkLight, Dango.paper, Color(hex: 0xD6EBC4), Dango.green]
        return VStack(alignment: .leading, spacing: 8) {
            Text(title + (value.map { " · \(words[$0 - 1])" } ?? "")).font(Dango.font(13, .heavy))
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { n in
                    let on = value == n
                    Button { set(n) } label: {
                        Text("\(n)")
                            .font(Dango.font(15, .heavy))
                            .frame(width: 48, height: 48)
                            .background {
                                ZStack {
                                    Circle().fill(Dango.ink).offset(x: on ? 0 : 2, y: on ? 0 : 2)
                                    Circle().fill(fills[n - 1])
                                    Circle().strokeBorder(Dango.ink, lineWidth: on ? 4 : 2)
                                }
                            }
                            .offset(y: on ? -2 : 0)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(title) \(n) 分")
                }
            }
        }
    }

    private var writingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("三句话复盘").font(Dango.font(17, .heavy))
            labeled("今天的进展") { DangoTextArea(placeholder: "完成了什么、推进到哪里", text: reviewBinding(\.progress), minHeight: 56) }
            labeled("卡住的地方") { DangoTextArea(placeholder: "哪里比预期慢？为什么？", text: reviewBinding(\.blocker), minHeight: 56) }
            labeled("明天到工位的第一件事") { DangoTextArea(placeholder: "写得越具体越好", text: reviewBinding(\.firstAction), minHeight: 56) }
            Button("存进日记，并把第一件事设为明天 Top 1") { saveReview() }
                .buttonStyle(.dango(.pink, fullWidth: true))
            if let saved = review.savedAt {
                Text("上次保存 \(saved.formatted(date: .omitted, time: .shortened))").font(Dango.font(12)).foregroundStyle(Dango.muted)
            }
        }
        .dangoCard(shadow: Dango.pink, padding: 20)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Dango.font(12, .heavy))
            content()
        }
    }

    private func saveReview() {
        let first = review.firstAction.trimmingCharacters(in: .whitespacesAndNewlines)
        journal.updateReview(on: today) { $0.savedAt = .now }
        if !first.isEmpty, !store.tasks(plannedOn: tomorrow).contains(where: { $0.title == first }) {
            if let task = store.addTask(title: first, plannedDate: tomorrow) {
                store.setFocus(task.id, on: tomorrow, isFocus: true)
            }
            withAnimation { toast = "已存进日记 · 明天 Top 1：\(first)" }
        } else {
            withAnimation { toast = first.isEmpty ? "已存进日记 · 还没写明天第一件事，明早团子会再问你一次" : "已存进日记" }
        }
    }

    // MARK: Week

    private var lastSevenDays: [Date] {
        (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var weekReview: some View {
        let days = lastSevenDays
        let focusTasks = days.flatMap { store.focusTasks(on: $0) }
        let focusDone = focusTasks.filter { $0.status == .completed }.count
        let plannedTasks = days.flatMap { day in store.tasks(plannedOn: day).filter { $0.parentTaskID == nil } }
        let plannedMinutes = plannedTasks.reduce(0) { $0 + $1.plannedDuration }
        let doneMinutes = plannedTasks.filter { $0.status == .completed }.reduce(0) { $0 + $1.plannedDuration }
        let sopTotal = days.reduce(0) { $0 + sopStore.items(for: $1).count }
        let sopDone = days.reduce(0) { sum, day in sum + sopStore.items(for: day).filter { sopStore.isCompleted($0.id, on: day) }.count }
        let focusMinutes = days.reduce(0) { $0 + journal.focusMinutes(on: $1) }
        return VStack(spacing: 20) {
            HStack(spacing: 18) {
                kpi("Top 3 完成率", focusTasks.isEmpty ? "—" : "\(focusDone * 100 / max(1, focusTasks.count))%", "\(focusDone) / \(focusTasks.count)", Dango.green)
                kpi("计划完成度", plannedMinutes == 0 ? "—" : "\(doneMinutes * 100 / max(1, plannedMinutes))%", "完成时长 / 计划时长", Dango.apricot)
                kpi("SOP 完成率", sopTotal == 0 ? "—" : "\(sopDone * 100 / max(1, sopTotal))%", "\(sopDone) / \(sopTotal) 项", Dango.lavender)
                kpi("专注时长", DayPlanner.duration(focusMinutes), "\(days.reduce(0) { $0 + journal.sessions(on: $1).count }) 个番茄", Dango.sky)
            }
            HStack(alignment: .top, spacing: 20) {
                chartCard(days).frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                    slippedCard
                    summaryCard(days: days, plannedTasks: plannedTasks)
                }
                .frame(width: 400)
            }
        }
    }

    private func kpi(_ title: String, _ value: String, _ note: String, _ fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Dango.font(13, .heavy))
            Text(value).font(Dango.mono(34, .medium))
            Text(note).font(Dango.font(12, .bold))
        }
        .dangoCard(fill: fill, padding: 16)
    }

    private func chartCard(_ days: [Date]) -> some View {
        let data = days.map { day -> (Date, Int, Int) in
            let tasks = store.tasks(plannedOn: day).filter { $0.parentTaskID == nil }
            return (day, tasks.reduce(0) { $0 + $1.plannedDuration }, tasks.filter { $0.status == .completed }.reduce(0) { $0 + $1.plannedDuration })
        }
        let maxValue = max(60, data.map { max($0.1, $0.2) }.max() ?? 60)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("每天：计划 vs 完成").font(Dango.font(17, .heavy))
                Spacer()
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Dango.paper).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Dango.ink, lineWidth: 1.5)).frame(width: 12, height: 12)
                    Text("计划").font(Dango.font(12, .bold))
                    RoundedRectangle(cornerRadius: 3).fill(Dango.greenDeep).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Dango.ink, lineWidth: 1.5)).frame(width: 12, height: 12).padding(.leading, 6)
                    Text("完成").font(Dango.font(12, .bold))
                }
            }
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 4) {
                            barColumn(value: item.1, max: maxValue, fill: Dango.paper)
                            barColumn(value: item.2, max: maxValue, fill: Dango.greenDeep)
                        }
                        .frame(height: 220, alignment: .bottom)
                        Rectangle().fill(Dango.ink).frame(height: 2)
                        Text(item.0.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))).font(Dango.font(12, .heavy))
                        Text("\(DayPlanner.duration(item.2))/\(DayPlanner.duration(item.1))").font(Dango.mono(10.5)).foregroundStyle(Dango.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .dangoCard(padding: 20)
    }

    private func barColumn(value: Int, max: Int, fill: Color) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
            .fill(fill)
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).stroke(Dango.ink, lineWidth: 2))
            .frame(width: 26, height: value > 0 ? Swift.max(6, CGFloat(value) / CGFloat(max) * 220) : 2)
    }

    private var slippedCard: some View {
        let slipped = store.activeTasks.filter { ($0.postponeCount ?? 0) > 0 }
            .sorted { ($0.postponeCount ?? 0) > ($1.postponeCount ?? 0) }
            .prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            Text("被顺延最多").font(Dango.font(17, .heavy))
            if slipped.isEmpty {
                Text("没有被反复顺延的任务，很稳。").font(Dango.font(13)).foregroundStyle(Dango.muted)
            }
            ForEach(Array(slipped)) { task in
                HStack(spacing: 10) {
                    Text("×\(task.postponeCount ?? 0)")
                        .font(Dango.mono(12))
                        .frame(width: 36, height: 26)
                        .dangoBlock(fill: Dango.pink, radius: 8, shadow: 0)
                    Text(task.title).font(Dango.font(13, .bold)).lineLimit(2)
                    Spacer()
                    Button("拆小") { router.selectedLibraryTaskID = task.id; router.go(.library) }
                        .buttonStyle(.dango(small: true))
                }
            }
        }
        .dangoCard(padding: 20)
    }

    private func summaryCard(days: [Date], plannedTasks: [TaskItem]) -> some View {
        let perDay = days.map { day -> (Date, Double) in
            let tasks = store.tasks(plannedOn: day).filter { $0.parentTaskID == nil }
            guard !tasks.isEmpty else { return (day, -1) }
            return (day, Double(tasks.filter { $0.status == .completed }.count) / Double(tasks.count))
        }.filter { $0.1 >= 0 }
        let worst = perDay.min { $0.1 < $1.1 }
        let best = perDay.max { $0.1 < $1.1 }
        let slipped = store.activeTasks.max { ($0.postponeCount ?? 0) < ($1.postponeCount ?? 0) }
        var lines: [String] = []
        if let best, let worst, best.0 != worst.0 {
            let f = { (d: Date) in d.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))) }
            lines.append("\(f(best.0))完成得最好（\(Int(best.1 * 100))%），\(f(worst.0))最吃力（\(Int(worst.1 * 100))%）。")
        }
        if let slipped, (slipped.postponeCount ?? 0) >= 2 {
            lines.append("「\(slipped.title)」已经顺延 \(slipped.postponeCount ?? 0) 次，下周一早上直接给它锁一个 90 分钟的块，或者先拆小。")
        }
        if lines.isEmpty { lines.append("这周的数据还不多。坚持用时间轴排两三天，这里就会有你的节奏画像。") }
        return VStack(alignment: .leading, spacing: 10) {
            Text("团子的周总结").font(Dango.font(17, .heavy)).foregroundStyle(.white)
            Text(lines.joined(separator: "\n")).font(Dango.font(13)).lineSpacing(4).foregroundStyle(Dango.sidebarText)
                .fixedSize(horizontal: false, vertical: true)
            Button("带着这些去排下周 →") { router.go(.week) }.buttonStyle(.dango(.pink))
        }
        .dangoCard(fill: Dango.ink, shadow: Dango.pink, padding: 20)
    }
}
