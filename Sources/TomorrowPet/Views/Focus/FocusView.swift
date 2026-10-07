import SwiftUI

/// 专注：番茄计时 + 当前任务的子任务 + 杂念收集（自动进收件箱）。
struct FocusView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var journal: JournalStore
    @ObservedObject var router: AppRouter
    @ObservedObject var focus: FocusTimer

    @State private var thought = ""
    @State private var captured: [(String, Date)] = []
    @State private var newSubtask = ""

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }

    var body: some View {
        ZStack {
            Dango.ink.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button("← 回到今天") { router.go(.today) }
                        .buttonStyle(.dango(.ghost, small: true))
                    Text("专注时桌宠和菜单栏会同步倒计时").font(Dango.font(13)).foregroundStyle(Dango.sidebarMuted)
                    Spacer()
                    Text("今日专注 \(DayPlanner.duration(journal.focusMinutes(on: today))) · \(journal.sessions(on: today).count) 个番茄")
                        .font(Dango.mono(13)).foregroundStyle(Dango.sidebarMuted)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                HStack(alignment: .center, spacing: 24) {
                    taskPanel.frame(width: 290)
                    timerColumn.frame(minWidth: 0, maxWidth: .infinity)
                    thoughtsPanel.frame(width: 290)
                }
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear(perform: pickDefaultTask)
    }

    private var candidates: [TaskItem] {
        let todays = store.tasks(plannedOn: today).filter { $0.status.isActive && $0.parentTaskID == nil }
        let focusIDs = Set(store.focusTasks(on: today).map(\.id))
        return todays.sorted { lhs, rhs in
            let l = focusIDs.contains(lhs.id) ? 0 : 1, r = focusIDs.contains(rhs.id) ? 0 : 1
            if l != r { return l < r }
            return (lhs.scheduledMinute ?? 9_999) < (rhs.scheduledMinute ?? 9_999)
        }
    }

    private func pickDefaultTask() {
        guard focus.taskID == nil, let first = candidates.first else { return }
        focus.choose(taskID: first.id, title: first.title)
    }

    // MARK: Task

    private var taskPanel: some View {
        let task = store.task(id: focus.taskID)
        let children = task.map { store.children(of: $0.id) } ?? []
        return VStack(alignment: .leading, spacing: 14) {
            Menu {
                ForEach(candidates) { item in
                    Button(item.title) { focus.choose(taskID: item.id, title: item.title) }
                }
                Divider()
                Button("不绑定任务") { focus.choose(taskID: nil, title: "") }
            } label: {
                HStack(spacing: 6) {
                    Text("正在做").font(Dango.font(12, .bold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Dango.sidebarMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Text(task?.title ?? (focus.taskTitle.isEmpty ? "自由专注" : focus.taskTitle))
                .font(Dango.font(20, .heavy)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let task {
                Text([task.scheduledMinute.map { "\(DayPlanner.clock($0))–\(DayPlanner.clock($0 + task.plannedDuration))" }, "预计 \(DayPlanner.duration(task.plannedDuration))",
                      journal.focusMinutes(for: task.id) > 0 ? "已专注 \(DayPlanner.duration(journal.focusMinutes(for: task.id)))" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Dango.mono(12)).foregroundStyle(Dango.pinkLight)
                VStack(spacing: 8) {
                    ForEach(children) { child in
                        let done = child.status == .completed
                        Button { store.setCompleted(child.id, completed: !done) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(done ? Dango.greenLight : Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Dango.sidebarText, lineWidth: 2))
                                    .frame(width: 18, height: 18)
                                Text(child.title).font(Dango.font(13, .bold)).strikethrough(done)
                                    .foregroundStyle(done ? Color(hex: 0x8C867E) : .white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Dango.ink2))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Dango.ink3, lineWidth: 1.5))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    darkField("拆一步：下一步具体做什么？", text: $newSubtask) {
                        store.addSubtask(title: newSubtask, to: task)
                        newSubtask = ""
                    }
                }
                .padding(.top, 6)
                Button("完成这件事 ✓") {
                    store.setCompleted(task.id, completed: true)
                    if focus.isRunning || focus.hasStarted { focus.finishEarly() }
                }
                .buttonStyle(.dango(.green, small: true))
            } else if candidates.isEmpty {
                Text("今天还没有排任务。也可以不绑定任务，单纯专注一会儿。")
                    .font(Dango.font(13)).foregroundStyle(Dango.sidebarMuted)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x2C2825)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Dango.ink3, lineWidth: 2))
    }

    // MARK: Timer

    private var timerColumn: some View {
        let sessions = journal.sessions(on: today).count
        return VStack(spacing: 18) {
            DangoMascot(mood: focus.isRunning ? .focused : (focus.justFinished ? .happy : .calm),
                        eaten: min(2, sessions % 3), outline: Dango.sidebarText, size: 120)
            Text(focus.clockText)
                .font(.system(size: 120, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(.white)
                .monospacedDigit()
                .accessibilityLabel("剩余 \(focus.remaining / 60) 分 \(focus.remaining % 60) 秒")
            Text(focus.justFinished ? "吃掉一颗团子！起来走走，休息 5 分钟" : (focus.isRunning ? "团子陪你一起，别切出去" : (focus.hasStarted ? "暂停中" : "准备好了就开始")))
                .font(Dango.font(15, .bold)).foregroundStyle(Dango.pinkLight)
            HStack(spacing: 12) {
                Button(focus.isRunning ? "暂停" : (focus.hasStarted ? "继续" : "开始专注")) { focus.toggle() }
                    .buttonStyle(DarkPinkButton())
                Button("重来") { focus.reset() }.buttonStyle(.dango(.ghost))
                Button("提前完成") { focus.finishEarly() }.buttonStyle(.dango(.ghost))
                    .disabled(!focus.hasStarted)
            }
            HStack(spacing: 8) {
                ForEach([25, 50, 90], id: \.self) { minutes in
                    let on = focus.length == minutes
                    Button("\(minutes) 分钟") { focus.setLength(minutes) }
                        .font(Dango.font(12, .heavy))
                        .foregroundStyle(on ? Dango.ink : Dango.sidebarText)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(on ? Dango.sidebarText : Color.clear))
                        .overlay(Capsule().strokeBorder(on ? Dango.sidebarText : Dango.ink3, lineWidth: 2))
                        .buttonStyle(PressableStyle())
                        .disabled(focus.isRunning)
                }
            }
            HStack(spacing: 10) {
                Text("今天这一串").font(Dango.font(12)).foregroundStyle(Dango.sidebarMuted)
                ForEach(0..<max(4, sessions), id: \.self) { index in
                    Circle()
                        .fill(index < sessions ? Dango.greenLight : Color.clear)
                        .overlay(Circle().strokeBorder(Dango.sidebarText, lineWidth: 2))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    // MARK: Thoughts

    private var thoughtsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("突然想到的事").font(Dango.font(16, .heavy)).foregroundStyle(.white)
            Text("先丢在这里，它会直接进收件箱，不用切出去。").font(Dango.font(12)).foregroundStyle(Dango.sidebarMuted)
            darkField("比如：给房东回邮件", text: $thought) {
                let text = thought.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                let parsed = QuickCaptureParser.parse(text, areaNames: store.areas.map(\.name))
                store.addTask(from: parsed, fallbackDate: nil)
                captured.insert((text, .now), at: 0)
                thought = ""
            }
            ForEach(Array(captured.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Circle().fill(Dango.pink).frame(width: 8, height: 8)
                    Text(item.0).font(Dango.font(13, .bold)).foregroundStyle(.white)
                    Spacer()
                    Text(item.1.formatted(date: .omitted, time: .shortened)).font(Dango.mono(11)).foregroundStyle(Dango.sidebarMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Dango.ink2))
            }
            let sessions = journal.sessions(on: today)
            if !sessions.isEmpty {
                DashedDivider(color: Dango.ink3).padding(.vertical, 4)
                Text("今天的番茄").font(Dango.font(12, .bold)).foregroundStyle(Dango.sidebarMuted)
                ForEach(sessions.suffix(5)) { session in
                    HStack {
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened)).font(Dango.mono(11))
                        Text(session.taskTitle).font(Dango.font(12, .semibold)).lineLimit(1)
                        Spacer()
                        Text(DayPlanner.duration(session.minutes)).font(Dango.mono(11))
                    }
                    .foregroundStyle(Dango.sidebarText)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x2C2825)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Dango.ink3, lineWidth: 2))
    }

    private func darkField(_ placeholder: String, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color(hex: 0x8C867E)))
            .textFieldStyle(.plain)
            .font(Dango.font(13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Dango.ink))
            .overlay(Capsule().strokeBorder(Dango.ink3, lineWidth: 2))
            .onSubmit(submit)
    }
}

private struct DarkPinkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Dango.font(15, .heavy))
            .foregroundStyle(Dango.ink)
            .frame(minWidth: 140)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    Capsule().fill(Dango.sidebarText).offset(x: configuration.isPressed ? 0 : 3, y: configuration.isPressed ? 0 : 3)
                    Capsule().fill(Dango.pink)
                }
            }
            .offset(x: configuration.isPressed ? 1.5 : 0, y: configuration.isPressed ? 1.5 : 0)
    }
}
