import AppKit

@MainActor
enum AppWindowActivator {
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { window in
            window.canBecomeMain && !(window is NSPanel)
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openNewMainWindow()
        }
    }

    /// 主窗口被关掉后，通过 SwiftUI 自动生成的 “New … Window” 菜单项重新打开。
    private static func openNewMainWindow() {
        guard let menu = NSApp.mainMenu else { return }
        func find(in menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.title.hasPrefix("New") && item.title.contains("Window") { return item }
                if item.title.hasPrefix("新建") && item.title.contains("窗口") { return item }
                if let submenu = item.submenu, let found = find(in: submenu) { return found }
            }
            return nil
        }
        if let item = find(in: menu), let parent = item.menu {
            parent.performActionForItem(at: parent.index(of: item))
        }
    }
}
