import SwiftUI

/// 习惯 · SOP：编辑一天的节奏（时段 + 清单），并查看每日固定目标的打卡热力图。
struct HabitsView: View {
    @ObservedObject var sopStore: DailySOPStore

    @State private var scope: SOPBlockScope = .everyday
    @State private var selectedBlockID: String?
    @State private var newItem = ""
    @State private var showTemplateEditor = false

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 36

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DangoPageHeader(eyebrow: "SOP 是一天的骨架；改这里，「今天」时间轴和 AI 规划都会跟着变", title: "习惯 · SOP") {
                    HStack(spacing: 12) {
                        DangoSegmented(selection: $scope, options: SOPBlockScope.allCases.map { ($0, $0.title) })
                        Button("完整模板…") { showTemplateEditor = true }.buttonStyle(.dango())
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    ribbonCard.frame(width: 340)
                    editorCard.frame(maxWidth: .infinity)
                }
                heatmapCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
        .sheet(isPresented: $showTemplateEditor) { SOPTemplateEditorView(store: sopStore) }
        .onChange(of: scope) { _, _ in selectedBlockID = nil }
    }

    // MARK: Variant date

    /// 用来展示该模板的代表日期。
    private var sampleDate: Date {
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<60 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let isSunday = calendar.component(.weekday, from: date) == 1
            let monthEnd = isSunday && DailySOPTemplate.isLastSundayOfMonth(date, calendar: calendar)
            switch scope {
            case .everyday where !isSunday: return date
            case .sunday where isSunday && !monthEnd: return date
            case .monthEnd where monthEnd: return date
            default: continue
            }
        }
        return today
    }

    private var blocks: [SOPTimeBlock] { sopStore.blocks(for: sampleDate) }
    private var selectedBlock: SOPTimeBlock? {
        blocks.first { $0.id == selectedBlockID } ?? blocks.first { $0.scope == scope } ?? blocks.first
    }

    // MARK: Ribbon

    private func y(_ minute: Int) -> CGFloat { CGFloat(minute - DayPlanner.dayStart) / 60 * hourHeight }

    private var ribbonCard: some View {
        let free = DayPlanner.freeWindows(blocks: blocks).reduce(0) { $0 + $1.length }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("一天的节奏").font(Dango.font(16, .heavy))
                Spacer()
                Button("+ 时段") { addBlock() }.buttonStyle(.dango(small: true))
            }
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: DayPlanner.dayStart, through: DayPlanner.dayEnd, by: 60)), id: \.self) { minute in
                    HStack(spacing: 8) {
                        Text(DayPlanner.clock(minute)).font(Dango.mono(11)).foregroundStyle(Dango.muted).frame(width: 42, alignment: .trailing)
                        DashedDivider()
                    }
                    .frame(height: 16)
                    .offset(y: y(minute) - 8)
                }
                ForEach(blocks) { block in
                    let selected = selectedBlock?.id == block.id
                    let height = max(16, y(block.end) - y(block.start) - 2)
                    Button { selectedBlockID = block.id } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(block.title).font(Dango.font(12, .heavy)).lineLimit(1)
                            if height > 30 {
                                Text("\(DayPlanner.clock(block.start))–\(DayPlanner.clock(block.end))").font(Dango.mono(10.5))
                            }
                        }
                        .foregroundStyle(Dango.ink)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .dangoBlock(fill: Dango.areaFill(block.tintName), radius: 10, shadow: 2, highlighted: selected)
                    }
                    .buttonStyle(PressableStyle())
                    .frame(height: height)
                    .padding(.leading, 52)
                    .offset(y: y(block.start) + 1)
                    .zIndex(selected ? 2 : 1)
                }
            }
            .frame(height: y(DayPlanner.dayEnd) + 8, alignment: .topLeading)
            Text("色块之间的空白是留给任务的时间，这个模板共 \(DayPlanner.duration(free))。")
                .font(Dango.font(12)).foregroundStyle(Dango.muted)
        }
        .dangoCard(padding: 16)
    }

    private func addBlock() {
        let block = SOPTimeBlock(id: "block-\(UUID().uuidString)", title: "新时段", start: 20 * 60, end: 20 * 60 + 30,
                                 scope: scope, remind: false, tintName: "green")
        sopStore.updateTimeBlock(block)
        selectedBlockID = block.id
    }

    // MARK: Editor

    private var sections: [DailySOPSection] { sopStore.sections(for: sampleDate) }

    private func items(in block: SOPTimeBlock) -> [DailySOPItem] {
        sections.flatMap(\.items).filter { item in
            DailySOPTemplate.startMinute(of: item.time).map { $0 >= block.start && $0 < block.end } ?? false
        }
        .sorted { (DailySOPTemplate.startMinute(of: $0.time) ?? 0) < (DailySOPTemplate.startMinute(of: $1.time) ?? 0) }
    }

    @ViewBuilder
    private var editorCard: some View {
        if let block = selectedBlock {
            let blockItems = items(in: block)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    DangoSquareDot(fill: Dango.areaFill(block.tintName), size: 18)
                    TextField("时段名称", text: Binding(
                        get: { block.title },
                        set: { value in var copy = block; copy.title = value; sopStore.updateTimeBlock(copy) }
                    ))
                    .textFieldStyle(.plain)
                    .font(Dango.font(22, .heavy))
                    Spacer()
                    Text("自动保存").font(Dango.font(12, .bold)).foregroundStyle(Dango.greenText)
                }
                HStack(spacing: 12) {
                    timeStepper("开始", block: block, key: \.start)
                    timeStepper("结束", block: block, key: \.end)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Button(block.remind ? "到点提醒 · 开" : "到点提醒 · 关") {
                        var copy = block; copy.remind.toggle(); sopStore.updateTimeBlock(copy)
                    }
                    .buttonStyle(.dango(block.remind ? .green : .plain))
                    Menu {
                        ForEach(["orange", "blue", "pink", "purple", "green", "teal"], id: \.self) { name in
                            Button(name) { var copy = block; copy.tintName = name; sopStore.updateTimeBlock(copy) }
                        }
                    } label: { DangoChip(text: "颜色", fill: Dango.areaFill(block.tintName)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    Spacer()
                    Button("删除时段") { sopStore.removeTimeBlock(id: block.id); selectedBlockID = nil }
                        .buttonStyle(.dango(small: true))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("清单").font(Dango.font(13, .heavy))
                        Text("粉色「AI」= 规划时把这一项当作固定占用告诉团子").font(Dango.font(12)).foregroundStyle(Dango.muted)
                    }
                    if blockItems.isEmpty {
                        Text("这个时段里还没有清单项。下面加一项，写上时间（比如 20:10）就会落进这个时段。")
                            .font(Dango.font(13)).foregroundStyle(Dango.muted)
                    }
                    ForEach(blockItems) { item in
                        HStack(spacing: 10) {
                            Text(DailySOPTemplate.startMinute(of: item.time).map(DayPlanner.clock) ?? "")
                                .font(Dango.mono(12)).foregroundStyle(Dango.muted).frame(width: 50, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(Dango.font(14, .bold))
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail).font(Dango.font(12)).foregroundStyle(Dango.muted)
                                }
                            }
                            Spacer()
                            Button { toggleAI(item) } label: {
                                Text("AI")
                                    .font(Dango.font(11, .heavy))
                                    .foregroundStyle(item.isPlanningContext ? Dango.ink : Dango.faint)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(item.isPlanningContext ? Dango.pink : Dango.paper))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Dango.ink, lineWidth: 1.5))
                            }
                            .buttonStyle(PressableStyle())
                            .help(item.isPlanningContext ? "已提供给 AI 规划" : "不提供给 AI")
                            Button { removeItem(item) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Dango.paper))
                                    .overlay(Circle().strokeBorder(Dango.ink, lineWidth: 1.5))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("删除 \(item.title)")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Dango.softer))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Dango.dash, lineWidth: 1.5))
                    }
                    HStack(spacing: 10) {
                        DangoField(placeholder: "加一项，例如：\(DayPlanner.clock(block.start)) 喝一杯水", text: $newItem) { addItem(to: block) }
                        Button("添加") { addItem(to: block) }.buttonStyle(.dango(.pink))
                    }
                    .padding(.top, 4)
                }
            }
            .dangoCard(shadow: Dango.pink, padding: 20)
        } else {
            Text("这个模板还没有时段，点「+ 时段」加一个。")
                .font(Dango.font(14, .bold))
                .dangoCard(padding: 30)
        }
    }

    private func timeStepper(_ title: String, block: SOPTimeBlock, key: WritableKeyPath<SOPTimeBlock, Int>) -> some View {
        HStack(spacing: 6) {
            Text(title).font(Dango.font(12, .heavy)).padding(.horizontal, 4)
            Button("−15") { shift(block, key, by: -15) }.buttonStyle(.dango(small: true))
            Text(DayPlanner.clock(block[keyPath: key])).font(Dango.mono(15)).frame(width: 54)
            Button("+15") { shift(block, key, by: 15) }.buttonStyle(.dango(small: true))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(Dango.softer))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Dango.ink, lineWidth: 2))
    }

    private func shift(_ block: SOPTimeBlock, _ key: WritableKeyPath<SOPTimeBlock, Int>, by delta: Int) {
        var copy = block
        copy[keyPath: key] = min(DayPlanner.dayEnd, max(DayPlanner.dayStart, copy[keyPath: key] + delta))
        guard copy.end - copy.start >= 15 else { return }
        sopStore.updateTimeBlock(copy)
    }

    private func editConfiguration(_ change: (inout DailySOPConfiguration) -> Void) {
        var config = sopStore.configuration
        change(&config)
        sopStore.updateConfiguration(config)
    }

    private func toggleAI(_ item: DailySOPItem) {
        editConfiguration { config in
            func flip(_ section: inout DailySOPSection) {
                if let index = section.items.firstIndex(where: { $0.id == item.id }) {
                    section.items[index].isPlanningContext.toggle()
                }
            }
            for index in config.dailySections.indices { flip(&config.dailySections[index]) }
            flip(&config.sundaySection)
            flip(&config.monthlySection)
        }
    }

    private func removeItem(_ item: DailySOPItem) {
        editConfiguration { config in
            for index in config.dailySections.indices { config.dailySections[index].items.removeAll { $0.id == item.id } }
            config.sundaySection.items.removeAll { $0.id == item.id }
            config.monthlySection.items.removeAll { $0.id == item.id }
        }
    }

    private func addItem(to block: SOPTimeBlock) {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var time = DayPlanner.clock(block.start)
        var title = text
        if let range = text.range(of: #"^\d{1,2}[:：]\d{2}"#, options: .regularExpression) {
            let raw = text[range].replacingOccurrences(of: "：", with: ":")
            if let minute = DailySOPTemplate.startMinute(of: raw) { time = DayPlanner.clock(minute) }
            title = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        guard !title.isEmpty else { return }
        let existing = items(in: block)
        editConfiguration { config in
            let targetSectionID = existing.first?.sectionID
            let item = DailySOPItem(id: "sop-\(UUID().uuidString)", time: time, title: title, sectionID: "", sectionTitle: "")
            switch block.scope {
            case .sunday: config.sundaySection.items.append(item)
            case .monthEnd: config.monthlySection.items.append(item)
            case .everyday:
                if let targetSectionID, let index = config.dailySections.firstIndex(where: { $0.id == targetSectionID }) {
                    config.dailySections[index].items.append(item)
                } else if !config.dailySections.isEmpty {
                    let index = config.dailySections.firstIndex { $0.items.contains { $0.time != nil } } ?? 0
                    config.dailySections[index].items.append(item)
                }
            }
        }
        newItem = ""
    }

    // MARK: Heatmap

    private var habitItems: [DailySOPItem] {
        let untimed = sopStore.configuration.dailySections.flatMap(\.items).filter { $0.time == nil }
        return untimed.isEmpty ? Array(sopStore.configuration.dailySections.flatMap(\.items).prefix(8)) : untimed
    }

    private var heatmapDays: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (0..<35).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var heatmapCard: some View {
        let days = heatmapDays
        return VStack(alignment: .leading, spacing: 12) {
            heatmapHeader
            heatmapDayLabels(days)
            ForEach(habitItems) { item in
                habitRow(item, days: days)
            }
        }
        .dangoCard(padding: 20)
    }

    private var heatmapHeader: some View {
        HStack(spacing: 14) {
            Text("每日固定目标 · 近 5 周").font(Dango.font(16, .heavy))
            Text("来自每日 SOP 打卡 · 点格子可以补打卡").font(Dango.font(12)).foregroundStyle(Dango.muted)
            Spacer()
            legendSwatch(fill: Dango.soft, border: Dango.line)
            Text("没做").font(Dango.font(12, .bold))
            legendSwatch(fill: Dango.greenDeep, border: Dango.ink).padding(.leading, 6)
            Text("做了").font(Dango.font(12, .bold))
        }
    }

    private func legendSwatch(fill: Color, border: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1.5))
            .frame(width: 13, height: 13)
    }

    private func heatmapDayLabels(_ days: [Date]) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 160, height: 1)
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    dayLabel(index: index, day: day, count: days.count)
                }
            }
            Text("连续 · 完成率").font(Dango.font(11, .bold)).foregroundStyle(Dango.muted).frame(width: 110, alignment: .trailing)
        }
    }

    private func dayLabel(index: Int, day: Date, count: Int) -> some View {
        let show = index % 7 == 0 || index == count - 1
        let text: String = show ? day.formatted(.dateTime.month(.defaultDigits).day()) : ""
        return Text(text)
            .font(Dango.mono(9.5))
            .foregroundStyle(Dango.muted)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func habitRow(_ item: DailySOPItem, days: [Date]) -> some View {
        let marks: [Bool] = days.map { sopStore.isCompleted(item.id, on: $0) }
        let doneCount = marks.filter { $0 }.count
        let rate = Int((Double(doneCount) / Double(max(1, marks.count)) * 100).rounded())
        let streak = Self.streak(marks)
        return HStack(spacing: 12) {
            Text(item.title).font(Dango.font(13, .bold)).lineLimit(1).frame(width: 160, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    heatCell(item: item, day: day, on: marks[index], isToday: index == days.count - 1)
                }
            }
            HStack(spacing: 4) {
                Text("\(streak) 天")
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 6).fill(streak >= 5 ? Dango.green : Color.clear))
                Text("· \(rate)%")
            }
            .font(Dango.mono(12))
            .frame(width: 110, alignment: .trailing)
        }
    }

    private func heatCell(item: DailySOPItem, day: Date, on: Bool, isToday: Bool) -> some View {
        let border: Color = isToday ? Dango.pinkDeep : (on ? Dango.ink : Dango.line)
        return Button { sopStore.toggle(item.id, on: day) } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(on ? Dango.greenDeep : Dango.soft)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(border, lineWidth: isToday ? 2 : 1.5))
                .frame(height: 20)
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity)
        .help(on ? "已完成" : "未完成")
    }

    private static func streak(_ marks: [Bool]) -> Int {
        var count = 0
        var index = marks.count - 1
        if index >= 0 && !marks[index] { index -= 1 } // 今天还没打卡不打断连续
        while index >= 0 && marks[index] {
            count += 1
            index -= 1
        }
        return count
    }
}
