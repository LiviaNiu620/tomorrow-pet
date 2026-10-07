import SwiftUI

/// 07:00–24:00 时间轴：SOP 节奏带、日历块、任务块、AI 草稿块和“现在”线。
struct TimelineCanvas: View {
    let blocks: [SOPTimeBlock]
    let events: [CalendarEventSummary]
    let day: Date
    let tasks: [TaskItem]
    let ghosts: [GhostPlacement]
    let topSuggestionIDs: Set<UUID>
    let nowMinute: Int?
    let sopDone: (String) -> Bool
    let sopItems: [DailySOPItem]
    @Binding var selection: TimelineSelection?
    @ObservedObject var store: TaskStore
    let place: (Int) -> Void
    let dropTask: (UUID, Int) -> Void
    let acceptGhost: (GhostPlacement) -> Void
    let rejectGhost: (GhostPlacement) -> Void
    let startFocus: (TaskItem) -> Void

    @State private var hoverSlot: Int?

    private let hourHeight: CGFloat = 56
    private let startMinute = DayPlanner.dayStart
    private let endMinute = DayPlanner.dayEnd
    private let labelWidth: CGFloat = 58

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(minute - startMinute) / 60 * hourHeight
    }

    var body: some View {
        let height = y(endMinute) + 8
        GeometryReader { proxy in
            let laneWidth = max(100, proxy.size.width - labelWidth - 4)
            ZStack(alignment: .topLeading) {
                hourGrid
                lane(width: laneWidth)
                    .offset(x: labelWidth)
                if let nowMinute, nowMinute >= startMinute, nowMinute <= endMinute {
                    nowLine(nowMinute)
                }
            }
        }
        .frame(height: height)
    }

    // MARK: Grid

    private var hourGrid: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: startMinute, through: endMinute, by: 60)), id: \.self) { minute in
                HStack(spacing: 8) {
                    Text(DayPlanner.clock(minute))
                        .font(Dango.mono(11))
                        .foregroundStyle(Dango.muted)
                        .frame(width: labelWidth - 10, alignment: .trailing)
                    if minute > startMinute {
                        DashedDivider()
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(height: 16)
                .offset(y: y(minute) - 8)
            }
        }
    }

    private func nowLine(_ minute: Int) -> some View {
        HStack(spacing: 4) {
            Text(DayPlanner.clock(minute))
                .font(Dango.mono(11))
                .foregroundStyle(Dango.ink)
                .frame(width: labelWidth - 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Dango.pink))
                .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
            Rectangle().fill(Dango.pinkDeep).frame(height: 3)
        }
        .frame(height: 20)
        .offset(y: y(minute) - 10)
        .allowsHitTesting(false)
        .accessibilityLabel("现在 \(DayPlanner.clock(minute))")
    }

    // MARK: Lane

    private func lane(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { block in
                bandView(block)
                    .frame(width: width, height: max(14, y(block.end) - y(block.start)))
                    .offset(y: y(block.start))
            }
            ForEach(Array(stride(from: startMinute, to: endMinute, by: 30)), id: \.self) { minute in
                slot(minute)
                    .frame(width: width, height: hourHeight / 2)
                    .offset(y: y(minute))
            }
            ForEach(layoutItems(width: width)) { item in
                itemView(item)
                    .frame(width: item.width - 4, height: item.height)
                    .offset(x: item.x, y: item.y)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func bandView(_ block: SOPTimeBlock) -> some View {
        let items = sopItems.filter { item in
            DailySOPTemplate.startMinute(of: item.time).map { $0 >= block.start && $0 < block.end } ?? false
        }
        let done = items.filter { sopDone($0.id) }.count
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(SOPStripes())
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Text(block.title).font(Dango.font(11, .heavy))
                    if !items.isEmpty && nowMinute != nil {
                        Text("\(done)/\(items.count)").font(Dango.mono(11))
                    }
                }
                .foregroundStyle(Color(hex: 0x4C5A42))
                .padding(.horizontal, 10)
                .padding(.top, 3)
            }
            .clipped()
            .allowsHitTesting(false)
    }

    private func slot(_ minute: Int) -> some View {
        let active = selection != nil && hoverSlot == minute
        return RoundedRectangle(cornerRadius: 8)
            .fill(active ? Dango.pink.opacity(0.28) : Color.white.opacity(0.001))
            .overlay(alignment: .leading) {
                if active {
                    Text("放在 \(DayPlanner.clock(minute))")
                        .font(Dango.font(11, .bold))
                        .foregroundStyle(Dango.pinkText)
                        .padding(.leading, 10)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hoverSlot = minute } else if hoverSlot == minute { hoverSlot = nil }
            }
            .onTapGesture { place(minute) }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, raw.hasPrefix("task:"),
                      let id = UUID(uuidString: String(raw.dropFirst(5))) else { return false }
                dropTask(id, minute)
                return true
            } isTargeted: { targeted in
                if targeted { hoverSlot = minute }
            }
            .accessibilityLabel("时间轴 \(DayPlanner.clock(minute))")
    }

    // MARK: Items & overlap layout

    private enum ItemKind {
        case event(CalendarEventSummary)
        case task(TaskItem)
        case ghost(GhostPlacement)
    }

    private struct LaidOutItem: Identifiable {
        let id: String
        let kind: ItemKind
        let start: Int
        let end: Int
        var column = 0
        var columns = 1
        var x: CGFloat = 0
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutItems(width: CGFloat) -> [LaidOutItem] {
        var items: [LaidOutItem] = []
        for event in events {
            guard let range = DayPlanner.minuteRange(of: event, on: day) else { continue }
            items.append(LaidOutItem(id: "e-\(event.id)", kind: .event(event), start: max(range.start, startMinute), end: range.end))
        }
        for task in tasks {
            guard let start = task.scheduledMinute else { continue }
            items.append(LaidOutItem(id: "t-\(task.id)", kind: .task(task), start: max(start, startMinute), end: start + task.plannedDuration))
        }
        for ghost in ghosts {
            guard let start = ghost.minute else { continue }
            items.append(LaidOutItem(id: "g-\(ghost.id)", kind: .ghost(ghost), start: start, end: start + max(15, ghost.suggestion.estimatedMinutes)))
        }
        items.sort { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }

        // 重叠的块分栏显示。
        var clusterStart = 0
        var clusterEnd = Int.min
        var columnEnds: [Int] = []
        func closeCluster(upTo index: Int) {
            let count = max(1, columnEnds.count)
            for i in clusterStart..<index { items[i].columns = count }
        }
        for index in items.indices {
            if items[index].start >= clusterEnd {
                closeCluster(upTo: index)
                clusterStart = index
                columnEnds = []
            }
            if let column = columnEnds.firstIndex(where: { $0 <= items[index].start }) {
                items[index].column = column
                columnEnds[column] = items[index].end
            } else {
                items[index].column = columnEnds.count
                columnEnds.append(items[index].end)
            }
            clusterEnd = max(clusterEnd, items[index].end)
        }
        closeCluster(upTo: items.count)

        for index in items.indices {
            let columnWidth = width / CGFloat(items[index].columns)
            items[index].x = columnWidth * CGFloat(items[index].column)
            items[index].width = columnWidth
            items[index].y = y(items[index].start) + 2
            items[index].height = max(24, y(items[index].end) - y(items[index].start) - 4)
        }
        return items
    }

    @ViewBuilder
    private func itemView(_ item: LaidOutItem) -> some View {
        let compact = item.height < 44
        switch item.kind {
        case .event(let event):
            eventBlock(event, compact: compact, start: item.start, end: item.end)
        case .task(let task):
            taskBlock(task, compact: compact)
        case .ghost(let ghost):
            ghostBlock(ghost, compact: compact)
        }
    }

    private func eventBlock(_ event: CalendarEventSummary, compact: Bool, start: Int, end: Int) -> some View {
        let layout = compact ? AnyLayout(HStackLayout(alignment: .center, spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
        return layout {
            Text(event.title).font(Dango.font(13, .heavy)).foregroundStyle(.white).lineLimit(compact ? 1 : 2)
            Text("\(DayPlanner.clock(start))–\(DayPlanner.clock(end)) · \(event.calendarTitle)")
                .font(Dango.mono(11)).foregroundStyle(Color(hex: 0xD8D3CB)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Dango.ink))
        .help("\(event.title)（\(event.source.title)，不可移动）")
    }

    private func taskBlock(_ task: TaskItem, compact: Bool) -> some View {
        let selected = selection == .task(task.id)
        let done = task.status == .completed
        let start = task.scheduledMinute ?? 0
        let isFocus = task.focusDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        let layout = compact ? AnyLayout(HStackLayout(alignment: .center, spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
        return HStack(alignment: compact ? .center : .top, spacing: 10) {
            DangoCheck(done: done) { store.setCompleted(task.id, completed: !done) }
            Button { selection = selected ? nil : .task(task.id) } label: {
                layout {
                    Text(task.title)
                        .font(Dango.font(13, .heavy))
                        .strikethrough(done)
                        .lineLimit(compact ? 1 : 3)
                        .multilineTextAlignment(.leading)
                    Text("\(DayPlanner.clock(start))–\(DayPlanner.clock(start + task.plannedDuration)) · \(DayPlanner.duration(task.plannedDuration))\(isFocus ? " · Top" : "")")
                        .font(Dango.mono(11))
                        .foregroundStyle(Color(hex: 0x3E423B))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .foregroundStyle(Dango.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dangoBlock(fill: store.fill(for: task), radius: 10, shadow: 2, highlighted: selected)
        .opacity(done ? 0.55 : 1)
        .draggable("task:\(task.id.uuidString)")
        .contextMenu {
            Button(isFocus ? "移出 Top 3" : "设为 Top 3") { store.setFocus(task.id, on: day, isFocus: !isFocus) }
            Button("开始专注") { startFocus(task) }
            Button("移出时间轴") { store.unschedule(task.id) }
            Button("顺延到明天") {
                store.postpone(task.id, to: Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day)
            }
            Divider()
            Menu("时长") {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                    Button(DayPlanner.duration(minutes)) {
                        store.mutate(task.id, message: "已修改时长") { $0.estimatedMinutes = minutes }
                    }
                }
            }
        }
        .zIndex(selected ? 2 : 1)
    }

    private func ghostBlock(_ ghost: GhostPlacement, compact: Bool) -> some View {
        let selected = selection == .ghost(ghost.id)
        let start = ghost.minute ?? 0
        let duration = max(15, ghost.suggestion.estimatedMinutes)
        let isTop = topSuggestionIDs.contains(ghost.id)
        let layout = compact ? AnyLayout(HStackLayout(alignment: .center, spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
        return HStack(alignment: compact ? .center : .top, spacing: 8) {
            DangoTag(text: isTop ? "AI · Top" : "AI")
            Button { selection = selected ? nil : .ghost(ghost.id) } label: {
                layout {
                    Text(ghost.suggestion.title).font(Dango.font(13, .heavy)).lineLimit(compact ? 1 : 2)
                    Text("\(DayPlanner.clock(start))–\(DayPlanner.clock(start + duration)) · \(ghost.suggestion.reason)")
                        .font(Dango.font(11))
                        .foregroundStyle(Color(hex: 0x3E423B))
                        .lineLimit(compact ? 1 : 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Button("接受") { acceptGhost(ghost) }.buttonStyle(.dango(.green, small: true))
            Button("不要") { rejectGhost(ghost) }.buttonStyle(.dango(small: true))
        }
        .foregroundStyle(Dango.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 0 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dangoBlock(fill: Color.white.opacity(0.92), radius: 10, shadow: 0, highlighted: selected, dashed: true)
        .help(ghost.suggestion.reason)
        .zIndex(selected ? 2 : 1)
    }
}
