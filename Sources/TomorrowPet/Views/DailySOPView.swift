import SwiftUI

struct DailySOPView: View {
    @ObservedObject var store: DailySOPStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showResetConfirmation = false
    @State private var showTemplateEditor = false

    private var sections: [DailySOPSection] {
        store.sections(for: selectedDate)
    }

    private var allItems: [DailySOPItem] {
        sections.flatMap(\.items)
    }

    private var completedCount: Int {
        allItems.lazy.filter { store.isCompleted($0.id, on: selectedDate) }.count
    }

    private var progress: Double {
        guard !allItems.isEmpty else { return 0 }
        return Double(completedCount) / Double(allItems.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                progressCard

                if sections.isEmpty {
                    PetEmptyState(title: "从一个小习惯开始", description: "点击工具栏的“编辑 SOP”，为每天建立自己的节奏。", systemImage: "leaf")
                        .frame(maxWidth: .infinity)
                }
                ForEach(sections) { section in
                    sopSection(section)
                }
            }
            .padding(AppTheme.pageInset)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("每日 SOP")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showTemplateEditor = true
                } label: {
                    Label("编辑 SOP", systemImage: "square.and.pencil")
                }

                Button {
                    moveDay(-1)
                } label: {
                    Label("前一天", systemImage: "chevron.left")
                }

                Button("今天") {
                    selectedDate = Calendar.current.startOfDay(for: .now)
                }
                .disabled(Calendar.current.isDateInToday(selectedDate))

                Button {
                    moveDay(1)
                } label: {
                    Label("后一天", systemImage: "chevron.right")
                }
            }
        }
        .sheet(isPresented: $showTemplateEditor) {
            SOPTemplateEditorView(store: store)
        }
        .confirmationDialog(
            "清空这一天的全部 SOP 打卡？",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空打卡", role: .destructive) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { store.reset(date: selectedDate) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清除 \(selectedDate.formatted(date: .long, time: .omitted)) 的勾选状态，不会影响普通任务。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetPageHeader(
                eyebrow: selectedDate.formatted(date: .complete, time: .omitted),
                title: Calendar.current.isDateInToday(selectedDate) ? "今天，也按自己的节奏。" : "回到这一天的节奏。",
                subtitle: "照顾好日常的小事，给自己稳定的支持。",
                systemImage: "leaf"
            )
            if Calendar.current.component(.weekday, from: selectedDate) == 1 {
                PetStatusPill(
                    text: DailySOPTemplate.isLastSundayOfMonth(selectedDate) ? "周日计划 · 月末复盘日" : "周日计划日",
                    systemImage: "calendar.badge.clock"
                )
            }
        }
    }

    private var progressCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("完成 \(completedCount) / \(allItems.count)")
                        .font(.headline)
                    Spacer()
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.success)
                }
                ProgressView(value: progress)
                    .tint(AppTheme.success)
                    .accessibilityLabel("当日 SOP 完成进度")

                HStack {
                    Text("日常习惯在这里打卡，专注任务在任务列表推进。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if completedCount > 0 {
                        Button("清空当天打卡", role: .destructive) {
                            showResetConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sopSection(_ section: DailySOPSection) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    sopRow(item)
                    if index < section.items.count - 1 {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Label(section.title, systemImage: section.systemImage)
                Spacer()
                Text("\(section.items.filter { store.isCompleted($0.id, on: selectedDate) }.count) / \(section.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sopRow(_ item: DailySOPItem) -> some View {
        let completed = store.isCompleted(item.id, on: selectedDate)
        return Toggle(isOn: Binding(
            get: { completed },
            set: { value in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    store.setCompleted(item.id, completed: value, on: selectedDate)
                }
            }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let time = item.time {
                    Text(time)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 94, alignment: .leading)
                } else {
                    Spacer().frame(width: 94)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .strikethrough(completed, color: .secondary)
                        .foregroundStyle(completed ? .secondary : .primary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(item.time.map { "\($0)，" } ?? "")\(item.title)")
    }

    private func moveDay(_ offset: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = Calendar.current.startOfDay(for: date)
        }
    }
}
