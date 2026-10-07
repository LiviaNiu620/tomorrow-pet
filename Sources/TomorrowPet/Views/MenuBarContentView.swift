import AppKit
import SwiftUI

/// 菜单栏面板：下一项、专注倒计时和常用入口。
struct MenuBarContentView: View {
    @ObservedObject private var focus = FocusTimer.shared
    @ObservedObject private var sopStore = DailySOPStore.shared
    @ObservedObject private var store = TaskStore.shared

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let next = sopStore.items(for: now).compactMap { item -> (DailySOPItem, Int)? in
            guard let start = DailySOPTemplate.startMinute(of: item.time), start > minute else { return nil }
            return (item, start)
        }.min { $0.1 < $1.1 }
        let top = store.focusTasks(on: now).first { $0.status.isActive }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DangoMascot(mood: focus.isRunning ? .focused : .happy, outline: Dango.sidebarText, size: 22)
                Text("团子").font(Dango.font(14, .heavy)).foregroundStyle(.white)
                Spacer()
                Text(focus.isRunning || focus.hasStarted ? focus.clockText : (next.map { "\(DayPlanner.clock($0.1)) \($0.0.title)" } ?? ""))
                    .font(Dango.mono(12)).foregroundStyle(Dango.pinkLight).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Dango.ink)

            VStack(spacing: 2) {
                row("+", "随手记", fill: Dango.pink) { open(.today); AppRouter.shared.captureFocusRequest = UUID() }
                row("今", "打开今天", fill: Dango.apricot) { open(.today, mode: .today) }
                row("明", "安排明天", fill: Dango.lavender) { open(.today, mode: .tomorrow) }
                if focus.isRunning || focus.hasStarted {
                    row("专", focus.isRunning ? "暂停专注（\(focus.clockText)）" : "继续专注（\(focus.clockText)）", fill: Dango.sky) { focus.toggle() }
                } else if let top {
                    row("专", "开始专注 · \(top.title)", fill: Dango.sky) {
                        focus.choose(taskID: top.id, title: top.title)
                        focus.start()
                    }
                } else {
                    row("专", "打开专注", fill: Dango.sky) { open(.focus) }
                }
                row("周", "本周计划", fill: Dango.sky) { open(.week) }
                row("盘", "今日复盘", fill: Color(hex: 0xE2EFBE)) { open(.review) }
                Rectangle().fill(Dango.dash).frame(height: 1.5).padding(.vertical, 4)
                HStack {
                    SettingsLink { Text("设置…").font(Dango.font(13, .semibold)) }
                        .buttonStyle(PressableStyle())
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }
                        .buttonStyle(PressableStyle())
                        .font(Dango.font(13, .semibold))
                }
                .foregroundStyle(Dango.muted)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .padding(8)
            .background(Dango.paper)
        }
        .frame(width: 320)
        .environment(\.colorScheme, .light)
    }

    private func row(_ icon: String, _ title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(Dango.font(12, .heavy))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(fill))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Dango.ink, lineWidth: 1.5))
                Text(title).font(Dango.font(13, .bold)).lineLimit(1)
                Spacer()
            }
            .foregroundStyle(Dango.ink)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func open(_ section: AppSection, mode: DayMode? = nil) {
        AppWindowActivator.showMainWindow()
        AppRouter.shared.go(section, mode: mode)
    }
}

/// 菜单栏图标：专注时直接显示倒计时。
struct MenuBarLabel: View {
    @ObservedObject private var focus = FocusTimer.shared

    var body: some View {
        if focus.isRunning || focus.hasStarted {
            Text("◉ \(focus.clockText)").monospacedDigit()
        } else {
            Image(systemName: "circle.grid.2x1.fill")
        }
    }
}
