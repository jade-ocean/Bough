import AppKit
import Combine
import Foundation

/// Per-window state machine: welcome <-> open workspace, banner, drop target.
@MainActor
final class MainWindowModel: ObservableObject {
    struct Workspace {
        let root: URL
        let gitDirectory: URL
        let name: String
        /// Per-repo working-copy model (status + staging + commit).
        let workspaceModel: WorkspaceModel
    }

    enum Banner: Equatable {
        case error(String)
        case info(String)

        var message: String {
            switch self {
            case .error(let m), .info(let m):
                return m
            }
        }
    }

    @Published private(set) var workspace: Workspace?
    @Published var banner: Banner?
    @Published private(set) var isProcessing = false
    @Published private(set) var activity: String = "就绪"
    @Published var isDropTargeted = false

    /// Sheet requested via the app menu (search / stash); consumed by the view.
    enum PendingSheet: String, Identifiable {
        case search
        case stash
        case clone

        var id: String { rawValue }
    }
    @Published var pendingSheet: PendingSheet?

    let accessProvider: RepositoryAccessProvider

    private(set) weak var window: NSWindow?
    private var store: RecentRepositoriesStore?
    private var cancellables = Set<AnyCancellable>()
    private var lastAutoRefresh = Date.distantPast

    init(accessProvider: RepositoryAccessProvider = DirectPathAccessProvider()) {
        self.accessProvider = accessProvider
        NotificationCenter.default.publisher(for: .boughOpenRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleOpenRequest(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .boughWorkspaceCommand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleWorkspaceCommand(note) }
            .store(in: &cancellables)
    }
}

// MARK: - Open flow

extension MainWindowModel {

    /// NSOpenPanel flow; routes the chosen URL into the async open pipeline.
    func promptOpenRepository() {
        guard let url = RepoOpenPanel.promptForDirectory() else { return }
        Task { await openRepository(at: url) }
    }

    /// Core open pipeline: validate via the access provider, switch state, record recents.
    func openRepository(at url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        banner = nil
        activity = "正在校验仓库…"
        defer { isProcessing = false }

        let rawPath = url.path
        do {
            let root = try accessProvider.resolveWorkTreeRoot(at: rawPath)
            let gitDir = try accessProvider.resolveGitDirectory(forWorkTreeRoot: root)
            let gitRepo = try GitRepository(root: root)
            let wsModel = WorkspaceModel(repository: gitRepo, accessProvider: accessProvider)
            let ws = Workspace(root: root, gitDirectory: gitDir,
                               name: root.lastPathComponent, workspaceModel: wsModel)
            workspace = ws
            activity = "就绪"
            Log.repository.info("opened repo: \(root.path, privacy: .public)")
            store?.recordOpen(root: root)
        } catch {
            Log.repository.error("open failed for \(rawPath, privacy: .public): \(String(describing: error), privacy: .public)")
            banner = .error(error.localizedDescription)
            activity = "就绪"
        }
    }

    func closeRepository() {
        workspace = nil
        activity = "就绪"
    }

    func attach(store: RecentRepositoriesStore) {
        self.store = store
    }
}

// MARK: - Clone

extension MainWindowModel {

    /// Clone a remote repo, then open it (and record recents via the normal open path).
    func cloneRepository(url: String, folderName: String, into parent: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        activity = "正在克隆远程仓库…"
        defer { isProcessing = false }
        do {
            let dest = try await CloneService.clone(url: url,
                                                    folderName: folderName,
                                                    into: parent)
            Log.repository.info("cloned into: \(dest.path, privacy: .public)")
            activity = "就绪"
            await openRepository(at: dest)
        } catch {
            Log.repository.error("clone failed: \(String(describing: error), privacy: .public)")
            banner = .error(error.localizedDescription)
            activity = "就绪"
        }
    }
}

// MARK: - URL scheme / drag & drop / window routing

extension MainWindowModel {

    /// bough://open?path=... entry (delivered via onOpenURL).
    func handleURLScheme(_ url: URL) {
        do {
            let request = try BoughURLScheme.parse(url)
            Task { await openRepository(at: URL(fileURLWithPath: request.path)) }
        } catch {
            Log.ui.error("url scheme parse failed: \(String(describing: error), privacy: .public)")
            banner = .error(error.localizedDescription)
        }
    }

    /// Finder drop entry; first URL wins.
    func handleDroppedURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }
        Task { await openRepository(at: url) }
    }

    /// Notification routing: only the window that was key when the panel was
    /// prompted handles the request (panel itself is key during runModal).
    private func handleOpenRequest(_ note: Notification) {
        guard let myWindow = window, myWindow === note.object as? NSWindow else { return }
        guard let path = note.userInfo?[BoughNotification.pathKey] as? String, !path.isEmpty else { return }
        Task { await openRepository(at: URL(fileURLWithPath: path))
        }
    }

    func attach(window: NSWindow?) {
        guard window !== self.window else { return }
        self.window = window
        if let window {
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] note in
                    guard (note.object as? NSWindow) === window else { return }
                    self?.autoRefreshThrottled()
                }
                .store(in: &cancellables)
        }
    }

    /// Refresh on window focus, at most once every 5 seconds.
    private func autoRefreshThrottled() {
        guard Date().timeIntervalSince(lastAutoRefresh) > 5 else { return }
        lastAutoRefresh = Date()
        Task { await workspaceModel?.refreshAll() }
    }

    /// Menu commands (keyboard shortcuts) route to the window that was key.
    private func handleWorkspaceCommand(_ note: Notification) {
        guard let myWindow = window, myWindow === note.object as? NSWindow else { return }
        guard let command = note.userInfo?[BoughNotification.commandKey] as? String else { return }
        switch command {
        case "search":
            pendingSheet = .search
        case "clone":
            pendingSheet = .clone
        case "stash":
            pendingSheet = .stash
        case "mode:history":
            workspaceModel?.centerMode = .history
        case "mode:changes":
            workspaceModel?.centerMode = .changes
        case "fetch":
            Task { await workspaceModel?.fetchAll() }
        case "push":
            Task { await workspaceModel?.push() }
        case "refresh":
            Task { await workspaceModel?.refreshAll() }
        default:
            break
        }
    }

    private var workspaceModel: WorkspaceModel? {
        workspace?.workspaceModel
    }
}

enum BoughNotification {
    static let pathKey = "path"
    static let commandKey = "command"
}

extension Notification.Name {
    static let boughOpenRequested = Notification.Name("com.wangyuyang.bough.openRequested")
    static let boughWorkspaceCommand = Notification.Name("com.wangyuyang.bough.workspaceCommand")
    static let boughOpenMultiRepo = Notification.Name("com.wangyuyang.bough.openMultiRepo")
}

/// Post workspace-level menu commands to the key window's model.
enum WorkspaceCommand {
    static func send(_ command: String) {
        NotificationCenter.default.post(
            name: .boughWorkspaceCommand,
            object: NSApp.keyWindow,
            userInfo: [BoughNotification.commandKey: command])
    }
}
