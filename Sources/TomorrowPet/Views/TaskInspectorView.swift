import SwiftUI

struct TaskInspectorView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var sopStore: DailySOPStore
    let task: TaskItem

    @State private var draft: TaskItem
    @State private var hasDueDate: Bool
    @State private var hasPlannedDate: Bool
    @State private var hasReviewDate: Bool
    @State private var hasRecurrenceEndDate: Bool
    @State private var tagsText: String
    @State private var showBreakdown = false

    init(
        store: TaskStore,
        calendarService: CalendarService,
        preferences: AppPreferences,
        sopStore: DailySOPStore,
        task: TaskItem
    ) {
        self.store = store
        self.calendarService = calendarService
        self.preferences = preferences
        self.sopStore = sopStore
        self.task = task
        _draft = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _hasPlannedDate = State(initialValue: task.plannedDate != nil)
        _hasReviewDate = State(initialValue: task.reviewDate != nil)
        _hasRecurrenceEndDate = State(initialValue: task.recurrence?.endDate != nil)
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("任务") {
                TextField("任务标题", text: $draft.title, axis: .vertical)
                    .font(.headline)
                    .lineLimit(1...4)

                Picker("状态", selection: $draft.status) {
                    ForEach(TaskStatus.allCases.filter { $0 != .trashed }) { status in
                        Text(status.title).tag(status)
                    }
                }

                Picker("领域", selection: $draft.areaID) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(store.areas) { area in
                        Text(area.name).tag(UUID?.some(area.id))
                    }
                }

                Picker("时间层级", selection: $draft.manualHorizon) {
                    Text("自动判断").tag(TaskHorizon?.none)
                    ForEach(TaskHorizon.allCases) { horizon in
                        Text(horizon.title).tag(TaskHorizon?.some(horizon))
                    }
                }

                Picker("优先级", selection: $draft.priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }

                TextField("项目（可选）", text: $draft.project)
            }

            Section("安排") {
                OptionalDateRow(
                    title: "计划日期",
                    isEnabled: $hasPlannedDate,
                    date: Binding(
                        get: { draft.plannedDate ?? .now },
                        set: { draft.plannedDate = $0 }
                    )
                )
                OptionalDateRow(
                    title: "截止日期",
                    isEnabled: $hasDueDate,
                    date: Binding(
                        get: { draft.dueDate ?? .now },
                        set: { draft.dueDate = $0 }
                    )
                )
                OptionalDateRow(
                    title: "复查日期",
                    isEnabled: $hasReviewDate,
                    date: Binding(
                        get: { draft.reviewDate ?? .now },
                        set: { draft.reviewDate = $0 }
                    )
                )

                Stepper(value: estimatedMinutes, in: 0...480, step: 5) {
                    HStack {
                        Text("预计时长")
                        Spacer()
                        Text(draft.estimatedMinutes.map { "\($0) 分钟" } ?? "未设置")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("重复") {
                Toggle("重复任务", isOn: isRecurring)
                if draft.recurrence != nil {
                    HStack {
                        Text("每")
                        Stepper(value: recurrenceInterval, in: 1...99) {
                            Text("\(draft.recurrence?.interval ?? 1)")
                                .monospacedDigit()
                        }
                        .frame(maxWidth: 120)
                        Picker("周期", selection: recurrenceFrequency) {
                            ForEach(RecurrenceFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        Spacer()
                    }

                    if draft.recurrence?.frequency == .weekly {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("重复星期")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(Self.weekdays, id: \.value) { weekday in
                                    Toggle(weekday.title, isOn: weekdayBinding(weekday.value))
                                        .toggleStyle(.button)
                                        .controlSize(.small)
                                }
                            }
                            Text("不选择星期时，将按当前任务的星期重复。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    OptionalDateRow(
                        title: "结束日期",
                        isEnabled: $hasRecurrenceEndDate,
                        date: Binding(
                            get: { draft.recurrence?.endDate ?? .now },
                            set: { draft.recurrence?.endDate = $0 }
                        )
                    )
                    Text("标记完成后会创建下一次任务，已完成的记录会保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("补充信息") {
                TextField("标签，用逗号分隔", text: $tagsText)
                TextField("备注", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...8)
                LabeledContent("来源", value: draft.source.title)
            }

            if let parentID = draft.parentTaskID,
               let parent = store.task(id: parentID) {
                Section("关联任务") {
                    LabeledContent("父任务", value: parent.title)
                }
            }

            let childCount = store.tasks.lazy.filter { $0.parentTaskID == draft.id && $0.status != .trashed }.count
            Section("AI 规划") {
                if childCount > 0 {
                    LabeledContent("已拆解步骤", value: "\(childCount) 项")
                }
                Button {
                    save()
                    showBreakdown = true
                } label: {
                    Label(childCount > 0 ? "继续 AI 拆解或补充步骤" : "AI 自动拆解和规划", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                Text("AI 会参考任务期限、周期、现有任务、Calendar、本周计划和每日 SOP。生成后可逐项编辑，确认前不会写入任务库。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("保存更改") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("移到垃圾箱", role: .destructive) {
                    store.delete([draft.id])
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: hasDueDate) { _, enabled in
            if enabled && draft.dueDate == nil { draft.dueDate = .now }
            if !enabled { draft.dueDate = nil }
        }
        .onChange(of: hasPlannedDate) { _, enabled in
            if enabled && draft.plannedDate == nil { draft.plannedDate = .now }
            if !enabled { draft.plannedDate = nil }
        }
        .onChange(of: hasReviewDate) { _, enabled in
            if enabled && draft.reviewDate == nil { draft.reviewDate = .now }
            if !enabled { draft.reviewDate = nil }
        }
        .onChange(of: hasRecurrenceEndDate) { _, enabled in
            if enabled && draft.recurrence?.endDate == nil {
                let base = draft.plannedDate ?? draft.dueDate ?? .now
                draft.recurrence?.endDate = Calendar.current.date(byAdding: .month, value: 1, to: base) ?? base
            }
            if !enabled { draft.recurrence?.endDate = nil }
        }
        .sheet(isPresented: $showBreakdown) {
            TaskBreakdownSheet(
                store: store,
                calendarService: calendarService,
                preferences: preferences,
                sopStore: sopStore,
                task: store.task(id: draft.id) ?? draft
            )
        }
    }

    private var estimatedMinutes: Binding<Int> {
        Binding(
            get: { draft.estimatedMinutes ?? 0 },
            set: { draft.estimatedMinutes = $0 == 0 ? nil : $0 }
        )
    }

    private var isRecurring: Binding<Bool> {
        Binding(
            get: { draft.recurrence != nil },
            set: { enabled in
                if enabled {
                    draft.recurrence = draft.recurrence ?? RecurrenceRule()
                } else {
                    draft.recurrence = nil
                    hasRecurrenceEndDate = false
                }
            }
        )
    }

    private var recurrenceFrequency: Binding<RecurrenceFrequency> {
        Binding(
            get: { draft.recurrence?.frequency ?? .daily },
            set: { draft.recurrence?.frequency = $0 }
        )
    }

    private var recurrenceInterval: Binding<Int> {
        Binding(
            get: { draft.recurrence?.interval ?? 1 },
            set: { draft.recurrence?.interval = max(1, $0) }
        )
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { draft.recurrence?.weekdays.contains(weekday) == true },
            set: { selected in
                if selected {
                    draft.recurrence?.weekdays.insert(weekday)
                } else {
                    draft.recurrence?.weekdays.remove(weekday)
                }
            }
        )
    }

    private static let weekdays: [(title: String, value: Int)] = [
        ("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1)
    ]

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if draft.status == .completed && draft.completedAt == nil { draft.completedAt = .now }
        if draft.status != .completed { draft.completedAt = nil }
        store.update(draft)
    }
}

struct TrashInspectorView: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem

    @State private var showPermanentDeleteConfirmation = false

    var body: some View {
        Form {
            Section("已删除任务") {
                Text(task.title)
                    .font(.headline)
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("原状态", value: task.trashedFromStatus?.title ?? "收件箱")
                if let deletedAt = task.deletedAt {
                    LabeledContent("移入时间", value: deletedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section {
                Button("恢复任务") {
                    store.restoreFromTrash([task.id])
                }
                .buttonStyle(.borderedProminent)

                Button("永久删除…", role: .destructive) {
                    showPermanentDeleteConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .alert("永久删除任务？", isPresented: $showPermanentDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                store.permanentlyDelete([task.id])
            }
        } message: {
            Text("“\(task.title)”将被永久删除，且无法撤销。")
        }
    }
}

private struct OptionalDateRow: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $isEnabled)
            if isEnabled {
                DatePicker(title, selection: $date, displayedComponents: [.date])
                    .labelsHidden()
            }
        }
    }
}
