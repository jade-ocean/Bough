import SwiftUI
import SwiftData

/// Empty state (no repo open): hero + recents card.
struct WelcomeView: View {
    @ObservedObject var viewModel: MainWindowModel

    @EnvironmentObject private var recentStore: RecentRepositoriesStore
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \RepositoryRecord.lastOpenedAt, order: .reverse)
    private var recents: [RepositoryRecord]

    init(viewModel: MainWindowModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = viewModel.banner {
                bannerView(banner)
            }
            HStack(alignment: .top, spacing: 40) {
                heroPanel
                recentsPanel
            }
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Bough")
    }

    // MARK: - Hero

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text("Bough")
                .font(.largeTitle.weight(.bold))
            Text("Every branch starts somewhere.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("轻量、原生、快速的 macOS Git 可视化管理工具")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Button("打开仓库…") {
                    viewModel.promptOpenRepository()
                }
                .keyboardShortcut("o")
                Button("克隆远程仓库…") {
                }
                .disabled(true)
                .help("Git 引擎接入后提供（阶段 2）")
            }
        }
        .frame(width: 300)
    }

    private var recentsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近仓库")
                .font(.headline)
            if recents.isEmpty {
                Text("最近打开的仓库会出现在这里")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                List(recents) { record in
                    recentRow(record)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 380)
    }

    private func recentRow(_ record: RepositoryRecord) -> some View {
        Button {
            Task { await viewModel.openRepository(at: URL(fileURLWithPath: record.path)) }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(record.name)
                        .fontWeight(.medium)
                    Text(record.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Text(record.lastOpenedAt, format: .relative(presentation: .named))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("在新窗口打开") {
                PendingOpenRouter.shared.pendingPath = record.path
                openWindow(id: "main")
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)])
            }
            Button("移除") { recentStore.remove(record) }
        }
    }

    private func bannerView(_ banner: MainWindowModel.Banner) -> some View {
        BannerView(banner: banner) {
            viewModel.banner = nil
        }
        .padding(.horizontal, 48)
        .padding(.top, 20)
    }
}
