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
        Window("多仓库总览", id: "multi-repo") {
            MultiRepoView()
                .modelContainer(recentStore.modelContainer)
                .environmentObject(recentStore)
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView()
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
                Button("克隆远程仓库…") { WorkspaceCommand.send("clone") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("多仓库总览") {
                    NotificationCenter.default.post(name: .boughOpenMultiRepo, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
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
            #if DEBUG
            // XCUITest runs must never pollute the real recents store -
            // tests share this app binary, so give them an in-memory one.
            if ProcessInfo.processInfo.environment["UITEST_REPO_PATH"] != nil {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: RepositoryRecord.self,
                                                   configurations: config)
                return RecentRepositoriesStore(modelContainer: container)
            }
            #endif
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
