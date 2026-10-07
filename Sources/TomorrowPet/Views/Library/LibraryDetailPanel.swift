import SwiftUI

/// 任务详情：改动即时保存；完整字段（重复、复查、标签）在「更多设置」里。
struct LibraryDetailPanel: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var router: AppRouter
    let taskID: UUID?

    @State private var newSubtask = ""
    @State private var showBreakdown = false
    @State private var showAdvanced = false
    @State private var showDuePicker = false
    @State private var confirmPermanentDelete = false

    var body: some View {
        Group {
            if let task = store.task(id: taskID) {
                if task.status == .trashed { trashed(task) } else { editor(task) }
            } else {
                VStack(spacing: 12) {
                    DangoMascot(mood: .calm, size: 48)
                    Text("点任意任务，在这里编辑").font(Dango.font(14, .heavy)).foregroundStyle(Dango.muted)
                    Text("改动会自动保存，⌘Z 可以撤销。").font(Dango.font(12)).foregroundStyle(Dango.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            }
        }
        .dangoCard(shadow: Dango.pink, padding: 20)
    }

    private func binding<T>(_ task: TaskItem, _ keyPath: WritableKeyPath<TaskItem, T>) -> Binding<T> {
        Binding(
            get: { store.task(id: task.id)?[keyPath: keyPath] ?? task[keyPath: keyPath] },
            set: { value in store.mutate(task.id, registersUndo: false) { $0[keyPath: keyPath] = value } }
        )
    }

    @ViewBuilder
    private func editor(_ task: TaskItem) -> some View {
        let area = store.area(for: task)
        let children = store.children(of: task.id)
        let focusedMinutes = JournalStore.shared.focusMinutes(for: task.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DangoSquareDot(fill: Dango.areaFill(area?.colorName))
                Text([area?.name ?? "未分类", task.project.isEmpty ? nil : task.project].compactMap { $0 }.joined(separator: " · "))
                    .font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
                Spacer()
                Text("自动保存").font(Dango.font(12, .bold)).foregroundStyle(Dango.greenText)
            }
            TextField("任务标题", text: binding(task, \.title), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Dango.font(20, .heavy))
                .lineLimit(1...4)

            FlowChips().callAsFunction {
                Menu {
                    ForEach(TaskStatus.allCases.filter { $0 != .trashed }) { status in
                        Button(status.title) {
                            if status == .completed { store.setCompleted(task.id, completed: true) }
                            else { store.mutate(task.id, message: "已修改状态") { $0.status = status } }
                        }
                    }
                } label: { DangoChip(text: "状态 · \(task.status.title)", fill: Dango.soft) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Menu {
                    Button("未分类") { store.mutate(task.id, message: "已修改领域") { $0.areaID = nil } }
                    ForEach(store.areas) { item in
                        Button(item.name) { store.mutate(task.id, message: "已修改领域") { $0.areaID = item.id } }
                    }
                } label: { DangoChip(text: "领域 · \(area?.name ?? "未分类")", fill: Dango.areaFill(area?.colorName)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                TaskDateMenu(store: store, task: task)
                Button { showDuePicker = true } label: {
                    DangoChip(text: task.dueDate.map { "截止 " + LibraryRow.dateLabel($0) } ?? "截止 · 无", fill: task.dueDate == nil ? Dango.paper : Dango.butter)
                }
                .buttonStyle(PressableStyle())
                .popover(isPresented: $showDuePicker) {
                    VStack(spacing: 10) {
                        DatePicker("截止日期", selection: Binding(
                            get: { task.dueDate ?? .now },
                            set: { value in store.mutate(task.id, message: "已修改截止日期") { $0.dueDate = value } }
                        ), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        Button("清除截止日期") {
                            store.mutate(task.id, message: "已清除截止日期") { $0.dueDate = nil }
                            showDuePicker = false
                        }
                        .buttonStyle(.dango(small: true))
                    }
                    .padding()
                }
                TaskDurationMenu(store: store, task: task)
                TaskPriorityMenu(store: store, task: task)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("项目").font(Dango.font(12, .heavy))
                TextField("比如：TGIS 修改稿", text: binding(task, \.project))
                    .textFieldStyle(.plain)
                    .font(Dango.font(13))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Dango.softer))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Dango.ink, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注").font(Dango.font(12, .heavy))
                DangoTextArea(placeholder: "写下背景、链接或完成标准", text: binding(task, \.notes), minHeight: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("子任务").font(Dango.font(12, .heavy))
                    Text("\(children.filter { $0.status == .completed }.count)/\(children.count)").font(Dango.mono(12)).foregroundStyle(Dango.muted)
                    if children.contains(where: { $0.source == .openAI }) { DangoTag(text: "AI 生成 · 可编辑") }
                }
                ForEach(children) { child in
                    let done = child.status == .completed
                    HStack(alignment: .top, spacing: 10) {
                        DangoCheck(done: done, size: 18, fill: Dango.greenDeep) { store.setCompleted(child.id, completed: !done) }
                        Text(child.title).font(Dango.font(13)).strikethrough(done)
                            .foregroundStyle(done ? Dango.faint : Dango.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let minutes = child.estimatedMinutes {
                            Text(DayPlanner.duration(minutes)).font(Dango.mono(11)).foregroundStyle(Dango.muted)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Dango.softer))
                    .contextMenu {
                        Button("打开这个子任务") { router.selectedLibraryTaskID = child.id }
                        Button("删除", role: .destructive) { store.delete([child.id]) }
                    }
                }
                HStack(spacing: 8) {
                    DangoField(placeholder: "加一个子任务", text: $newSubtask) {
                        store.addSubtask(title: newSubtask, to: task)
                        newSubtask = ""
                    }
                }
                Button(children.isEmpty ? "让团子拆解这件事" : "让团子补充步骤") { showBreakdown = true }
                    .buttonStyle(.dango(.pink))
                    .padding(.top, 4)
            }

            if let parent = task.parentTaskID.flatMap({ store.task(id: $0) }) {
                Button { router.selectedLibraryTaskID = parent.id } label: {
                    Text("属于：\(parent.title) →").font(Dango.font(12, .bold)).foregroundStyle(Dango.pinkText)
                }
                .buttonStyle(PressableStyle())
            }

            HStack(spacing: 8) {
                Button("开始专注") {
                    FocusTimer.shared.choose(taskID: task.id, title: task.title)
                    FocusTimer.shared.start()
                    router.go(.focus)
                }
                .buttonStyle(.dango(.ink, small: true))
                Button("更多设置…") { showAdvanced = true }.buttonStyle(.dango(small: true))
                Spacer()
                Button("删除") { store.delete([task.id]) }.buttonStyle(.dango(small: true))
            }

            VStack(alignment: .leading, spacing: 3) {
                DashedDivider()
                Text("来源 · \(task.source.title) · 创建于 \(task.createdAt.formatted(date: .abbreviated, time: .omitted))")
                if focusedMinutes > 0 { Text("已专注 \(DayPlanner.duration(focusedMinutes))") }
                if let count = task.postponeCount, count > 0 { Text("已顺延 \(count) 次") }
            }
            .font(Dango.font(12))
            .foregroundStyle(Dango.muted)
        }
        .sheet(isPresented: $showBreakdown) {
            TaskBreakdownSheet(store: store, calendarService: calendarService, preferences: preferences, sopStore: sopStore, task: task)
        }
        .sheet(isPresented: $showAdvanced) {
            NavigationStack {
                TaskInspectorView(store: store, calendarService: calendarService, preferences: preferences, sopStore: sopStore, task: task)
                    .navigationTitle("更多设置")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { showAdvanced = false } }
                    }
            }
            .frame(minWidth: 460, minHeight: 640)
        }
    }

    private func trashed(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DangoChip(text: "垃圾箱", fill: Dango.soft)
            Text(task.title).font(Dango.font(20, .heavy))
            if let deletedAt = task.deletedAt {
                Text("删除于 \(deletedAt.formatted(date: .abbreviated, time: .shortened)) · 原状态：\(task.trashedFromStatus?.title ?? "收件箱")")
                    .font(Dango.font(12)).foregroundStyle(Dango.muted)
            }
            HStack {
                Button("恢复任务") { store.restoreFromTrash([task.id]) }.buttonStyle(.dango(.green))
                Button("永久删除…") { confirmPermanentDelete = true }.buttonStyle(.dango())
            }
        }
        .alert("永久删除任务？", isPresented: $confirmPermanentDelete) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) { store.permanentlyDelete([task.id]) }
        } message: {
            Text("“\(task.title)”将被永久删除，且无法撤销。")
        }
    }
}

/// 自动换行的胶囊排列。
struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
