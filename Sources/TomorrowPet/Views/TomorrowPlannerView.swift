import SwiftUI

struct TomorrowPlannerView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var preferences: AppPreferences

    @State private var generatedPlan: AIPlanSuggestion?
    @State private var selectedSuggestionIDs: Set<UUID> = []
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var accepted = false
    @State private var editingSuggestion: AISuggestedTask?
    @AppStorage("tomorrowPlannerAdditionalInput") private var additionalInput = ""

    private let planningService = OpenAIPlanningService()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width < 600 ? 1 : 3), spacing: 12) {
                        PetMetric(title: "固定日程", value: calendarService.hasAnyCalendarAccess ? "\(calendarService.tomorrowEvents.count) 项" : "未连接", systemImage: "calendar")
                        PetMetric(title: "任务候选", value: "\(candidateTasks.count) 项", systemImage: "checklist")
                        PetMetric(title: "明日重点", value: "最多 3 项", systemImage: "scope", color: AppTheme.accent)
                    }
                    PetAdaptiveColumns(availableWidth: geometry.size.width) {
                        VStack(alignment: .leading, spacing: 20) {
                            additionalInputCard
                            if let generatedPlan {
                                planCard(generatedPlan)
                            } else {
                                generateCard
                            }
                        }
                    } secondary: {
                        VStack(alignment: .leading, spacing: 20) {
                            calendarCard
                            weeklyDirectionCard
                            taskCandidatesCard
                        }
                    }
                }
                .padding(AppTheme.pageInset)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("明日 AI 计划")
        .task {
            await calendarService.refreshTomorrow()
            if let stored = store.lastAIPlan,
               Calendar.current.isDate(stored.date, inSameDayAs: tomorrow) {
                generatedPlan = stored.plan
                selectedSuggestionIDs = Set((stored.plan.topThree + stored.plan.additionalTasks).map(\.id))
            }
        }
        .alert("无法生成计划", isPresented: errorBinding) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .sheet(item: $editingSuggestion) { suggestion in
            AISuggestionEditorView(suggestion: suggestion, areas: store.areas) { updated in
                updateSuggestion(updated)
            }
        }
    }

    private var header: some View {
        PetPageHeader(
            eyebrow: tomorrow.formatted(date: .complete, time: .omitted),
            title: "给明天，留一点从容。",
            subtitle: "选好三个重点，给重要的事留出时间。计划由你确认后保存。"
        )
    }

    private var calendarCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if calendarService.isLoading {
                    ProgressView("正在读取 Calendar…")
                } else if !calendarService.hasAnyCalendarAccess {
                    Text("连接日历，把固定安排一起纳入计划。也可以直接根据任务库开始规划。")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Button("连接 Apple Calendar") {
                            Task { await calendarService.requestAppleAccessAndRefresh() }
                        }
                        .buttonStyle(.bordered)
                        SettingsLink {
                            Label("连接 Google Calendar", systemImage: "globe")
                        }
                    }
                } else if calendarService.tomorrowEvents.isEmpty {
                    Label("明天没有 Calendar 事件", systemImage: "calendar.badge.checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendarService.tomorrowEvents) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Text(event.isAllDay ? "全天" : event.startDate.formatted(date: .omitted, time: .shortened))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).fontWeight(.medium)
                                Text(event.calendarTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let message = calendarService.errorMessage,
                   calendarService.hasAnyCalendarAccess {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("明天的固定安排", systemImage: "calendar")
        }
    }

    private var taskCandidatesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if candidateTasks.isEmpty {
                    Text("任务库目前没有活动任务。你仍然可以让 AI 根据 Calendar 建议准备事项，或先到任务中心添加任务。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidateTasks.prefix(8)) { task in
                        HStack {
                            Text(task.title)
                            Spacer()
                            Text(store.areas.first(where: { $0.id == task.areaID })?.name ?? "未分类")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let minutes = task.estimatedMinutes {
                                Text("\(minutes)m")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if candidateTasks.count > 8 {
                        Text("另有 \(candidateTasks.count - 8) 项活动任务会提供给 AI 做取舍。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("任务候选", systemImage: "checklist")
        }
    }

    private var additionalInputCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $additionalInput)
                        .font(.body)
                        .frame(minHeight: 96, maxHeight: 150)
                        .accessibilityLabel("明日补充事项")
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

                    if additionalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("例如：\n给导师回复实验进度\n买猫粮\n整理周五汇报的三张图")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("建议一行写一件事，最多 20 条。AI 会整理分类、优先级和估时；确认计划后才会创建任务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !additionalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("约 \(additionalInputLineCount) 条")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(additionalInputLineCount > 20 ? Color.red : Color.secondary)
                        Button("清空") { additionalInput = "" }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("明日补充事项", systemImage: "square.and.pencil")
        }
    }

    @ViewBuilder
    private var weeklyDirectionCard: some View {
        if let plan = store.currentWeeklyPlan,
           !plan.goals.isEmpty || !plan.selectedTaskIDs.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.goals.prefix(3).enumerated()), id: \.offset) { index, goal in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 20, height: 20)
                                .background(Color.teal.opacity(0.15), in: Circle())
                            Text(goal)
                        }
                    }
                    if !plan.selectedTaskIDs.isEmpty {
                        Text("AI 还会优先识别本周已选的 \(plan.selectedTaskIDs.count) 项推进任务，但不会忽略截止日期和日历负荷。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("本周方向", systemImage: "target")
            }
        }
    }

    private var generateCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("把精力留给最重要的事", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                Text("结合任务、日历与每日节奏，为你挑选重点并估算用时。生成后可以编辑和取舍。")
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        generatePlan()
                    } label: {
                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在规划明天…")
                            }
                        } else {
                            Label("生成明日计划", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGenerating || additionalInputLineCount > 20)

                    SettingsLink {
                        Label("AI 设置", systemImage: "slider.horizontal.3")
                    }
                }
                Text("首次使用请在 AI 设置中填写 API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func planCard(_ plan: AIPlanSuggestion) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text(plan.summary)
                    .font(.title3.weight(.semibold))

                Text("明天的三个重点")
                    .font(.headline)
                ForEach(plan.topThree) { suggestion in
                    suggestionRow(suggestion, isFocus: true)
                }

                if !plan.additionalTasks.isEmpty {
                    Divider()
                    Text("其他任务与补充事项")
                        .font(.headline)
                    ForEach(plan.additionalTasks) { suggestion in
                        suggestionRow(suggestion, isFocus: false)
                    }
                }

                Divider()
                Label(plan.workloadAssessment, systemImage: "gauge.with.dots.needle.50percent")
                if !plan.notes.isEmpty {
                    Text(plan.notes)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(accepted ? "计划已保存" : "确认并加入明天") {
                        accept(plan)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(accepted || isGenerating || selectedSuggestionIDs.isEmpty)

                    Button(isGenerating ? "正在重新生成…" : "重新生成") { generatePlan() }
                        .disabled(isGenerating || additionalInputLineCount > 20)

                    Spacer()
                    Text("已选择 \(selectedSuggestionIDs.count) 项")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("团子的明日建议", systemImage: "sparkles")
        }
    }

    private func suggestionRow(_ suggestion: AISuggestedTask, isFocus: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("选择 \(suggestion.title)", isOn: Binding(
                get: { selectedSuggestionIDs.contains(suggestion.id) },
                set: { selected in
                    if selected { selectedSuggestionIDs.insert(suggestion.id) }
                    else { selectedSuggestionIDs.remove(suggestion.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title).fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(suggestion.area)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text("\(suggestion.estimatedMinutes) 分钟")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestionSourceText(suggestion))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button {
                editingSuggestion = suggestion
            } label: {
                Label("编辑建议", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("确认前编辑任务内容、分类、优先级和估时")
            .disabled(isGenerating)
        }
        .accessibilityHint(isFocus ? "明日重点任务" : "额外候选任务")
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private var candidateTasks: [TaskItem] {
        store.activeTasks.sorted { lhs, rhs in
            let left = lhs.dueDate ?? lhs.plannedDate ?? .distantFuture
            let right = rhs.dueDate ?? rhs.plannedDate ?? .distantFuture
            if left != right { return left < right }
            return lhs.priority < rhs.priority
        }
    }

    private var additionalInputLineCount: Int {
        additionalInput.split(whereSeparator: \Character.isNewline).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func generatePlan() {
        isGenerating = true
        errorMessage = nil
        accepted = false
        Task {
            do {
                await calendarService.refreshTomorrow()
                let userInputItems = try OpenAIPlanningService.additionalInputItems(from: additionalInput)
                let plan = try await planningService.createTomorrowPlan(
                    apiKey: KeychainService.readAPIKey(),
                    model: preferences.openAIModel,
                    tomorrow: tomorrow,
                    tasks: store.activeTasks,
                    areas: store.areas,
                    events: calendarService.tomorrowEvents,
                    weeklyPlan: store.currentWeeklyPlan,
                    sopItems: sopStore.planningItems(for: tomorrow),
                    userInputItems: userInputItems
                )
                generatedPlan = plan
                selectedSuggestionIDs = Set((plan.topThree + plan.additionalTasks).map(\.id))
                store.store(plan: plan, for: tomorrow)
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func updateSuggestion(_ updated: AISuggestedTask) {
        guard var plan = generatedPlan else { return }
        if let index = plan.topThree.firstIndex(where: { $0.id == updated.id }) {
            plan.topThree[index] = updated
        } else if let index = plan.additionalTasks.firstIndex(where: { $0.id == updated.id }) {
            plan.additionalTasks[index] = updated
        } else {
            return
        }
        generatedPlan = plan
        store.store(plan: plan, for: tomorrow)
        accepted = false
    }

    private func accept(_ plan: AIPlanSuggestion) {
        let top = plan.topThree.filter { selectedSuggestionIDs.contains($0.id) }
        let additional = plan.additionalTasks.filter { selectedSuggestionIDs.contains($0.id) }
        store.apply(top, to: tomorrow, markAsFocus: true)
        store.apply(additional, to: tomorrow, markAsFocus: false)
        let userSuggestions = (plan.topThree + plan.additionalTasks).filter { $0.source == "user_input" }
        if !userSuggestions.isEmpty,
           userSuggestions.allSatisfy({ selectedSuggestionIDs.contains($0.id) }) {
            additionalInput = ""
        }
        accepted = true
    }

    private func suggestionSourceText(_ suggestion: AISuggestedTask) -> String {
        switch suggestion.source {
        case "calendar_preparation": "AI 根据 Calendar 建议"
        case "user_input": "来自你的补充事项 · 确认后创建任务"
        default: "来自任务库"
        }
    }
}

private struct AISuggestionEditorView: View {
    let areas: [TaskArea]
    let onSave: (AISuggestedTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AISuggestedTask

    init(suggestion: AISuggestedTask, areas: [TaskArea], onSave: @escaping (AISuggestedTask) -> Void) {
        self.areas = areas
        self.onSave = onSave
        _draft = State(initialValue: suggestion)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务内容") {
                    TextField("任务标题", text: $draft.title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("规划理由或说明", text: $draft.reason, axis: .vertical)
                        .lineLimit(2...5)
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
                }
                Section {
                    Text("任务来源与内部映射不会被修改；你的编辑会在确认计划时写入任务库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑 AI 建议")
            .frame(minWidth: 480, minHeight: 430)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
