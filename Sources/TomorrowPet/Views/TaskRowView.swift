import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let area: TaskArea?
    let allowsCompletion: Bool
    let toggleCompleted: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if allowsCompletion {
                Button(action: toggleCompleted) {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(task.status == .completed ? AppTheme.success : .secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(task.status == .completed ? "标记为未完成" : "完成任务")
                .accessibilityLabel("\(task.status == .completed ? "标记为未完成" : "完成任务")：\(task.title)")
            } else {
                Image(systemName: "trash.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(task.title)
                    .padding(.top, 5)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        categoryLabel
                        scheduleLabel
                        durationLabel
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        categoryLabel
                        HStack(spacing: 10) {
                            scheduleLabel
                            durationLabel
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        categoryLabel
                        scheduleLabel
                        durationLabel
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let deletedAt = task.deletedAt {
                    Label("删除于 \(deletedAt.shortDayText)", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.priority != .none {
                Text("\(task.priority.title)优先级")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.priority(task.priority))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.priority(task.priority).opacity(0.08), in: Capsule())
                    .fixedSize()
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var categoryLabel: some View {
        HStack(spacing: 7) {
            if let area {
                Label(area.name, systemImage: area.systemImage)
            } else {
                Label("未分类", systemImage: "tray")
            }
            if task.recurrence != nil {
                Image(systemName: "repeat")
                    .accessibilityLabel("重复任务")
                    .help("重复任务")
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var scheduleLabel: some View {
        if let dueDate = task.dueDate, isOverdue {
            Label("逾期 · \(dueDate.shortDayText)", systemImage: "exclamationmark.circle")
                .foregroundStyle(AppTheme.accent)
                .fixedSize()
        } else if let date = task.plannedDate {
            Label(date.shortDayText, systemImage: "calendar")
                .fixedSize()
        } else if let date = task.dueDate {
            Label("截止 \(date.shortDayText)", systemImage: "flag")
                .fixedSize()
        } else {
            Text(task.effectiveHorizon().title).fixedSize()
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        if let minutes = task.estimatedMinutes {
            Label("\(minutes) 分钟", systemImage: "clock")
                .monospacedDigit()
                .fixedSize()
        }
    }

    private var isOverdue: Bool {
        guard task.status.isActive, let dueDate = task.dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }
}
