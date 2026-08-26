import AppKit
import SwiftUI

struct MenuBarContentView: View {
    var body: some View {
        Button("打开任务中心") {
            AppWindowActivator.showMainWindow()
        }
        Button("安排明天") {
            AppWindowActivator.showMainWindow()
            NotificationCenter.default.post(name: .openTomorrowPlanner, object: nil)
        }
        Button("本周计划") {
            AppWindowActivator.showMainWindow()
            NotificationCenter.default.post(name: .openWeeklyPlanner, object: nil)
        }
        Button("快速添加任务") {
            AppWindowActivator.showMainWindow()
            NotificationCenter.default.post(name: .showQuickAdd, object: nil)
        }
        Divider()
        SettingsLink { Text("设置…") }
        Divider()
        Button("退出明日团子") {
            NSApp.terminate(nil)
        }
    }
}
