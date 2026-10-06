import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var sopStore: DailySOPStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var calendarService: CalendarService

    @State private var destination: SidebarDestination? = .planner
    @State private var selectedTaskID: UUID?
    @State private var showInspector = true
    @State private var quickAddRequest = UUID()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selection: $destination)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 260)
        } detail: {
            Group {
                if destination == .planner {
                    TomorrowPlannerView(
                        store: store,
                        sopStore: sopStore,
                        calendarService: calendarService,
                        preferences: preferences
                    )
                } else if destination == .weekly {
                    WeeklyPlannerView(store: store, calendarService: calendarService)
                } else if destination == .sop {
                    DailySOPView(store: sopStore)
                } else if let destination {
                    TaskListView(
                        store: store,
                        destination: destination,
                        selectedTaskID: $selectedTaskID,
                        quickAddRequest: quickAddRequest
                    )
                } else {
                    ContentUnavailableView("选择一个视图", systemImage: "sidebar.left")
                }
            }
            .background(PetDetailBackground())
            .groupBoxStyle(PetGroupBoxStyle())
            .inspector(isPresented: inspectorBinding) {
                if let task = store.task(id: selectedTaskID) {
                    if task.status == .trashed {
                        TrashInspectorView(store: store, task: task)
                            .id(task.id.uuidString + task.status.rawValue)
                            .inspectorColumnWidth(min: 280, ideal: 330, max: 420)
                    } else {
                        TaskInspectorView(
                            store: store,
                            calendarService: calendarService,
                            preferences: preferences,
                            sopStore: sopStore,
                            task: task
                        )
                            .id(task.id.uuidString + task.status.rawValue)
                            .inspectorColumnWidth(min: 280, ideal: 330, max: 420)
                    }
                } else {
                    ContentUnavailableView(
                        "选择任务查看详情",
                        systemImage: "info.circle"
                    )
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let action = store.undoAction {
                HStack(spacing: 14) {
                    Text(action.message)
                    Button("撤销") {
                        withAnimation { store.undoLastAction() }
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.separator.opacity(0.5)))
                .shadow(radius: 8, y: 3)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .tint(AppTheme.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if destination != .planner && destination != .weekly && destination != .sop {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("任务详情", systemImage: "sidebar.trailing")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(selectedTaskID == nil)
                    .help(showInspector ? "隐藏任务详情" : "显示任务详情")
                }
            }
        }
        .onChange(of: destination) { _, newValue in
            selectedTaskID = nil
        }
        .onChange(of: selectedTaskID) { _, newValue in
            if newValue != nil { showInspector = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTomorrowPlanner)) { _ in
            destination = .planner
            selectedTaskID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWeeklyPlanner)) { _ in
            destination = .weekly
            selectedTaskID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDailySOP)) { _ in
            destination = .sop
            selectedTaskID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .showQuickAdd)) { _ in
            destination = .inbox
            quickAddRequest = UUID()
        }
        .task(id: store.undoAction?.id) {
            guard let id = store.undoAction?.id else { return }
            try? await Task.sleep(for: .seconds(5))
            withAnimation { store.clearUndo(id: id) }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { destination != .planner && destination != .weekly && destination != .sop && selectedTaskID != nil && showInspector },
            set: { showInspector = $0 }
        )
    }
}
