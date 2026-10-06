import SwiftUI

struct WeeklyPlannerView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var calendarService: CalendarService

    @State private var goals = ["", "", ""]
    @State private var notes = ""
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var savedMessage = ""

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PetPageHeader(
                        eyebrow: "本周方向",
                        title: "让这一周，有所向往。",
                        subtitle: "先定下想达成的结果，再选择值得推进的任务。",
                        systemImage: "target"
                    )
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width < 600 ? 1 : 3), spacing: 12) {
                        PetMetric(title: "本周目标", value: "\(cleanGoals.count) / 3", systemImage: "target", color: AppTheme.accent)
                        PetMetric(title: "已选任务", value: "\(selectedTaskIDs.count) 项", systemImage: "checklist")
                        PetMetric(title: "未来七天日程", value: calendarService.hasAnyCalendarAccess ? "\(calendarService.upcomingWeekEvents.count) 项" : "未连接", systemImage: "calendar")
                    }
                    PetAdaptiveColumns(availableWidth: geometry.size.width) {
                        VStack(alignment: .leading, spacing: 20) {
                            goalsCard
                            taskSelectionCard
                            notesCard
                        }
                    } secondary: {
                        weekCalendarCard
                    }
                }
                .padding(AppTheme.pageInset)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("本周计划")
        .task {
            restorePlan()
            await calendarService.refreshUpcomingWeek()
        }
        .onChange(of: goals) { _, _ in savedMessage = "" }
        .onChange(of: notes) { _, _ in savedMessage = "" }
        .onChange(of: selectedTaskIDs) { _, _ in savedMessage = "" }
    }

    private var notesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                TextField("本周风险、等待事项或想留出的空间", text: $notes, axis: .vertical)
                    .lineLimit(3...7)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("保存本周计划") { save() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(cleanGoals.isEmpty)
                    if !savedMessage.isEmpty {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.success)
                    }
                }
                if cleanGoals.isEmpty {
                    Text("写下至少一个目标，就可以保存本周计划。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("留一点余地", systemImage: "note.text")
        }
    }

    private var weekCalendarCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if calendarService.isLoading {
                    ProgressView("正在读取日历…")
                } else if !calendarService.hasAnyCalendarAccess {
                    Text("连接 Apple 或 Google Calendar 后可以预览未来七天的固定安排。")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Button("连接 Apple Calendar") {
                            Task { await calendarService.requestAppleAccessAndRefresh() }
                        }
                        SettingsLink {
                            Label("连接 Google Calendar", systemImage: "globe")
                        }
                    }
                } else if calendarService.upcomingWeekEvents.isEmpty {
                    Label("未来七天没有 Calendar 事件", systemImage: "calendar.badge.checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedEvents, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.day.formatted(.dateTime.weekday(.wide).month().day()))
                                .font(.headline)
                            ForEach(group.events) { event in
                                HStack {
                                    Text(event.isAllDay ? "全天" : event.startDate.formatted(date: .omitted, time: .shortened))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 58, alignment: .leading)
                                    Text(event.title).fixedSize(horizontal: false, vertical: true)
                                }
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
            Label("未来七天", systemImage: "calendar")
        }
    }

    private var goalsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(goals.indices, id: \.self) { index in
                    HStack {
                        Text("\(index + 1)")
                            .font(.callout.bold())
                            .frame(width: 26, height: 26)
                            .background(Color.teal.opacity(0.15), in: Circle())
                        TextField("第 \(index + 1) 个结果：完成后会有什么不同？", text: $goals[index], axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("本周目标 \(index + 1)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("本周三个结果", systemImage: "target")
        }
    }

    private var taskSelectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                if weeklyCandidates.isEmpty {
                    Text("没有需要在本周复查或即将截止的任务。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(weeklyCandidates) { task in
                        Toggle(isOn: Binding(
                            get: { selectedTaskIDs.contains(task.id) },
                            set: { selected in
                                if selected { selectedTaskIDs.insert(task.id) }
                                else { selectedTaskIDs.remove(task.id) }
                            }
                        )) {
                            HStack {
                                Text(task.title)
                                Spacer()
                                Text(store.areas.first(where: { $0.id == task.areaID })?.name ?? "未分类")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("本周要推进的任务", systemImage: "checklist")
        }
    }

    private var cleanGoals: [String] {
        goals.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var weeklyCandidates: [TaskItem] {
        let calendar = Calendar.current
        let boundary = calendar.date(byAdding: .day, value: 7, to: .now) ?? .now
        return store.activeTasks.filter { task in
            task.plannedDate.map { $0 < boundary } == true
                || task.dueDate.map { $0 < boundary } == true
                || task.reviewDate.map { $0 < boundary } == true
                || task.effectiveHorizon() == .longTerm
        }
    }

    private var groupedEvents: [(day: Date, events: [CalendarEventSummary])] {
        let groups = Dictionary(grouping: calendarService.upcomingWeekEvents) {
            Calendar.current.startOfDay(for: $0.startDate)
        }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    private func restorePlan() {
        guard let plan = store.currentWeeklyPlan else { return }
        for index in goals.indices where index < plan.goals.count {
            goals[index] = plan.goals[index]
        }
        notes = plan.notes
        selectedTaskIDs = Set(plan.selectedTaskIDs)
    }

    private func save() {
        store.storeWeeklyPlan(
            goals: cleanGoals,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedTaskIDs: Array(selectedTaskIDs)
        )
        savedMessage = "本周计划已保存"
    }
}
