import AppKit

@MainActor
enum AppWindowActivator {
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { window in
            window.canBecomeMain && !(window is NSPanel)
        }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
