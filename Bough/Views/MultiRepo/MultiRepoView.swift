import SwiftUI
import SwiftData

/// Multi-repository overview window: scan + batch fetch/pull over recents.
struct MultiRepoView: View {
    @EnvironmentObject private var recentStore: RecentRepositoriesStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model = MultiRepoModel()
    @Query(sort: \RepositoryRecord.lastOpenedAt, order: .reverse)
    private var recents: [RepositoryRecord]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.rows.isEmpty {
                EmptyStateView(icon: "square.stack.3d.up",
                               title: "没有可管理的仓库",
                               message: "先在主窗口打开几个仓库，它们会出现在这里")
            } else {
                repoList
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onAppear {
            model.seed(paths: recents.map(\.path))
            if model.rows.allSatisfy({ $0.snapshot == nil }) {
                Task { await model.scan() }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("多仓库总览（\(model.rows.count)）")
                .font(.headline)
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("重新扫描") { Task { await model.scan() } }
                .disabled(model.isBusy)
            Button("全部 Fetch") { Task { await model.fetchAll() } }
                .disabled(model.isBusy)
            Button("全部 Pull…") { model.showsPullConfirm = true }
                .disabled(model.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .confirmationDialog("对全部仓库执行 pull（merge）？",
                            isPresented: $model.showsPullConfirm,
                            titleVisibility: .visible) {
            Button("Pull 全部（\(AppPreferences.defaultPullStrategy.rawValue) 策略）", role: .destructive) {
                Task { await model.pullAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将在每个有效仓库上执行 git pull（\(AppPreferences.defaultPullStrategy.rawValue) 策略）；有冲突的仓库会标记失败并保留冲突现场。")
        }
    }

    private var repoList: some View {
        List {
            ForEach(model.rows) { row in
                rowView(row)
                    .contextMenu {
                        Button("打开此仓库") { openRow(row) }
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: row.path)])
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func rowView(_ row: MultiRepoModel.Row) -> some View {
        HStack(spacing: 10) {
            stateDot(row.state)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.body.weight(.medium))
                    if let branch = row.snapshot?.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let snapshot = row.snapshot, snapshot.isValid {
                        if snapshot.ahead > 0 || snapshot.behind > 0 {
                            Text("↑\(snapshot.ahead) ↓\(snapshot.behind)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if snapshot.dirtyCount > 0 {
                            Text("\(snapshot.dirtyCount) 个更改")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text(row.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            switch row.state {
            case .idle:
                EmptyView()
            case .working:
                ProgressView().controlSize(.small)
            case .done(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(message)
            }
            Button("打开") { openRow(row) }
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func stateDot(_ state: MultiRepoModel.RowState) -> some View {
        Circle()
            .fill(color(for: state))
            .frame(width: 8, height: 8)
    }

    private func color(for state: MultiRepoModel.RowState) -> Color {
        switch state {
        case .idle: return .gray.opacity(0.4)
        case .working: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }

    private func openRow(_ row: MultiRepoModel.Row) {
        model.open(row: row)
        openWindow(id: "main")
    }
}
