import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    let destination: SidebarDestination
    @Binding var selectedTaskID: UUID?
    var quickAddRequest: UUID

    @State private var searchText = ""
    @State private var priorityFilter: TaskPriority?
    @State private var pendingPermanentDeletion: Set<UUID> = []
    @State private var showPermanentDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            if destination != .trash && destination != .completed {
                QuickAddView(store: store, destination: destination, focusRequest: quickAddRequest) { id in
                    clearFilters()
                    selectedTaskID = id
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            if hasFilters {
                HStack(spacing: 10) {
                    Label("筛选结果 \(filteredTasks.count) 项", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    if let priorityFilter {
                        Text("\(priorityFilter.title)优先级")
                            .foregroundStyle(AppTheme.priority(priorityFilter))
                    }
                    Spacer()
                    Button("清除筛选", action: clearFilters)
                        .buttonStyle(.borderless)
                }
                .font(.caption)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            Divider().opacity(0.5)

            if filteredTasks.isEmpty {
                VStack(spacing: 0) {
                    PetEmptyState(title: emptyTitle, description: emptyDescription, systemImage: emptyIcon)
                    if hasFilters {
                        Button("显示全部任务", action: clearFilters)
                            .buttonStyle(.bordered)
                    }
                }
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
                                Button("编辑任务") {
                                    selectedTaskID = task.id
                                }
                                Divider()
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
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: store.undoAction == nil ? 0 : 64)
                }
            }
        }
        .navigationTitle(destinationTitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("优先级", selection: $priorityFilter) {
                        Text("全部优先级").tag(TaskPriority?.none)
                        ForEach(TaskPriority.allCases) { priority in
                            Text("\(priority.title)优先级").tag(TaskPriority?.some(priority))
                        }
                    }
                } label: {
                    Label("筛选优先级", systemImage: priorityFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
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
        .onChange(of: destination) { _, _ in clearFilters() }
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

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(destinationTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(store.count(for: destination)) 项")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(destinationSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }

    private var destinationSubtitle: String {
        switch destination {
        case .today: "把注意力放回今天，一次完成一件事。"
        case .tomorrow: "提前安排，让明天开始得更轻松。"
        case .inbox: "先记下来，再慢慢理清。"
        case .longTerm: "给长远的目标，留一个清晰的下一步。"
        case .waiting: "记录等待中的进展，适时跟进。"
        case .completed: "每一件完成的小事，都在推动你向前。"
        case .trash: "误删的任务可以恢复，永久删除前会再次确认。"
        default: "整理要做的事，为重要的事留出空间。"
        }
    }

    private var hasFilters: Bool { !searchText.isEmpty || priorityFilter != nil }

    private func clearFilters() {
        searchText = ""
        priorityFilter = nil
    }

    private var destinationTitle: String {
        if case .area(let areaID) = destination {
            return store.areas.first(where: { $0.id == areaID })?.name ?? "领域"
        }
        return destination.title
    }

    private var emptyTitle: String {
        if hasFilters { return "没有找到匹配的任务" }
        if destination == .completed { return "还没有已完成任务" }
        if destination == .trash { return "垃圾箱是空的" }
        return "这里暂时没有任务"
    }

    private var emptyIcon: String {
        if hasFilters { return "magnifyingglass" }
        if destination == .completed { return "checkmark.circle" }
        if destination == .trash { return "trash" }
        return "checklist"
    }

    private var emptyDescription: String {
        if hasFilters { return "试试其他关键词，或清除筛选查看全部任务。" }
        return switch destination {
        case .longTerm: "添加一个长期事项，并为它设置下一步或复查日期。"
        case .today: "今天没有安排任务，可以给自己留出休息时间。"
        case .inbox: "所有新任务都已经整理好了。"
        case .trash: "移到垃圾箱的任务会保留在这里，直到你恢复或永久删除。"
        case .sop: "每日 SOP 使用独立的打卡视图。"
        default: "使用上方输入框快速记录一件事。"
        }
    }

    private func requestPermanentDeletion(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingPermanentDeletion = ids
        showPermanentDeleteConfirmation = true
    }
}
