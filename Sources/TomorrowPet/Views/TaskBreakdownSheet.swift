import SwiftUI

struct TaskBreakdownSheet: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var sopStore: DailySOPStore
    let task: TaskItem

    @Environment(\.dismiss) private var dismiss
    @State private var breakdown: AITaskBreakdown?
    @State private var selectedStepIDs: Set<String> = []
    @State private var editingStep: AIBreakdownStep?
    @State private var isGenerating = false
    @State private var accepted = false
    @State private var errorMessage: String?

    private let service = OpenAITaskBreakdownService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    taskSummary

                    if let breakdown {
                        resultView(breakdown)
                    } else {
                        generateView
                    }
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .navigationTitle("AI 拆解任务")
            .frame(minWidth: 760, minHeight: 650)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            await calendarService.refreshPlanningHorizon(days: 14)
        }
        .sheet(item: $editingStep) { step in
            BreakdownStepEditorView(step: step, areas: store.areas, parentDueDate: task.dueDate) { updated in
                updateStep(updated)
            }
        }
        .alert("无法拆解任务", isPresented: errorBinding) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var taskSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title).font(.title3.bold())
                if !task.notes.isEmpty { Text(task.notes).foregroundStyle(.secondary) }
                HStack(spacing: 12) {
                    Label(task.priority.title + "优先级", systemImage: "flag")
                    if let due = task.dueDate {
                        Label("截止 \(due.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.exclamationmark")
                    }
                    if let recurrence = task.recurrence {
                        Label("每 \(recurrence.interval) \(recurrence.frequency.title)", systemImage: "repeat")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("要拆解的任务", systemImage: "scope")
        }
    }

    private var generateView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("史努比会生成 3–12 个带完成标准、估时、计划日期和依赖关系的步骤。所有步骤先进入预览，你可以修改、删除或补充。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("开始 AI 拆解", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                    SettingsLink { Label("AI 设置", systemImage: "key") }
                }
                Text("已读取未来 14 天的 \(calendarService.upcomingPlanningEvents.count) 个 Calendar 安排；不会把地点、参与者或会议链接发给 OpenAI。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultView(_ value: AITaskBreakdown) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(value.summary).font(.headline)

                ForEach(value.steps) { step in
                    stepRow(step)
                    if step.id != value.steps.last?.id { Divider() }
                }

                Button {
                    addManualStep()
                } label: {
                    Label("手动补充一个步骤", systemImage: "plus")
                }

                if !value.risks.isEmpty {
                    Divider()
                    Text("风险与提醒").font(.headline)
                    ForEach(value.risks, id: \.self) { risk in
                        Label(risk, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                HStack {
                    Button(accepted ? "步骤已创建" : "确认并创建子任务") {
                        let steps = value.steps.filter { selectedStepIDs.contains($0.id) }
                        store.applyBreakdown(steps, to: task)
                        accepted = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(accepted || selectedStepIDs.isEmpty)

                    Button("重新生成") { generate() }
                        .disabled(isGenerating)
                    Spacer()
                    Text("已选择 \(selectedStepIDs.count) 项")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("拆解预览", systemImage: "list.bullet.rectangle")
        }
    }

    private func stepRow(_ step: AIBreakdownStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("选择 \(step.title)", isOn: Binding(
                get: { selectedStepIDs.contains(step.id) },
                set: { selected in
                    if selected { selectedStepIDs.insert(step.id) }
                    else { selectedStepIDs.remove(step.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(step.title).fontWeight(.semibold)
                    Text(step.area)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text("完成标准：\(step.completionCriteria)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("\(step.estimatedMinutes) 分钟")
                    if let planned = step.plannedDate {
                        Text("计划 \(planned.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if let due = step.dueDate {
                        Text("截止 \(due.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if !step.dependsOnStepIDs.isEmpty {
                        Text("依赖 \(step.dependsOnStepIDs.joined(separator: "、"))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button { editingStep = step } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("编辑步骤")
            Button(role: .destructive) { deleteStep(step.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("删除步骤")
        }
        .padding(.vertical, 4)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func generate() {
        isGenerating = true
        accepted = false
        errorMessage = nil
        Task {
            do {
                await calendarService.refreshPlanningHorizon(days: 14)
                let result = try await service.createBreakdown(
                    apiKey: KeychainService.readAPIKey(),
                    model: preferences.openAIModel,
                    task: task,
                    tasks: store.activeTasks,
                    areas: store.areas,
                    events: calendarService.upcomingPlanningEvents,
                    weeklyPlan: store.currentWeeklyPlan,
                    sopItems: sopStore.planningItems(for: .now)
                )
                breakdown = result
                selectedStepIDs = Set(result.steps.map(\.id))
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func updateStep(_ updated: AIBreakdownStep) {
        guard var value = breakdown,
              let index = value.steps.firstIndex(where: { $0.id == updated.id }) else { return }
        value.steps[index] = updated
        breakdown = value
        accepted = false
    }

    private func deleteStep(_ id: String) {
        breakdown?.steps.removeAll { $0.id == id }
        selectedStepIDs.remove(id)
        accepted = false
    }

    private func addManualStep() {
        let step = AIBreakdownStep(
            id: "manual-\(UUID().uuidString)",
            title: "新步骤",
            notes: "",
            area: store.areas.first(where: { $0.id == task.areaID })?.name ?? "未分类",
            estimatedMinutes: 30,
            priority: task.priority.rawValue,
            plannedDate: nil,
            dueDate: task.dueDate,
            completionCriteria: "明确这个步骤完成时应达到的结果",
            dependsOnStepIDs: []
        )
        breakdown?.steps.append(step)
        selectedStepIDs.insert(step.id)
        editingStep = step
        accepted = false
    }
}

private struct BreakdownStepEditorView: View {
    let areas: [TaskArea]
    let parentDueDate: Date?
    let onSave: (AIBreakdownStep) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AIBreakdownStep
    @State private var hasPlannedDate: Bool
    @State private var hasDueDate: Bool

    init(
        step: AIBreakdownStep,
        areas: [TaskArea],
        parentDueDate: Date?,
        onSave: @escaping (AIBreakdownStep) -> Void
    ) {
        self.areas = areas
        self.parentDueDate = parentDueDate
        self.onSave = onSave
        _draft = State(initialValue: step)
        _hasPlannedDate = State(initialValue: step.plannedDate != nil)
        _hasDueDate = State(initialValue: step.dueDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("步骤") {
                    TextField("步骤标题", text: $draft.title, axis: .vertical)
                    TextField("说明", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("完成标准", text: $draft.completionCriteria, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("安排") {
                    Picker("分类", selection: $draft.area) {
                        Text("未分类").tag("未分类")
                        ForEach(areas) { area in Text(area.name).tag(area.name) }
                    }
                    Picker("优先级", selection: $draft.priority) {
                        Text("高").tag("high")
                        Text("中").tag("medium")
                        Text("低").tag("low")
                        Text("无").tag("none")
                    }
                    Stepper(value: $draft.estimatedMinutes, in: 5...480, step: 5) {
                        LabeledContent("预计时长", value: "\(draft.estimatedMinutes) 分钟")
                    }
                    editableDate("计划日期", enabled: $hasPlannedDate, date: $draft.plannedDate)
                    editableDate("截止日期", enabled: $hasDueDate, date: $draft.dueDate)
                    if let parentDueDate {
                        Text("原任务截止：\(parentDueDate.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !draft.dependsOnStepIDs.isEmpty {
                    Section("依赖步骤") {
                        Text(draft.dependsOnStepIDs.joined(separator: "、"))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑拆解步骤")
            .frame(minWidth: 520, minHeight: 520)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.completionCriteria = draft.completionCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func editableDate(_ title: String, enabled: Binding<Bool>, date: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(
            get: { enabled.wrappedValue },
            set: { value in
                enabled.wrappedValue = value
                if value && date.wrappedValue == nil { date.wrappedValue = .now }
                if !value { date.wrappedValue = nil }
            }
        ))
        if enabled.wrappedValue {
            DatePicker(
                title,
                selection: Binding(get: { date.wrappedValue ?? .now }, set: { date.wrappedValue = $0 }),
                displayedComponents: [.date]
            )
            .labelsHidden()
        }
    }

    private var canSave: Bool {
        let titleOK = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let criteriaOK = !draft.completionCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let calendar = Calendar.current
        let plannedDay = calendar.startOfDay(for: draft.plannedDate ?? .now)
        let dueDay = calendar.startOfDay(for: draft.dueDate ?? .now)
        let parentDueDay = calendar.startOfDay(for: parentDueDate ?? .distantFuture)
        let dateOrderOK = !(hasPlannedDate && hasDueDate && plannedDay > dueDay)
        let parentDateOK = !(hasDueDate && parentDueDate != nil && dueDay > parentDueDay)
        return titleOK && criteriaOK && dateOrderOK && parentDateOK
    }
}
