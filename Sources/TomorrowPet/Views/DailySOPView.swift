import SwiftUI

struct DailySOPView: View {
    @ObservedObject var store: DailySOPStore

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showResetConfirmation = false

    private var sections: [DailySOPSection] {
        DailySOPTemplate.sections(for: selectedDate)
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

                ForEach(sections) { section in
                    sopSection(section)
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle("每日 SOP")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
        .confirmationDialog(
            "清空这一天的全部 SOP 打卡？",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空打卡", role: .destructive) {
                withAnimation { store.reset(date: selectedDate) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清除 \(selectedDate.formatted(date: .long, time: .omitted)) 的勾选状态，不会影响普通任务。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PetFaceView(mood: completedCount == allItems.count ? .happy : .planning)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(Calendar.current.isDateInToday(selectedDate) ? "今天按节奏走" : "查看每日节奏")
                    .font(.largeTitle.bold())
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .foregroundStyle(.secondary)
                if Calendar.current.component(.weekday, from: selectedDate) == 1 {
                    Text(DailySOPTemplate.isLastSundayOfMonth(selectedDate) ? "周日计划 · 月末复盘日" : "周日计划日")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
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
                        .foregroundStyle(.teal)
                }
                ProgressView(value: progress)
                    .tint(.teal)

                HStack {
                    Text("SOP 是固定节奏，普通 Todo 继续只放需要管理的任务。")
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
            Label(section.title, systemImage: section.systemImage)
                .foregroundStyle(Color.areaColor(named: section.tintName))
        }
    }

    private func sopRow(_ item: DailySOPItem) -> some View {
        let completed = store.isCompleted(item.id, on: selectedDate)
        return Toggle(isOn: Binding(
            get: { completed },
            set: { value in
                withAnimation(.easeInOut(duration: 0.16)) {
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
                Text(completed ? "【✓】" : "【 】")
                    .font(.caption.monospaced())
                    .foregroundStyle(completed ? Color.teal : Color.secondary.opacity(0.65))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
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
