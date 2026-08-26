import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    let destination: SidebarDestination
    @Binding var selectedTaskID: UUID?

    @State private var searchText = ""
    @State private var priorityFilter: TaskPriority?
    @State private var pendingPermanentDeletion: Set<UUID> = []
    @State private var showPermanentDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if destination != .trash {
                QuickAddView(store: store, defaultAreaID: defaultAreaID) { id in
                    selectedTaskID = id
                }
                .padding([.horizontal, .top])
            }

            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptyIcon,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedTaskID) {
                    ForEach(filteredTasks) { task in
                        TaskRowView(
                            task: task,
                            area: store.areas.first { $0.id == task.areaID },
                            allowsCompletion: destination != .trash,
                            toggleCompleted: {
                                store.setCompleted(task.id, completed: task.status != .completed)
                            }
                        )
                        .tag(task.id)
                        .contextMenu {
                            if destination == .trash {
                                Button("恢复任务") {
                                    store.restoreFromTrash([task.id])
                                    if selectedTaskID == task.id { selectedTaskID = nil }
                                }
                                Button("永久删除…", role: .destructive) {
                                    requestPermanentDeletion([task.id])
                                }
                            } else {
                                Button(task.status == .completed ? "标记为未完成" : "标记完成") {
                                    store.setCompleted(task.id, completed: task.status != .completed)
                                }
                                Divider()
                                Button("移到垃圾箱", role: .destructive) {
                                    store.delete([task.id])
                                    if selectedTaskID == task.id { selectedTaskID = nil }
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { filteredTasks[$0].id })
                        if destination == .trash {
                            requestPermanentDeletion(ids)
                        } else {
                            store.delete(ids)
                        }
                        if let selectedTaskID, ids.contains(selectedTaskID) { self.selectedTaskID = nil }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(destinationTitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("全部优先级") { priorityFilter = nil }
                    Divider()
                    ForEach(TaskPriority.allCases.filter { $0 != .none }) { priority in
                        Button(priority.title) { priorityFilter = priority }
                    }
                } label: {
                    Label("筛选优先级", systemImage: "line.3.horizontal.decrease.circle")
                }

                if destination == .trash && !filteredTasks.isEmpty {
                    Button(role: .destructive) {
                        showEmptyTrashConfirmation = true
                    } label: {
                        Label("清空垃圾箱", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("永久删除任务？", isPresented: $showPermanentDeleteConfirmation) {
            Button("取消", role: .cancel) { pendingPermanentDeletion = [] }
            Button("永久删除", role: .destructive) {
                store.permanentlyDelete(pendingPermanentDeletion)
                pendingPermanentDeletion = []
                selectedTaskID = nil
            }
        } message: {
            Text("这将永久删除选中的 \(pendingPermanentDeletion.count) 个任务，且无法撤销。")
        }
        .alert("清空垃圾箱？", isPresented: $showEmptyTrashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("全部永久删除", role: .destructive) {
                store.emptyTrash()
                selectedTaskID = nil
            }
        } message: {
            Text("垃圾箱中的 \(store.count(for: .trash)) 个任务将被永久删除，且无法撤销。")
        }
    }

    private var filteredTasks: [TaskItem] {
        store.tasks(for: destination).filter { task in
            let matchesSearch = searchText.isEmpty
                || task.title.localizedCaseInsensitiveContains(searchText)
                || task.notes.localizedCaseInsensitiveContains(searchText)
                || task.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            let matchesPriority = priorityFilter == nil || task.priority == priorityFilter
            return matchesSearch && matchesPriority
        }
    }

    private var defaultAreaID: UUID? {
        if case .area(let areaID) = destination { return areaID }
        return nil
    }

    private var destinationTitle: String {
        if case .area(let areaID) = destination {
            return store.areas.first(where: { $0.id == areaID })?.name ?? "领域"
        }
        return destination.title
    }

    private var emptyTitle: String {
        if destination == .completed { return "还没有已完成任务" }
        if destination == .trash { return "垃圾箱是空的" }
        return "这里暂时没有任务"
    }

    private var emptyIcon: String {
        if destination == .completed { return "checkmark.circle" }
        if destination == .trash { return "trash" }
        return "checklist"
    }

    private var emptyDescription: String {
        switch destination {
        case .longTerm: "添加一个长期事项，并为它设置下一步或复查日期。"
        case .today: "今天没有安排任务，可以给自己留出休息时间。"
        case .inbox: "所有新任务都已经整理好了。"
        case .trash: "移到垃圾箱的任务会保留在这里，直到你恢复或永久删除。"
        default: "使用上方输入框快速记录一件事。"
        }
    }

    private func requestPermanentDeletion(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingPermanentDeletion = ids
        showPermanentDeleteConfirmation = true
    }
}
