import SwiftUI

struct SOPTemplateEditorView: View {
    @ObservedObject var store: DailySOPStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: DailySOPConfiguration
    @State private var showRestoreConfirmation = false

    init(store: DailySOPStore) {
        self.store = store
        _draft = State(initialValue: store.configuration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("在这里修改每天会出现的固定节奏。编辑模板不会清空任何历史打卡；新步骤会获得稳定标识。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("每日分组") {
                    ForEach($draft.dailySections) { $section in
                        SOPSectionEditor(section: $section, allowsSectionDeletion: true) {
                            draft.dailySections.removeAll { $0.id == section.id }
                        }
                    }
                    Button {
                        draft.dailySections.append(Self.newSection())
                    } label: {
                        Label("添加每日分组", systemImage: "plus")
                    }
                }

                Section("周日额外计划") {
                    SOPSectionEditor(section: $draft.sundaySection)
                }

                Section("月末额外计划") {
                    SOPSectionEditor(section: $draft.monthlySection)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑每日 SOP")
            .frame(minWidth: 650, minHeight: 620)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem {
                    Button("恢复默认…", role: .destructive) {
                        showRestoreConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateConfiguration(draft)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .confirmationDialog("恢复默认 SOP 模板？", isPresented: $showRestoreConfirmation) {
            Button("恢复默认", role: .destructive) {
                draft = DailySOPTemplate.defaultConfiguration
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会替换正在编辑的模板；点击“保存”后才会生效，历史打卡不会被删除。")
        }
    }

    private static func newSection() -> DailySOPSection {
        let id = "section-\(UUID().uuidString)"
        return DailySOPSection(
            id: id,
            title: "新分组",
            systemImage: "list.bullet.circle.fill",
            tintName: "teal",
            items: []
        )
    }
}

private struct SOPSectionEditor: View {
    @Binding var section: DailySOPSection
    var allowsSectionDeletion = false
    var deleteSection: (() -> Void)?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                TextField("分组名称", text: $section.title)
                    .font(.headline)

                ForEach($section.items) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("时间，例如 08:20 或 20:00–20:30", text: optionalText($item.time))
                                .frame(width: 210)
                            TextField("步骤内容", text: $item.title)
                            Button(role: .destructive) {
                                section.items.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("删除这个 SOP 步骤")
                        }
                        TextField("说明（可选）", text: optionalText($item.detail), axis: .vertical)
                            .lineLimit(1...3)
                        Toggle("提供给 AI 作为固定时间与负荷参考", isOn: $item.isPlanningContext)
                            .font(.caption)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                }

                HStack {
                    Button {
                        section.items.append(Self.newItem(section: section))
                    } label: {
                        Label("添加步骤", systemImage: "plus")
                    }
                    if allowsSectionDeletion, let deleteSection {
                        Spacer()
                        Button("删除分组", role: .destructive, action: deleteSection)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label(section.title, systemImage: section.systemImage)
                Spacer()
                Text("\(section.items.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func optionalText(_ value: Binding<String?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private static func newItem(section: DailySOPSection) -> DailySOPItem {
        DailySOPItem(
            id: "sop-\(UUID().uuidString)",
            title: "新步骤",
            sectionID: section.id,
            sectionTitle: section.title
        )
    }
}
