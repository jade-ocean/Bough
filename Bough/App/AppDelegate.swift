import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        Log.app.info("Bough launching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Bough launched")
    }

    /// Quit when the last window closes (matches utility-app convention).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.ui.info("dock reopen, visible windows: \(flag)")
        return true
    }
}
