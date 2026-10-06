import SwiftUI

struct PetPanelView: View {
    @ObservedObject var store: TaskStore
    @State private var isExpanded = false
    @State private var quickTask = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 8, height: 8)
                        Text("史努比的小纸条")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(petMessage)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        TextField("记一件事…", text: $quickTask)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTask)
                        Button(action: addTask) {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .disabled(quickTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("添加任务")
                    }

                    HStack {
                        Button("安排明天") {
                            AppWindowActivator.showMainWindow()
                            NotificationCenter.default.post(name: .openTomorrowPlanner, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)

                        Button("任务中心") {
                            AppWindowActivator.showMainWindow()
                        }
                    }

                    Button {
                        AppWindowActivator.showMainWindow()
                        NotificationCenter.default.post(name: .openWeeklyPlanner, object: nil)
                    } label: {
                        Label("查看本周计划", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.sky)
                }
                .padding(16)
                .frame(width: 286)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                PetFaceView(mood: tomorrowCount > 0 ? .planning : .idle)
                    .frame(width: 106, height: 106)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起史努比" : "打开史努比")
        }
        .padding(8)
        .frame(width: 320, height: 300, alignment: .bottomTrailing)
    }

    private var tomorrowCount: Int {
        store.count(for: .tomorrow)
    }

    private var petMessage: String {
        if tomorrowCount == 0 {
            return "明天还没有选重点。让我看看 Calendar，陪你挑出三件最重要的事吧。"
        }
        return "明天已经安排了 \(tomorrowCount) 项任务。还需要调整吗？"
    }

    private func addTask() {
        guard store.addTask(title: quickTask) != nil else { return }
        quickTask = ""
    }
}
