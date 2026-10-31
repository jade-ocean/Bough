import SwiftUI

/// Center column: staged / unstaged / untracked file lists + commit composer.
struct ChangesView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                BannerView(banner: banner) { model.banner = nil }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            HStack(spacing: 0) {
                stagedPanel
                Divider()
                worktreePanel
            }
            CommitComposer(model: model)
        }
        .sheet(isPresented: discardBinding) {
            DiscardConfirmation(entries: model.pendingDiscard) { confirmed in
                let entries = model.pendingDiscard
                model.pendingDiscard = []
                if confirmed {
                    Task { await model.performDiscard(entries) }
                }
            }
        }
        .task { await model.refresh() }
        .navigationTitle(model.repository.root.lastPathComponent)
        .toolbar { toolbarContent }
    }

    private var discardBinding: Binding<Bool> {
        Binding(get: { !model.pendingDiscard.isEmpty },
                set: { if !$0 { model.pendingDiscard = [] } })
    }

    // MARK: - Panels

    private var stagedPanel: some View {
        filePanel(
            title: "已暂存",
            entries: model.status.staged,
            emptyText: "没有已暂存的文件",
            bulkActionTitle: "全部取消暂存",
            bulkAction: { Task { await model.unstageAll() } }
        ) { entry in
            Button("取消暂存") { Task { await model.unstage([entry]) } }
            Button("放弃更改…") { model.pendingDiscard = [entry] }
        }
    }

    private var worktreePanel: some View {
        VStack(spacing: 0) {
            filePanel(
                title: "未暂存",
                entries: model.status.unstaged,
                emptyText: "没有未暂存的更改",
                bulkActionTitle: "全部暂存",
                bulkAction: { Task { await model.stageAll() } }
            ) { entry in
                Button("暂存") { Task { await model.stage([entry]) } }
                Button("放弃更改…") { model.pendingDiscard = [entry] }
            }
            Divider()
            filePanel(
                title: "未跟踪",
                entries: model.status.untracked,
                emptyText: "没有未跟踪的文件",
                bulkActionTitle: "全部暂存",
                bulkAction: { Task { await model.stageAll() } }
            ) { entry in
                Button("暂存") { Task { await model.stage([entry]) } }
                Button("删除文件…", role: .destructive) { model.pendingDiscard = [entry] }
            }
        }
    }

    private func filePanel<Menu: View>(title: String,
                                       entries: [StatusEntry],
                                       emptyText: String,
                                       bulkActionTitle: String,
                                       bulkAction: @escaping () -> Void,
                                       @ViewBuilder contextMenu: @escaping (StatusEntry) -> Menu) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(title)（\(entries.count)）")
                    .font(.headline)
                Spacer()
                Button(bulkActionTitle) { bulkAction() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .disabled(entries.isEmpty || model.isBusy)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if entries.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    StatusRow(entry: entry, side: side(for: title))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.detail.select(.worktreeFile(
                                path: entry.path,
                                staged: title == "已暂存",
                                isUntracked: entry.isUntracked))
                        }
                        .contextMenu { contextMenu(entry) }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func side(for title: String) -> ChangeSide {
        title == "已暂存" ? .staged : .worktree
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("视图", selection: $model.centerMode) {
                Label("历史", systemImage: "clock.arrow.circlepath")
                    .tag(WorkspaceModel.CenterMode.history)
                    .accessibilityIdentifier("mode.history")
                Label("工作区", systemImage: "folder")
                    .tag(WorkspaceModel.CenterMode.changes)
                    .accessibilityIdentifier("mode.changes")
            }
            .accessibilityIdentifier("center.mode")
            .pickerStyle(.segmented)
            .frame(width: 150)
            branchChip
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("刷新（Cmd+R）")
            Menu {
                Button("Fetch 全部远程") { Task { await model.fetchAll() } }
                Divider()
                Button("Pull（默认：\(AppPreferences.defaultPullStrategy.rawValue)）") {
                    Task { await model.pull(strategy: AppPreferences.defaultPullStrategy) }
                }
                Button("Pull（merge 策略）") { Task { await model.pull(strategy: .merge) } }
                Button("Pull（rebase 策略）") { Task { await model.pull(strategy: .rebase) } }
                Divider()
                Button("Push") { Task { await model.push() } }
                Button("Push（force-with-lease）", role: .destructive) {
                    Task { await model.push(forceWithLease: true) }
                }
            } label: {
                Image(systemName: "arrow.triangle.pull")
            }
            .help("fetch / pull / push")
        }
    }

    private var branchChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
            Text(branchLabel)
            if model.status.ahead > 0 || model.status.behind > 0 {
                Text("↑\(model.status.ahead) ↓\(model.status.behind)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .help("当前分支")
    }

    private var branchLabel: String {
        if let branch = model.status.branch { return branch }
        return "—"
    }
}
