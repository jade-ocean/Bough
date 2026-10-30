import SwiftUI
import SwiftData

/// Left column: repo, recents, branch tree, remote branches, remotes.
struct SidebarView: View {
    let workspace: MainWindowModel.Workspace

    @EnvironmentObject private var viewModel: MainWindowModel
    @EnvironmentObject private var recentStore: RecentRepositoriesStore
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var model: WorkspaceModel
    @ObservedObject private var branches: BranchModel
    @ObservedObject private var stash: StashModel
    @ObservedObject private var tags: TagModel
    @Query(sort: \RepositoryRecord.lastOpenedAt, order: .reverse)
    private var recents: [RepositoryRecord]

    /// Sheets presented from the sidebar.
    enum SidebarSheet: Identifiable {
        case newBranch(startPoint: String?)
        case renameBranch(Branch)
        case remoteEditor(RemoteInfo?)
        case newStash
        case newTag(target: Commit?)

        var id: String {
            switch self {
            case .newBranch(let point): return "new:\(point ?? "HEAD")"
            case .renameBranch(let branch): return "rename:\(branch.id)"
            case .remoteEditor(let remote): return "remote:\(remote?.name ?? "new")"
            case .newStash: return "newStash"
            case .newTag(let target): return "newTag:\(target?.sha ?? "HEAD")"
            }
        }
    }
    @State private var sheet: SidebarSheet?
    /// Branch pending destructive-delete confirmation.
    @State private var deleteTarget: Branch?

    init(workspace: MainWindowModel.Workspace) {
        self.workspace = workspace
        self._model = ObservedObject(wrappedValue: workspace.workspaceModel)
        self._branches = ObservedObject(wrappedValue: workspace.workspaceModel.branches)
        self._stash = ObservedObject(wrappedValue: workspace.workspaceModel.stash)
        self._tags = ObservedObject(wrappedValue: workspace.workspaceModel.tags)
    }

