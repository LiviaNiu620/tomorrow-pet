import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: TaskStore
    @Binding var selection: SidebarDestination?

    var body: some View {
        List(selection: $selection) {
            Section("计划") {
                sidebarRow(.planner, icon: "sparkles", count: nil)
                sidebarRow(.weekly, icon: "calendar.badge.clock", count: nil)
                sidebarRow(.sop, icon: "checklist.checked", count: nil)
                sidebarRow(.today, icon: "sun.max", count: store.count(for: .today))
                sidebarRow(.tomorrow, icon: "sunrise", count: store.count(for: .tomorrow))
            }

            Section("任务") {
                sidebarRow(.inbox, icon: "tray", count: store.count(for: .inbox))
                sidebarRow(.all, icon: "checklist", count: store.count(for: .all))
                sidebarRow(.immediate, icon: "bolt", count: store.count(for: .immediate))
                sidebarRow(.shortTerm, icon: "calendar", count: store.count(for: .shortTerm))
                sidebarRow(.longTerm, icon: "mountain.2", count: store.count(for: .longTerm))
                sidebarRow(.waiting, icon: "hourglass", count: store.count(for: .waiting))
                sidebarRow(.completed, icon: "checkmark.circle", count: store.count(for: .completed))
                sidebarRow(.trash, icon: "trash", count: store.count(for: .trash))
            }

            Section("领域") {
                ForEach(store.areas) { area in
                    HStack(spacing: 8) {
                        Image(systemName: area.systemImage)
                            .foregroundStyle(Color.areaColor(named: area.colorName))
                            .frame(width: 16)
                        Text(area.name)
                        Spacer()
                        Text("\(store.count(for: .area(area.id)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarDestination.area(area.id))
                    .accessibilityLabel("\(area.name)，\(store.count(for: .area(area.id))) 个任务")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppConstants.name)
    }

    @ViewBuilder
    private func sidebarRow(_ destination: SidebarDestination, icon: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(destination.title)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(destination)
    }
}
