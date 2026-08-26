import SwiftUI

struct QuickAddView: View {
    @ObservedObject var store: TaskStore
    var defaultAreaID: UUID?
    var onAdded: (UUID) -> Void

    @State private var title = ""
    @State private var areaID: UUID?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)

            TextField("快速添加任务，按 Return 保存", text: $title)
                .textFieldStyle(.plain)
                .onSubmit(add)

            Picker("领域", selection: $areaID) {
                Text("未分类").tag(UUID?.none)
                ForEach(store.areas) { area in
                    Text(area.name).tag(UUID?.some(area.id))
                }
            }
            .labelsHidden()
            .frame(width: 100)

            Button("添加", action: add)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if areaID == nil { areaID = defaultAreaID }
        }
        .onChange(of: defaultAreaID) { _, newValue in areaID = newValue }
    }

    private func add() {
        guard let task = store.addTask(title: title, areaID: areaID) else { return }
        title = ""
        onAdded(task.id)
    }
}
