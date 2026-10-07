import SwiftUI

/// 桌面上的三色团子：平时安静，点一下随手记；专注时显示倒计时；晚上提醒规划明天。
struct PetPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject private var sopStore = DailySOPStore.shared
    @ObservedObject private var focus = FocusTimer.shared
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var isExpanded = false
    @State private var quickTask = ""
    @State private var lastAdded: String?
    @State private var snoozedUntil: Date?
    @State private var now = Date()
    @State private var hovering = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if focus.isRunning || focus.hasStarted {
                focusBubble
            } else if isExpanded {
                captureBubble
            } else if showsEveningNudge {
                eveningBubble
            } else if hovering {
                idleBubble
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { isExpanded.toggle() }
            } label: {
                DangoMascot(mood: focus.isRunning ? .focused : (isLate ? .sleepy : .happy),
                            eaten: focus.isRunning ? 1 : 0, size: 58)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .onHover { hovering = $0 }
            .accessibilityLabel(isExpanded ? "收起团子" : "打开团子")
            .padding(.trailing, 18)
        }
        .padding(8)
        .frame(width: 320, height: 300, alignment: .bottomTrailing)
        .environment(\.colorScheme, .light)
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: State

    private var minute: Int { calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now) }
    private var isLate: Bool { minute >= 23 * 60 + 40 || minute < 6 * 60 }

    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now }

    private var showsEveningNudge: Bool {
        let start = preferences.dailyHour * 60 + preferences.dailyMinute
        guard minute >= start, minute < start + 90 else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        return store.focusTasks(on: tomorrow).isEmpty
    }

    private var nextSOP: (DailySOPItem, Int)? {
        sopStore.items(for: now).compactMap { item -> (DailySOPItem, Int)? in
            guard let start = DailySOPTemplate.startMinute(of: item.time), start > minute else { return nil }
            return (item, start)
        }.min { $0.1 < $1.1 }
    }

    // MARK: Bubbles

    private func bubble<Content: View>(fill: Color = Dango.paper, shadow: Color = Dango.ink, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 270, alignment: .leading)
            .dangoCard(fill: fill, shadow: shadow, radius: 18, offset: 3, padding: 14)
            .frame(width: 290)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var idleBubble: some View {
        bubble {
            HStack(spacing: 12) {
                let total = sopStore.items(for: now).count
                let done = sopStore.items(for: now).filter { sopStore.isCompleted($0.id, on: now) }.count
                DangoRing(progress: total == 0 ? 0 : Double(done) / Double(total), lineWidth: 6)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("下一项").font(Dango.font(12, .bold)).foregroundStyle(Dango.muted)
                    Text(nextSOP.map { "\(DayPlanner.clock($0.1)) \($0.0.title)" } ?? "今天的节奏走完了")
                        .font(Dango.font(14, .heavy)).lineLimit(2)
                    Text(nextSOP.map { "\(DayPlanner.duration($0.1 - minute)) 后 · SOP \(done)/\(total)" } ?? "SOP \(done)/\(total)")
                        .font(Dango.mono(11)).foregroundStyle(Dango.pinkText)
                }
            }
        }
    }

    private var captureBubble: some View {
        bubble {
            VStack(alignment: .leading, spacing: 10) {
                Text("想到什么，丢给我").font(Dango.font(13, .heavy))
                HStack(spacing: 6) {
                    TextField("周四前回合作者邮件 #工作", text: $quickTask)
                        .textFieldStyle(.plain)
                        .font(Dango.font(13))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Dango.paper))
                        .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
                        .onSubmit(addTask)
                    Button(action: addTask) { Image(systemName: "arrow.up").font(.system(size: 12, weight: .heavy)) }
                        .buttonStyle(.dango(.pink, small: true))
                        .disabled(quickTask.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("添加任务")
                }
                if let lastAdded {
                    Text("✓ 「\(lastAdded)」已记下").font(Dango.font(12, .bold)).foregroundStyle(Dango.greenText)
                }
                HStack(spacing: 8) {
                    Button("今天") { open(.today, mode: .today) }.buttonStyle(.dango(small: true))
                    Button("安排明天") { open(.today, mode: .tomorrow) }.buttonStyle(.dango(.pink, small: true))
                    Button("专注") { open(.focus) }.buttonStyle(.dango(small: true))
                }
            }
        }
    }

    private var eveningBubble: some View {
        bubble(fill: Dango.blushSoft) {
            VStack(alignment: .leading, spacing: 10) {
                Text(DayPlanner.clock(preferences.dailyHour * 60 + preferences.dailyMinute)).font(Dango.mono(12)).foregroundStyle(Dango.pinkText)
                Text("明天还没选重点。我先看看日历，帮你排个草稿？").font(Dango.font(14, .heavy)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("去看看") { open(.today, mode: .tomorrow) }.buttonStyle(.dango(.pink, small: true))
                    Button("晚 30 分钟") { snoozedUntil = now.addingTimeInterval(30 * 60) }.buttonStyle(.dango(small: true))
                }
            }
        }
    }

    private var focusBubble: some View {
        bubble(fill: Dango.ink, shadow: Dango.pink) {
            HStack(spacing: 12) {
                Text(focus.clockText).font(Dango.mono(28)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.isRunning ? "专注中" : "暂停中").font(Dango.font(12, .bold)).foregroundStyle(Dango.pinkLight)
                    Text(focus.taskTitle.isEmpty ? "自由专注" : focus.taskTitle).font(Dango.font(13, .heavy)).foregroundStyle(.white).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button { focus.toggle() } label: {
                    Image(systemName: focus.isRunning ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .heavy))
                }
                .buttonStyle(.dango(.pink, small: true))
                .accessibilityLabel(focus.isRunning ? "暂停" : "继续")
            }
        }
    }

    private func open(_ section: AppSection, mode: DayMode? = nil) {
        AppWindowActivator.showMainWindow()
        AppRouter.shared.go(section, mode: mode)
        withAnimation { isExpanded = false }
    }

    private func addTask() {
        let parsed = QuickCaptureParser.parse(quickTask, areaNames: store.areas.map(\.name))
        guard let task = store.addTask(from: parsed, fallbackDate: nil) else { return }
        lastAdded = task.title
        quickTask = ""
    }
}
