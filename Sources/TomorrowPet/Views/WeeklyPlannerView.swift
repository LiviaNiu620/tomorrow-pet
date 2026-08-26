import SwiftUI

struct WeeklyPlannerView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var calendarService: CalendarService

    @State private var goals = ["", "", ""]
    @State private var notes = ""
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var savedMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    PetFaceView(mood: .planning)
                        .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("安排这一周")
                            .font(.largeTitle.bold())
                        Text("先看固定日程和长期事项，再只选择三个真正重要的结果。")
                            .foregroundStyle(.secondary)
                    }
                }

                weekCalendarCard
                goalsCard
                taskSelectionCard

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("本周风险、等待事项或想留出的空间", text: $notes, axis: .vertical)
                            .lineLimit(3...7)

                        HStack {
                            Button("保存本周计划") { save() }
                                .buttonStyle(.borderedProminent)
                                .disabled(cleanGoals.isEmpty)
                            if !savedMessage.isEmpty {
                                Text(savedMessage)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("备注与确认", systemImage: "checkmark.seal")
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("本周计划")
        .task {
            await calendarService.refreshUpcomingWeek()
            restorePlan()
        }
    }

    private var weekCalendarCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if !calendarService.hasAnyCalendarAccess {
                    Text("连接 Apple 或 Google Calendar 后可以预览未来七天的固定安排。")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("授权 Apple Calendar") {
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
                            ForEach(group.events.prefix(4)) { event in
                                HStack {
                                    Text(event.isAllDay ? "全天" : event.startDate.formatted(date: .omitted, time: .shortened))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 58, alignment: .leading)
                                    Text(event.title).lineLimit(1)
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
                        TextField("本周想达成的结果", text: $goals[index])
                    }
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
                    ForEach(weeklyCandidates.prefix(12)) { task in
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
