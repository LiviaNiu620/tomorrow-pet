import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: TaskStore
    @Binding var selection: SidebarDestination?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PetFaceView(mood: .happy)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppConstants.name)
                        .font(.headline)
                    Text("按自己的节奏，慢慢向前")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            Divider().opacity(0.55)

            List(selection: $selection) {
                Section("每日节奏") {
                    sidebarRow(.today, icon: "sun.max", count: store.count(for: .today), color: .orange)
                    sidebarRow(.tomorrow, icon: "sunrise", count: store.count(for: .tomorrow), color: AppTheme.accent)
                    sidebarRow(.planner, icon: "sparkles", count: nil, color: AppTheme.accent)
                    sidebarRow(.weekly, icon: "calendar.badge.clock", count: nil, color: AppTheme.sky)
                    sidebarRow(.sop, icon: "checklist.checked", count: nil, color: .purple)
                }

                Section("任务") {
                    sidebarRow(.inbox, icon: "tray", count: store.count(for: .inbox))
                    sidebarRow(.all, icon: "checklist", count: store.count(for: .all))
                    sidebarRow(.immediate, icon: "bolt", count: store.count(for: .immediate), color: .orange)
                    sidebarRow(.shortTerm, icon: "calendar", count: store.count(for: .shortTerm), color: AppTheme.sky)
                    sidebarRow(.longTerm, icon: "mountain.2", count: store.count(for: .longTerm), color: .purple)
                    sidebarRow(.waiting, icon: "hourglass", count: store.count(for: .waiting))
                }

                Section("领域") {
                    ForEach(store.areas) { area in
                        HStack(spacing: 9) {
                            Image(systemName: area.systemImage)
                                .foregroundStyle(Color.areaColor(named: area.colorName))
                                .frame(width: 17)
                            Text(area.name)
                            Spacer()
                            let count = store.count(for: .area(area.id))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(SidebarDestination.area(area.id))
                        .accessibilityLabel("\(area.name)，\(store.count(for: .area(area.id))) 个任务")
                    }
                }
                Section("归档") {
                    sidebarRow(.completed, icon: "checkmark.circle", count: store.count(for: .completed), color: AppTheme.success)
                    sidebarRow(.trash, icon: "trash", count: store.count(for: .trash))
                }
            }
            .listStyle(.sidebar)

            Divider().opacity(0.5)
            HStack {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .help("打开设置（⌘,）")
                Spacer()
                Text("⌘ N 新任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private func sidebarRow(
        _ destination: SidebarDestination,
        icon: String,
        count: Int?,
        color: Color = .secondary
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 17)
            Text(destination.title)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .tag(destination)
        .accessibilityLabel(count.map { "\(destination.title)，\($0) 个任务" } ?? destination.title)
    }
}
