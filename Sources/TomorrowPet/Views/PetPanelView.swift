import SwiftUI

struct PetPanelView: View {
    @ObservedObject var store: TaskStore
    @State private var isExpanded = false
    @State private var quickTask = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(petMessage)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        TextField("记一件事…", text: $quickTask)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTask)
                        Button(action: addTask) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(quickTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("添加任务")
                    }

                    HStack {
                        Button("安排明天") {
                            AppWindowActivator.showMainWindow()
                            NotificationCenter.default.post(name: .openTomorrowPlanner, object: nil)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("任务中心") {
                            AppWindowActivator.showMainWindow()
                        }
                    }

                    Button("本周计划") {
                        AppWindowActivator.showMainWindow()
                        NotificationCenter.default.post(name: .openWeeklyPlanner, object: nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 270)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.3)))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                PetFaceView(mood: tomorrowCount > 0 ? .planning : .idle)
                    .frame(width: 92, height: 92)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起团子" : "打开团子")
        }
        .padding(8)
        .frame(width: 300, height: 260, alignment: .bottomTrailing)
    }

    private var tomorrowCount: Int {
        store.count(for: .tomorrow)
    }

    private var petMessage: String {
        if tomorrowCount == 0 {
            return "明天还没有选重点。要不要看看 Calendar，一起安排三件最重要的事？"
        }
        return "明天已经安排了 \(tomorrowCount) 项任务。还需要调整吗？"
    }

    private func addTask() {
        guard store.addTask(title: quickTask) != nil else { return }
        quickTask = ""
    }
}
