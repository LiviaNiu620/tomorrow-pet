import SwiftUI

struct QuickAddView: View {
    @ObservedObject var store: TaskStore
    let destination: SidebarDestination
    let focusRequest: UUID
    var onAdded: (UUID) -> Void

    @State private var title = ""
    @State private var areaID: UUID?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                TextField("记下一件要做的事…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isFocused)
                    .accessibilityLabel("新任务标题")
                    .onSubmit(add)
            }
            HStack(spacing: 10) {
                Picker("领域", selection: $areaID) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(store.areas) { area in
                        Text(area.name).tag(UUID?.some(area.id))
                    }
                }
                .labelsHidden()
                .frame(width: 104)
                Spacer(minLength: 0)
                Text("Return 保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("添加", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isFocused ? AppTheme.accent.opacity(0.65) : Color.secondary.opacity(0.2), lineWidth: isFocused ? 1.5 : 0.75)
        }
        .onAppear { areaID = defaultAreaID }
        .onChange(of: destination) { _, _ in areaID = defaultAreaID }
        .task(id: focusRequest) { isFocused = true }
    }

    private var defaultAreaID: UUID? {
        if case .area(let areaID) = destination { return areaID }
        return nil
    }

    private func add() {
        guard let task = store.addTask(title: title, areaID: areaID, in: destination) else { return }
        title = ""
        onAdded(task.id)
        isFocused = true
    }
}
