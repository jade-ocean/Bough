import SwiftUI

/// Three-pane skeleton per spec:
/// left = repo switcher + branch/tag/stash/remote tree (placeholders),
/// center = history (Phase 3), right = diff detail (Phase 3).
struct MainWindowView: View {
    @StateObject private var viewModel = MainWindowModel()
    @EnvironmentObject private var recentStore: RecentRepositoriesStore
    @Environment(\.openWindow) private var openWindow
    @State private var showConflictSheet = false

    var body: some View {
        Group {
            if let workspace = viewModel.workspace {
                workspaceView(workspace)
            } else {
                WelcomeView(viewModel: viewModel)
            }
        }
        .background(
            WindowAccessor { viewModel.attach(window: $0) }
        )
        .onAppear { viewModel.attach(store: recentStore) }
        .task { await consumePendingOpen() }
        .onOpenURL { viewModel.handleURLScheme($0) }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.handleDroppedURLs(urls)
            return true
        } isTargeted: { viewModel.isDropTargeted = $0 }
        .overlay { dropOverlay }
        .onReceive(NotificationCenter.default.publisher(for: .boughOpenMultiRepo)) { _ in
            openWindow(id: "multi-repo")
        }
        .sheet(item: $viewModel.pendingSheet) { sheet in
            if let ws = viewModel.workspace {
                switch sheet {
                case .search:
                    SearchSheet(model: ws.workspaceModel) { viewModel.pendingSheet = nil }
                case .stash:
                    NewStashSheet(model: ws.workspaceModel) { viewModel.pendingSheet = nil }
                case .clone:
                    CloneRemoteSheet(viewModel: viewModel) { viewModel.pendingSheet = nil }
                }
            } else {
                // Welcome state: only clone applies.
                CloneRemoteSheet(viewModel: viewModel) { viewModel.pendingSheet = nil }
            }
        }
        .environmentObject(viewModel)
    }

    private func workspaceView(_ ws: MainWindowModel.Workspace) -> some View {
        VStack(spacing: 0) {
            if !ws.workspaceModel.status.unmerged.isEmpty {
                ConflictBannerView(model: ws.workspaceModel) {
                    showConflictSheet = true
                }
            }
            NavigationSplitView {
                SidebarView(workspace: ws)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            } content: {
                centerColumn(ws)
            } detail: {
                DetailPaneView(model: ws.workspaceModel)
            }
            StatusBarView(workspace: ws, windowModel: viewModel)
        }
        .sheet(isPresented: $showConflictSheet) {
            ConflictSheet(conflict: ws.workspaceModel.conflict) {
                showConflictSheet = false
                Task { await ws.workspaceModel.refresh() }
            }
        }
    }

    /// History graph or working copy, switched by the toolbar segmented control.
    @ViewBuilder
    private func centerColumn(_ ws: MainWindowModel.Workspace) -> some View {
        let model = ws.workspaceModel
        switch model.centerMode {
        case .history:
            HistoryView(model: model)
        case .changes:
            ChangesView(model: model)
        }
    }

    private func consumePendingOpen() async {
        if let path = PendingOpenRouter.shared.take() {
            await viewModel.openRepository(at: .init(fileURLWithPath: path))
        }
    }

    private var dropOverlay: some View {
        Group {
            if viewModel.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [6]))
                    .foregroundStyle(.tint)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(8)
                    .allowsHitTesting(false)
        }
    }
}
}
