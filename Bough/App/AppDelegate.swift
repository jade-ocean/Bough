import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        Log.app.info("Bough launching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the Sparkle updater at launch. Without touching the lazy
        // singleton here it only initializes from the "检查更新…" menu item,
        // so SUEnableAutomaticChecks never takes effect (BUG-004). The
        // controller itself no-ops under XCUITest (UITEST_REPO_PATH guard).
        _ = UpdaterController.shared
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
