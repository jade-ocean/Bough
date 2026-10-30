import SwiftUI

/// Reflog browser: find dropped commits after resets/rebases and recover
/// via checkout / new branch / reset.
struct ReflogSheet: View {
    @ObservedObject var model: WorkspaceModel
    let onClose: () -> Void

    @State private var entries: [ReflogEntry] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var branchTarget: ReflogEntry?
    @State private var branchName = ""
    @State private var resetTarget: ReflogEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 680, height: 480)
        .task { await load() }
        .sheet(item: $resetTarget) { entry in
            ResetSheetView(commit: Commit(sha: entry.sha,
                                          shortSha: entry.shortSha,
                                          authorName: "", authorEmail: "",
                                          timestamp: entry.timestamp,
                                          subject: entry.operation,
                                          body: "", parents: [])) { mode in
                resetTarget = nil
                Task { await model.resetTo(sha: entry.sha, mode: mode) }
            }
        }
        .alert("从 \(branchTarget?.selector ?? "") 新建分支", isPresented: Binding(
            get: { branchTarget != nil },
            set: { if !$0 { branchTarget = nil } })) {
            TextField("分支名", text: $branchName)
            Button("创建") {
                if let target = branchTarget {
                    Task { await model.branchFromReflog(target, name: branchName) }
                }
                branchTarget = nil
                branchName = ""
            }
            Button("取消", role: .cancel) { branchTarget = nil }
        } message: {
            Text("指向 \(branchTarget?.sha.prefix(7).description ?? "")，不切换当前分支")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.tint)
            Text("Reflog（HEAD 操作历史）")
                .font(.headline)
            Spacer()
            Button("刷新") { Task { await load() } }
                .controlSize(.small)
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("读取 reflog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorText {
            EmptyStateView(icon: "exclamationmark.triangle",
                           title: "读取失败",
                           message: errorText)
        } else {
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(entry.selector)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tint)
                        Text(entry.operation)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(entry.shortSha)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)),
                             format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contextMenu {
                    Button("检出此提交（detached）") {
                        Task { await model.checkoutDetached(entry) }
                    }
                    Button("从此提交新建分支…") {
                        branchName = ""
                        branchTarget = entry
                    }
                    Button("重置当前分支到此处…") {
                        resetTarget = entry
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await model.repository.reflog()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
