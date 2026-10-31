import SwiftUI

/// All commits that touched one file (`git log --follow`), newest first.
/// Clicking an entry jumps to that commit with the file's diff pre-selected -
/// closing the blame/file-history loop.
struct FileHistoryTarget: Identifiable {
    /// Ref to walk history from (commit sha or "HEAD").
    let sha: String
    let path: String
    var id: String { sha + ":" + path }
}

struct FileHistorySheet: View {
    @ObservedObject var model: WorkspaceModel
    let target: FileHistoryTarget
    let onClose: () -> Void

    @State private var entries: [Commit] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView("读取文件历史…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                EmptyStateView(icon: "exclamationmark.triangle",
                               title: "读取失败", message: errorText)
            } else if entries.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath",
                               title: "没有提交",
                               message: "该文件在此范围内没有变更记录")
            } else {
                List {
                    ForEach(entries) { commit in
                        row(commit)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("文件历史")
                    .font(.headline)
                Text("\(target.path) · \(String(target.sha.prefix(7)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Text("\(entries.count) 次变更")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject)
                .font(.callout)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(commit.authorName)
                    .foregroundStyle(.secondary)
                Text(Date(timeIntervalSince1970: TimeInterval(commit.timestamp)),
                     format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                Text(commit.shortSha)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onClose()
            Task { await model.openCommit(sha: commit.sha, fileName: target.path) }
        }
        .help("点击跳转到该提交并定位此文件的 diff")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await model.repository.fileHistory(path: target.path,
                                                             ref: target.sha)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
