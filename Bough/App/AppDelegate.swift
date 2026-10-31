import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once by the root view (captures OpenWindowAction, which stays
    /// valid after its window closes) so Dock reopen can restore a window.
    static var reopenHandler: (() -> Void)?

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Restore is handled in applicationDidBecomeActive ONLY - firing both
        // produced two windows on Dock click (0.4.2 regression).
        return true
    }

    /// SwiftUI swallows applicationShouldHandleReopen - restore on activation
    /// ourselves when no main window is visible.
    func applicationDidBecomeActive(_ notification: Notification) {
        let hasMainWindow = NSApp.windows.contains {
            $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true
        }
        if !hasMainWindow {
            Log.ui.info("activation without main window - reopening")
            // Defer out of the activation call stack: a synchronous
            // openWindow here gets swallowed until the NEXT activation.
            DispatchQueue.main.async { Self.reopenHandler?() }
        }
    }
}
