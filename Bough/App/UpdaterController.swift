import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater controller.
/// Feed URL / EdDSA key live in Info.plist (SUFeedURL / SUPublicEDKey).
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController?

    private init() {
        #if DEBUG
        // XCUITest runs must not spawn the updater (its sheet would mask the
        // whole window and network probing slows the run).
        if ProcessInfo.processInfo.environment["UITEST_REPO_PATH"] != nil {
            controller = nil
            return
        }
        #endif
        // startingUpdater can fail when Sparkle misconfigured; degrade gracefully.
        var updater: SPUStandardUpdaterController?
        do {
            updater = SPUStandardUpdaterController(startingUpdater: true,
                                                   updaterDelegate: nil,
                                                   userDriverDelegate: nil)
        } catch {
            Log.app.error("Sparkle init failed: \(String(describing: error), privacy: .public)")
        }
        self.controller = updater
    }

    /// Called from the menu; no-op when the updater failed to start.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
