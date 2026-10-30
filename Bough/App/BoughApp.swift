import SwiftUI
import SwiftData

@main
struct BoughApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let recentStore: RecentRepositoriesStore

    init() {
        recentStore = BoughApp.makeStore()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
                .frame(minWidth: 1000, minHeight: 640)
                .modelContainer(recentStore.modelContainer)
                .environmentObject(recentStore)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("打开仓库…") {
                    RepoOpenPanel.performMenuOpen()
                }
                .keyboardShortcut("o")
            }
            CommandMenu("仓库") {
                Button("刷新") { WorkspaceCommand.send("refresh") }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("搜索…") { WorkspaceCommand.send("search") }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("历史视图") { WorkspaceCommand.send("mode:history") }
                    .keyboardShortcut("1", modifiers: .command)
                Button("工作区视图") { WorkspaceCommand.send("mode:changes") }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Fetch 全部远程") { WorkspaceCommand.send("fetch") }
                Button("Stash 更改…") { WorkspaceCommand.send("stash") }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Push") { WorkspaceCommand.send("push") }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("检查更新…") {
                    UpdaterController.shared.checkForUpdates()
                }
            }
        }
    }

    private static func makeStore() -> RecentRepositoriesStore {
        do {
            let container = try ModelContainer(for: RepositoryRecord.self)
            return RecentRepositoriesStore(modelContainer: container)
        } catch {
            Log.app.fault("ModelContainer creation failed: \(String(describing: error), privacy: .public)")
            let fallback = try! ModelContainer(
                for: RepositoryRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            return RecentRepositoriesStore(modelContainer: fallback)
        }
    }
}
