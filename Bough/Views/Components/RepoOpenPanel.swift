import AppKit

/// NSOpenPanel wrapper + menu routing.
@MainActor
enum RepoOpenPanel {

    /// Directory picker for choosing a repository (root or any subfolder).
    static func promptForDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "选择一个 Git 仓库（根目录或其中任意子目录）"
        panel.prompt = "打开"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// File > Open Repository... handler.
    /// Captures the key window BEFORE runModal (the panel becomes key during the modal loop),
    /// then posts a notification routed to that window's model.
    static func performMenuOpen() {
        let keyWindow = NSApp.keyWindow
        guard let url = promptForDirectory() else { return }
        NotificationCenter.default.post(
            name: .boughOpenRequested,
            object: keyWindow,
            userInfo: [BoughNotification.pathKey: url.path]
        )
    }
}
