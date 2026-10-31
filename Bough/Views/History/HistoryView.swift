import SwiftUI

/// Center column (history mode): filter bar + graph/list of commits.
struct HistoryView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject private var history: HistoryModel
    @ObservedObject private var detail: DetailModel
    /// Collapses the graph column into a plain list (spec: 可折叠为列表).
    @State private var showsGraph = true
    /// Reset request awaiting mode choice.
    @State private var resetTarget: Commit?
    @State private var tagTarget: Commit?
    @State private var rebaseTarget: Commit?
    @State private var showsReflog = false
    @State private var treeTarget: Commit?

    init(model: WorkspaceModel) {
        self.model = model
        self._history = ObservedObject(wrappedValue: model.history)
        self._detail = ObservedObject(wrappedValue: model.detail)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if history.visibleRows.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath",
                               title: "没有提交",
                               message: history.isLoading ? "正在加载历史…" : "当前过滤条件下没有提交")
            } else {
                commitList
            }
        }
        .task { await history.reload() }
        .navigationTitle(model.repository.root.lastPathComponent)
        .toolbar { toolbarContent }
        .sheet(item: $resetTarget) { commit in
            resetSheet(commit)
        }
        .sheet(item: $tagTarget) { commit in
            NewTagSheet(model: model, target: commit) { tagTarget = nil }
        }
        .sheet(item: $rebaseTarget) { commit in
            InteractiveRebaseSheet(model: model, base: commit) { rebaseTarget = nil }
        }
        .sheet(isPresented: $showsReflog) {
            ReflogSheet(model: model) { showsReflog = false }
        }
        .sheet(item: $treeTarget) { commit in
            FileTreeSheet(model: model, ref: commit.sha, title: commit.subject) {
                treeTarget = nil
            }
        }
    }

    private func resetSheet(_ commit: Commit) -> some View {
        return ResetSheetView(commit: commit) { mode in
            resetTarget = nil
            Task { await model.reset(to: commit, mode: mode) }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("按消息 / SHA 过滤", text: $history.textQuery)
                .textFieldStyle(.plain)
            authorPicker
            DatePicker("从", selection: Binding(
                get: { history.filter.since ?? Date.distantPast },
                set: { history.filter.since = $0 == Date.distantPast ? nil : $0 }))
                .labelsHidden()
            if pathFilterActive {
                TextField("路径前缀，如 src/", text: $history.filter.path)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        history.filter = history.filter // trigger reload via didSet
                    }
            }
            Button {
                pathFilterActive.toggle()
                if !pathFilterActive { history.filter.path = "" }
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .help("按路径过滤")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - List

    private var commitList: some View {
        let graphWidth: CGFloat = showsGraph
            ? CGFloat((history.visibleRows.map(\.laneCount).max() ?? 1)) * 14 + 4
            : 0
        return List(selection: selectedCommit) {
            ForEach(history.visibleRows) { row in
                HistoryRowView(row: row, showsGraph: showsGraph, graphWidth: graphWidth,
                               decorations: history.decorations(for: row.commit.sha),
                               isHead: history.headSha == row.commit.sha)
                    .tag(row.commit) // List(selection:) requires tags to fire the binding
                    .contextMenu {
                        contextMenu(for: row.commit)
                    }
            }
            if history.canLoadMore {
                loadMoreRow
            }
        }
        .listStyle(.plain)
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if history.isLoadingMore {
                ProgressView().controlSize(.small)
                Text("加载中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("加载更早的提交（已载入 \(history.rows.count)）") {
                    Task { await history.loadMore() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var selectedCommit: Binding<Commit?> {
        Binding(get: {
            if case .commit(let commit) = detail.selection { return commit }
            return nil
        }, set: { newValue in
            if let newValue {
                detail.select(.commit(newValue))
            }
        })
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for commit: Commit) -> some View {
        Button("复制 SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.sha, forType: .string)
        }
        Divider()
        Button("检出此提交（detached HEAD）") {
            Task { await model.checkout(commit) }
        }
        Button("Cherry-pick 到当前分支") {
            Task { await model.cherryPick(commit) }
        }
        Button("Revert 此提交") {
            Task { await model.revert(commit) }
        }
        Divider()
        Button("浏览此提交的文件树…") {
            treeTarget = commit
        }
        Button("在此提交上打标签…") {
            tagTarget = commit
        }
        Button("交互式 Rebase（简化版）…") {
            rebaseTarget = commit
        }
        Divider()
        Button("重置当前分支到此处…") {
            resetTarget = commit
        }
    }

    // MARK: - Path filter / author picker / badges

    @State private var pathFilterActive = false

    private var authorPicker: some View {
        Menu {
            Button("全部作者") { history.filter.author = "" }
            Divider()
            ForEach(history.authors, id: \.self) { name in
                Button(name) { history.filter.author = name }
            }
        } label: {
            Label(history.filter.author.isEmpty ? "作者" : history.filter.author,
                  systemImage: "person")
        }
        .frame(width: 110)
    }

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
            Toggle("图形", isOn: $showsGraph)
                .help("显示 / 隐藏提交图")
            Button {
                showsReflog = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("Reflog：找回被重置/变基丢弃的提交")
            Button {
                Task { await history.reload() }
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
}
