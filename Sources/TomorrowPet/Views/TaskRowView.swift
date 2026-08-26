import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let area: TaskArea?
    let allowsCompletion: Bool
    let toggleCompleted: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if allowsCompletion {
                Button(action: toggleCompleted) {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.status == .completed ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.status == .completed ? "标记为未完成" : "标记完成")
            } else {
                Image(systemName: "trash.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let area {
                        Label(area.name, systemImage: area.systemImage)
                            .foregroundStyle(Color.areaColor(named: area.colorName))
                    } else {
                        Label("未分类", systemImage: "tray")
                    }

                    Text(task.effectiveHorizon().title)

                    if let date = task.plannedDate {
                        Label(date.shortDayText, systemImage: "calendar.badge.clock")
                    } else if let date = task.dueDate {
                        Label("截止 \(date.shortDayText)", systemImage: "flag")
                    }

                    if let minutes = task.estimatedMinutes {
                        Label("\(minutes) 分钟", systemImage: "clock")
                    }

                    if task.recurrence != nil {
                        Label("重复", systemImage: "repeat")
                    }

                    if let deletedAt = task.deletedAt {
                        Label("删除于 \(deletedAt.shortDayText)", systemImage: "trash")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 10)

            if task.priority != .none {
                Text(task.priority.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(priorityColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(priorityColor)
                    .accessibilityLabel("优先级\(task.priority.title)")
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        case .none: .secondary
        }
    }
}
