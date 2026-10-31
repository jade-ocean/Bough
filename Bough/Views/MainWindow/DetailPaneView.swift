import SwiftUI

/// Right column: commit detail (header + changed files + diff) or a single
/// working-copy file diff.
struct DetailPaneView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Group {
            switch model.detail.selection {
            case .commit:
                commitDetail
            case .worktreeFile:
                worktreeDetail
            case .stash(let entry):
                VStack(spacing: 0) {
                    stashHeader(entry)
                    DiffContentView(rendered: model.detail.rendered,
                                    showsSideBySide: sideBySideBinding,
                                    isLoading: false)
                }
            case nil:
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "变更详情",
                    message: "选择左侧提交或工作区文件查看 diff")
            }
        }
    }

    // MARK: - Commit detail

    private var commitDetail: some View {
        VStack(spacing: 0) {
            CommitHeaderView(commit: model.detail.headerCommit)
            if model.detail.files.count > 1 {
                FileChangeListView(files: model.detail.files,
                                   selected: model.detail.selectedFile) { file in
                    model.detail.selectFile(file)
                }
            }
            DiffContentView(rendered: model.detail.rendered,
                            showsSideBySide: sideBySideBinding,
                            isLoading: false,
                            showsBlame: model.detail.showsBlame,
                            blame: model.detail.blame,
                            onToggleBlame: {
                                Task { await model.detail.setBlame(!model.detail.showsBlame) }
                            },
                            onOpenCommit: { sha in
                                Task { await model.openCommit(sha: sha) }
                            })
        }
    }

    private var worktreeDetail: some View {
        VStack(spacing: 0) {
            if let file = model.detail.selectedFile {
                worktreeHeader(file)
            }
            DiffContentView(rendered: model.detail.rendered,
                            showsSideBySide: sideBySideBinding,
                            isLoading: false,
                            hunkActionTitle: hunkActionTitle,
                            hunkActionEnabled: !model.detail.selectedHunks.isEmpty,
                            onHunkAction: {
                                Task { await model.detail.applySelectedHunks(stage: hunkActionStages) }
                            },
                            hunkSelection: Binding(
                                get: { model.detail.selectedHunks },
                                set: { model.detail.selectedHunks = $0 }),
                            showsBlame: model.detail.showsBlame,
                            blame: model.detail.blame,
                            onToggleBlame: {
                                Task { await model.detail.setBlame(!model.detail.showsBlame) }
                            },
                            onOpenCommit: { sha in
                                Task { await model.openCommit(sha: sha) }
                            })
        }
    }

    /// nil = hunk actions hidden (not a worktree diff).
    private var hunkActionTitle: String? {
        guard case .worktreeFile(_, let staged, _) = model.detail.selection else { return nil }
        let count = model.detail.selectedHunks.count
        let verb = staged ? "从暂存区撤销所选 Hunk（\(count)）" : "暂存所选 Hunk（\(count)）"
        return count == 0 ? (staged ? "从暂存区撤销所选 Hunk" : "暂存所选 Hunk") : verb
    }

    private var hunkActionStages: Bool {
        guard case .worktreeFile(_, let staged, _) = model.detail.selection else { return true }
        return !staged
    }

    private var sideBySideBinding: Binding<Bool> {
        Binding(get: { model.detail.showsSideBySide },
                set: { model.detail.showsSideBySide = $0 })
    }

    private func worktreeHeader(_ file: FileChange) -> some View {
        HStack(spacing: 6) {
            StatusRow(entry: StatusEntry(path: file.path,
                                         indexStatus: file.kind == .untracked ? nil : file.asFileStatus,
                                         worktreeStatus: nil,
                                         isUntracked: file.kind == .untracked,
                                         originalPath: file.originalPath),
                      side: .worktree)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func stashHeader(_ entry: StashEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(entry.selector) · \(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)), format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("应用（保留条目）") {
                Task { await model.stashApply(entry) }
            }
            .controlSize(.small)
            Button("弹出") {
                Task { await model.stashPop(entry) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

}

/// Commit metadata strip above the file list.
struct CommitHeaderView: View {
    let commit: Commit?

    var body: some View {
        if let commit {
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject)
                    .font(.headline)
                if !commit.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(commit.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    Text(commit.authorName)
                        .foregroundStyle(.secondary)
                    Text(Date(timeIntervalSince1970: TimeInterval(commit.timestamp)),
                         format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                    Text(commit.shortSha)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commit.sha, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制完整 SHA")
                    if commit.parents.count > 1 {
                        Label("合并提交", systemImage: "arrow.triangle.merge")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// Compact changed-file list within the commit detail.
struct FileChangeListView: View {
    let files: [FileChange]
    let selected: FileChange?
    let onSelect: (FileChange) -> Void

    var body: some View {
        List(selection: Binding(get: { selected?.path },
                                set: { if let path = $0, let file = files.first(where: { $0.path == path }) {
                                    onSelect(file)
                                }})) {
            ForEach(files) { file in
                HStack(spacing: 6) {
                    Image(systemName: icon(for: file.kind))
                        .foregroundStyle(color(for: file.kind))
                        .font(.caption)
                        .frame(width: 14)
                    Text(file.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    if file.isBinary {
                        Text("二进制")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tag(file.path)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 220)
    }

    private func icon(for kind: FileChange.Kind) -> String {
        switch kind {
        case .added: "plus.circle"
        case .modified: "pencil"
        case .deleted: "minus.circle"
        case .renamed: "arrow.triangle.swap"
        case .copied: "doc.on.doc"
        case .typechange: "arrow.triangle.2.circlepath"
        case .untracked: "questionmark.circle"
        }
    }

    private func color(for kind: FileChange.Kind) -> Color {
        switch kind {
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        case .renamed, .copied: .blue
        case .typechange: .purple
        case .untracked: .gray
        }
    }
}
