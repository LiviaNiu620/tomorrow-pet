import SwiftUI

struct RootView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var journal: JournalStore
    @ObservedObject var router: AppRouter
    @ObservedObject var focus: FocusTimer

    var body: some View {
        HStack(spacing: 0) {
            DangoSidebar(store: store, sopStore: sopStore, router: router, focus: focus)
                .frame(width: 224)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            ZStack {
                Dango.ground.ignoresSafeArea()
                page
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .overlay(alignment: .bottom) { undoToast }
        .overlay {
            if router.showPalette {
                CommandPalette(store: store, router: router, focus: focus)
                    .transition(.opacity)
            }
        }
        .background(Dango.ground)
        .environment(\.colorScheme, .light)
        .frame(minWidth: 1180, minHeight: 760)
        .tint(Dango.pinkDeep)
        .task(id: store.undoAction?.id) {
            guard let id = store.undoAction?.id else { return }
            try? await Task.sleep(for: .seconds(5))
            withAnimation { store.clearUndo(id: id) }
        }
        .background {
            // 键盘快捷键：⌘K 命令面板，⌘1–6 切换页面。
            Group {
                Button("") { router.showPalette.toggle() }.keyboardShortcut("k", modifiers: .command)
                ForEach(AppSection.allCases) { section in
                    Button("") { router.go(section) }
                        .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                }
                Button("") { router.showPalette = false }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch router.section {
        case .today:
            TodayView(store: store, sopStore: sopStore, calendarService: calendarService, preferences: preferences, journal: journal, router: router, focus: focus)
        case .week:
            WeekView(store: store, sopStore: sopStore, calendarService: calendarService, router: router)
        case .library:
            LibraryView(store: store, sopStore: sopStore, calendarService: calendarService, preferences: preferences, router: router)
        case .habits:
            HabitsView(sopStore: sopStore)
        case .review:
            ReviewView(store: store, sopStore: sopStore, journal: journal, router: router)
        case .focus:
            FocusView(store: store, journal: journal, router: router, focus: focus)
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let action = store.undoAction {
            HStack(spacing: 14) {
                Text(action.message)
                    .font(Dango.font(13, .bold))
                    .foregroundStyle(.white)
                Button("撤销 ⌘Z") { withAnimation { store.undoLastAction() } }
                    .buttonStyle(.dango(.pink, small: true))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Dango.ink))
            .overlay(Capsule().strokeBorder(Dango.pink, lineWidth: 2))
            .padding(.bottom, 20)
            .padding(.leading, 224)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Sidebar

struct DangoSidebar: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var router: AppRouter
    @ObservedObject var focus: FocusTimer
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                DangoMascot(mood: .happy, outline: Dango.sidebarText, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppConstants.name)
                        .font(Dango.font(18, .black))
                        .foregroundStyle(.white)
                    Text("一天一串，慢慢吃完")
                        .font(Dango.font(12))
                        .foregroundStyle(Dango.sidebarMuted)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 14)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    navButton(section)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("领域")
                    .font(Dango.font(12, .bold))
                    .foregroundStyle(Dango.sidebarMuted)
                    .padding(.horizontal, 12)
                ForEach(store.areas) { area in
                    Button {
                        router.libraryFilter = "area:\(area.id.uuidString)"
                        router.go(.library)
                    } label: {
                        HStack(spacing: 10) {
                            DangoSquareDot(fill: Dango.areaFill(area.colorName), size: 12, border: Dango.sidebarText)
                            Text(area.name).font(Dango.font(13, .semibold))
                            Spacer()
                            let count = store.activeTasks.filter { $0.areaID == area.id }.count
                            if count > 0 {
                                Text("\(count)").font(Dango.mono(12)).foregroundStyle(Dango.sidebarMuted)
                            }
                        }
                        .foregroundStyle(Dango.sidebarText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            Spacer(minLength: 8)

            petCard

            HStack {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .font(Dango.font(13, .semibold))
                        .foregroundStyle(Dango.sidebarText)
                }
                .buttonStyle(PressableStyle())
                Spacer()
                Button { router.showPalette = true } label: {
                    Text("⌘K")
                        .font(Dango.mono(11))
                        .foregroundStyle(Dango.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Dango.pink))
                }
                .buttonStyle(PressableStyle())
                .help("命令面板")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Dango.ink)
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func navButton(_ section: AppSection) -> some View {
        let selected = router.section == section
        return Button { router.go(section) } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 20)
                Text(section.title).font(Dango.font(14, .bold))
                Spacer()
                if section == .today {
                    let count = store.tasks(plannedOn: now).filter { $0.status.isActive }.count
                    if count > 0 { Text("\(count)").font(Dango.mono(12)) }
                }
                if section == .focus && (focus.isRunning || focus.hasStarted) {
                    Text(focus.clockText).font(Dango.mono(12))
                }
            }
            .foregroundStyle(selected ? Dango.ink : Dango.sidebarText)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Dango.pink : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(section.title)（⌘\(section.shortcut)）")
    }

    private var petCard: some View {
        let minute = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        let next = sopStore.items(for: now)
            .compactMap { item -> (DailySOPItem, Int)? in
                guard let start = DailySOPTemplate.startMinute(of: item.time), start > minute else { return nil }
                return (item, start)
            }
            .min { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 6) {
            Text(focus.isRunning ? "团子陪你专注中" : "团子说")
                .font(Dango.font(12))
                .foregroundStyle(Dango.sidebarMuted)
            if focus.isRunning {
                Text(focus.taskTitle.isEmpty ? "专注" : focus.taskTitle)
                    .font(Dango.font(13, .bold)).foregroundStyle(.white).lineLimit(2)
                Text(focus.clockText).font(Dango.mono(14)).foregroundStyle(Dango.pinkLight)
            } else if let next {
                Text("下一项 · \(next.0.title)")
                    .font(Dango.font(13, .bold)).foregroundStyle(.white).lineLimit(2)
                Text("\(DayPlanner.clock(next.1)) · \(DayPlanner.duration(next.1 - minute)) 后")
                    .font(Dango.mono(12)).foregroundStyle(Dango.pinkLight)
            } else {
                Text("今天的节奏走完了，早点休息。")
                    .font(Dango.font(13, .bold)).foregroundStyle(.white)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Dango.ink2))
    }
}

// MARK: - Command palette

struct CommandPalette: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var router: AppRouter
    @ObservedObject var focus: FocusTimer
    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Command: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let key: String
        let fill: Color
        let run: () -> Void
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { router.showPalette = false }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("⌘K")
                        .font(Dango.mono(12))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Dango.pink))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Dango.ink, lineWidth: 1.5))
                    TextField("输入命令，或直接写一件新任务后回车", text: $query)
                        .textFieldStyle(.plain)
                        .font(Dango.font(16))
                        .focused($focused)
                        .onSubmit(runFirst)
                    Button("Esc") { router.showPalette = false }
                        .buttonStyle(.dango(small: true))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                Rectangle().fill(Dango.ink).frame(height: 2)
                VStack(spacing: 2) {
                    ForEach(filtered) { command in
                        Button(action: command.run) {
                            HStack(spacing: 12) {
                                Text(command.icon)
                                    .font(Dango.font(12, .heavy))
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(command.fill))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Dango.ink, lineWidth: 1.5))
                                Text(command.label).font(Dango.font(14, .bold))
                                Spacer()
                                Text(command.key).font(Dango.mono(11)).foregroundStyle(Dango.muted)
                            }
                            .foregroundStyle(Dango.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PaletteRowStyle())
                    }
                    if filtered.isEmpty {
                        Text("没有匹配的命令。按回车会把「\(query)」记成新任务。")
                            .font(Dango.font(13))
                            .foregroundStyle(Dango.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .padding(8)
            }
            .dangoCard(offset: 6, padding: 0)
            .frame(width: 600)
            .padding(.top, 110)
        }
        .onAppear { focused = true }
    }

    private var commands: [Command] {
        let today = Date()
        let top = store.focusTasks(on: today).first { $0.status.isActive }
        var list: [Command] = [
            Command(icon: "+", label: "新建任务（随手记）", key: "⌥Space", fill: Dango.pink) {
                router.go(.today); router.captureFocusRequest = UUID()
            },
            Command(icon: "明", label: "去明天 · 让团子生成草稿", key: "", fill: Dango.lavender) { router.go(.today, mode: .tomorrow) },
            Command(icon: "今", label: "回到今天", key: "⌘1", fill: Dango.apricot) { router.go(.today, mode: .today) },
            Command(icon: "顺", label: "把今天没排时间的任务全部顺延到明天", key: "", fill: Color(hex: 0xC6EBDD)) {
                let calendar = Calendar.current
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
                for task in store.tasks(plannedOn: today) where task.status.isActive && task.scheduledMinute == nil {
                    store.postpone(task.id, to: tomorrow)
                }
                router.showPalette = false
            },
            Command(icon: "周", label: "打开本周", key: "⌘2", fill: Dango.sky) { router.go(.week) },
            Command(icon: "库", label: "打开任务库", key: "⌘3", fill: Dango.sky) { router.go(.library) },
            Command(icon: "习", label: "编辑 SOP 与习惯", key: "⌘4", fill: Dango.green) { router.go(.habits) },
            Command(icon: "盘", label: "打开今日复盘", key: "⌘5", fill: Color(hex: 0xE2EFBE)) { router.go(.review) }
        ]
        if let top {
            list.insert(Command(icon: "专", label: "开始专注 · \(top.title)", key: "⌘6", fill: Dango.sky) {
                focus.choose(taskID: top.id, title: top.title)
                focus.start()
                router.go(.focus)
            }, at: 2)
        } else {
            list.append(Command(icon: "专", label: "打开专注", key: "⌘6", fill: Dango.sky) { router.go(.focus) })
        }
        return list
    }

    private var filtered: [Command] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }

    private func runFirst() {
        if let first = filtered.first {
            first.run()
        } else {
            let parsed = QuickCaptureParser.parse(query, areaNames: store.areas.map(\.name))
            store.addTask(from: parsed, fallbackDate: nil)
            router.showPalette = false
        }
    }
}

private struct PaletteRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 10).fill(configuration.isPressed ? Dango.blush : Color.clear))
            .onHover { _ in }
    }
}