    var body: some View {
        List {
            repoSection
            recentsSection
            branchesSection
            remoteBranchesSection
            remotesSection
            stashSection
            tagsSection
        }
        .listStyle(.sidebar)
        .navigationTitle(workspace.name)
        .sheet(item: $sheet) { target in
            sheetView(target)
        }
        .confirmationDialog(
            "检出「\(model.pendingCheckout?.name ?? "")」前如何处理未提交更改？",
            isPresented: Binding(
                get: { model.pendingCheckout != nil },
                set: { if !$0 { model.pendingCheckout = nil } }),
            titleVisibility: .visible) {
            Button("先自动 Stash，检出后恢复（推荐）") {
                if let target = model.pendingCheckout {
                    Task { await model.checkoutWithStash(target) }
                }
            }
            Button("直接检出（不处理更改）") {
                if let target = model.pendingCheckout {
                    Task { await model.checkout(target) }
                }
            }
            Button("取消", role: .cancel) { model.pendingCheckout = nil }
        } message: {
            Text("工作区有未提交更改；目标分支会覆盖其中部分文件。")
        }
        .confirmationDialog(
            "删除分支「\(deleteTarget?.name ?? "")」？",
            isPresented: Binding(get: { deleteTarget != nil },
                                 set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible) {
            Button("删除（安全，未合并会失败）", role: .destructive) {
                if let target = deleteTarget {
                    Task { await model.delete(target, force: false) }
                }
                deleteTarget = nil
            }
            Button("强制删除（丢弃未合并提交）", role: .destructive) {
                if let target = deleteTarget {
                    Task { await model.delete(target, force: true) }
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("未合并的提交无法用安全模式删除。")
        }
    }

    // MARK: - Sections

    private var repoSection: some View {
        Section("仓库") {
            HStack {
                Label(workspace.name, systemImage: "folder.fill")
                Spacer()
            }
            .contextMenu {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([workspace.root])
                }
            }
            rowButton("打开其他仓库…", icon: "plus.rectangle.on.folder") {
                viewModel.promptOpenRepository()
            }
            rowButton("新窗口打开", icon: "square.on.square") {
                PendingOpenRouter.shared.pendingPath = workspace.root.path
                openWindow(id: "main")
            }
        }
    }

    private var recentsSection: some View {
        Section("最近") {
            ForEach(recents.prefix(8)) { record in
                rowButton(record.name, icon: "clock") {
                    Task { await viewModel.openRepository(at: URL(fileURLWithPath: record.path)) }
                }
                .contextMenu {
                    Button("移除") { recentStore.remove(record) }
                }
            }
        }
    }

    private var branchesSection: some View {
        Section {
            ForEach(branches.local) { branch in
                branchRow(branch)
                    .contextMenu { branchMenu(branch) }
            }
        } header: {
            HStack {
                Text("分支")
                Spacer()
                Button {
                    sheet = .newBranch(startPoint: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建分支")
            }
        }
    }

    @ViewBuilder
    private func branchRow(_ branch: Branch) -> some View {
        HStack(spacing: 6) {
            if branch.isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
            Label(branch.name, systemImage: "arrow.triangle.branch")
                .lineLimit(1)
            Spacer()
            if branch.ahead > 0 || branch.behind > 0 {
                Text("\(branch.ahead > 0 ? "↑\(branch.ahead)" : "")\(branch.behind > 0 ? " ↓\(branch.behind)" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(branch.isCurrent ? .body.weight(.medium) : .body)
    }

    @ViewBuilder
    private func branchMenu(_ branch: Branch) -> some View {
        if !branch.isCurrent {
            Button("检出") {
                Task { await model.requestCheckout(branch) }
            }
        }
        Button("合并到当前分支") {
            Task { await model.merge(branch) }
        }
        Button("Rebase 当前分支到此") {
            Task { await model.rebase(onto: branch) }
        }
        Button("从此处新建分支…") {
            sheet = .newBranch(startPoint: branch.name)
        }
        Divider()
        Button("重命名…") {
            sheet = .renameBranch(branch)
        }
        if !branch.isCurrent {
            Button("删除…", role: .destructive) {
                deleteTarget = branch
            }
        }
    }

    private var remoteBranchesSection: some View {
        Section("远程分支") {
            if branches.remote.isEmpty {
                Text("尚无远程分支（fetch 后显示）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(branches.remoteGroups, id: \.name) { group in
                DisclosureGroup(group.name) {
                    ForEach(group.branches) { branch in
                        remoteBranchRow(branch)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func remoteBranchRow(_ branch: Branch) -> some View {
        Label(branch.name, systemImage: "network")
            .lineLimit(1)
            .contextMenu {
                Button("检出到本地分支") {
                    let shortName = branch.name.split(separator: "/").dropFirst().joined(separator: "/")
                    Task {
                        await model.checkoutRemote(named: shortName)
                    }
                }
            }
    }

    private var remotesSection: some View {
        Section {
            ForEach(branches.remotes) { remote in
                HStack {
                    Label(remote.name, systemImage: "server.rack")
                        .lineLimit(1)
                    Spacer()
                }
                .contextMenu {
                    Button("抓取（fetch）") {
                        Task { await model.fetchAll() }
                    }
                    Button("编辑…") { sheet = .remoteEditor(remote) }
                    Button("移除…", role: .destructive) {
                        Task { await model.removeRemote(remote) }
                    }
                }
                .help(remote.url)
            }
        } header: {
            HStack {
                Text("远程仓库")
                Spacer()
                Button {
                    sheet = .remoteEditor(nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加远程仓库")
            }
        } footer: {
            Text("凭据走系统：SSH 由 ssh-agent 处理，HTTPS 由 macOS 钥匙串处理")
        }
    }

    private var stashSection: some View {
        Section {
            if stash.entries.isEmpty {
                Text("暂无 stash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(stash.entries) { entry in
                stashRow(entry)
            }
        } header: {
            HStack {
                Text("Stash")
                Spacer()
                Button {
                    sheet = .newStash
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("暂存当前更改")
            }
        }
    }

    @ViewBuilder
    private func stashRow(_ entry: StashEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .foregroundStyle(.tint)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .lineLimit(1)
                Text(entry.selector)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.detail.select(.stash(entry))
        }
        .contextMenu {
            Button("查看 diff") { model.detail.select(.stash(entry)) }
            Button("应用（保留条目）") { Task { await model.stashApply(entry) } }
            Button("弹出（应用并删除）") { Task { await model.stashPop(entry) } }
            Button("删除…", role: .destructive) {
                Task { await model.stashDrop(entry) }
            }
        }
    }

    private var tagsSection: some View {
        Section {
            if tags.entries.isEmpty {
                Text("尚无标签")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(tags.entries) { tag in
                tagRow(tag)
            }
        } header: {
            HStack {
                Text("标签")
                Spacer()
                Button {
                    sheet = .newTag(target: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建标签")
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: TagEntry) -> some View {
        HStack(spacing: 6) {
            Label(tag.name, systemImage: "tag")
                .lineLimit(1)
            Spacer()
            Text(tag.isAnnotated ? "附注" : "轻量")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button("推送到远程") { Task { await model.pushTag(tag) } }
            Button("删除…", role: .destructive) {
                Task { await model.deleteTag(tag) }
            }
        }
        .help(tag.message.isEmpty ? tag.name : tag.message)
    }

    // MARK: - Helpers

    private func rowButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func sheetView(_ target: SidebarSheet) -> some View {
        switch target {
        case .newBranch(let startPoint):
            NewBranchSheet(model: model, startPointHint: startPoint) { sheet = nil }
        case .renameBranch(let branch):
            RenameBranchSheet(model: model, branch: branch) { sheet = nil }
        case .remoteEditor(let remote):
            RemoteEditorSheet(model: model, remote: remote) { sheet = nil }
        case .newStash:
            NewStashSheet(model: model) { sheet = nil }
        case .newTag(let target):
            NewTagSheet(model: model, target: target) { sheet = nil }
        }
    }
}
