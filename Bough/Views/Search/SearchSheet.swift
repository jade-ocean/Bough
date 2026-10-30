import SwiftUI

/// Global search: git grep over the worktree and commit search across branches.
struct SearchSheet: View {
    @ObservedObject var model: WorkspaceModel
    let onClose: () -> Void

    private var search: SearchModel { model.search }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultArea
            footer
        }
        .frame(width: 760, height: 540)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Picker("范围", selection: Binding(
                get: { search.tab },
                set: { search.tab = $0; search.scheduleSearch() })) {
                Label("代码", systemImage: "doc.text").tag(SearchModel.Tab.code)
                Label("提交", systemImage: "clock.arrow.circlepath").tag(SearchModel.Tab.commits)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索…", text: Binding(
                get: { search.query },
                set: { search.query = $0; search.scheduleSearch() }))
                .textFieldStyle(.roundedBorder)
            Toggle("Aa", isOn: Binding(
                get: { search.caseSensitive },
                set: { search.caseSensitive = $0; search.scheduleSearch() }))
                .toggleStyle(.checkbox)
                .help("区分大小写")
            if search.tab == .code {
                Toggle(".*", isOn: Binding(
                    get: { search.useRegex },
                    set: { search.useRegex = $0; search.scheduleSearch() }))
                    .toggleStyle(.checkbox)
                    .help("正则表达式")
                TextField("路径前缀（可选）", text: Binding(
                    get: { search.pathPrefix },
                    set: { search.pathPrefix = $0; search.scheduleSearch() }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultArea: some View {
        if search.isSearching {
            ProgressView("搜索中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = search.errorText {
            EmptyStateView(icon: "exclamationmark.triangle",
                           title: "搜索失败",
                           message: error)
        } else {
            switch search.tab {
            case .code:
                codeResults
            case .commits:
                commitResults
            }
        }
    }

    private var codeResults: some View {
        Group {
            if search.codeResults.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               title: search.query.isEmpty ? "输入关键词开始搜索" : "无匹配结果",
                               message: "基于 git grep 的全仓库代码检索")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(search.codeResults) { result in
                            codeRow(result)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func codeRow(_ result: GrepResult) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(result.file):\(result.line):\(result.column)")
                .font(.caption)
                .foregroundStyle(.tint)
            highlighted(result)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.03)))
        .contextMenu {
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.file, forType: .string)
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [model.repository.root.appendingPathComponent(result.file)])
            }
        }
    }

    private func highlighted(_ result: GrepResult) -> Text {
        var attributed = AttributedString(result.text)
        let range: Range<AttributedString.Index>?
        if search.useRegex, let regex = try? NSRegularExpression(pattern: search.query, options: search.caseSensitive ? [] : [.caseInsensitive]) {
            let ns = NSRange(result.text.startIndex..<result.text.endIndex, in: result.text)
            if let match = regex.firstMatch(in: result.text, options: [], range: ns),
               let swiftRange = Range(match.range, in: result.text) {
                range = AttributedString(result.text).range(of: String(result.text[swiftRange]))
            } else {
                range = nil
            }
        } else {
            range = attributed.range(of: search.query, options: search.caseSensitive ? [] : [.caseInsensitive])
        }
        if let range {
            attributed[range].backgroundColor = .yellow.opacity(0.55)
        }
        return Text(attributed)
    }

    private var commitResults: some View {
        Group {
            if search.commitResults.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               title: search.query.isEmpty ? "输入关键词开始搜索" : "无匹配提交",
                               message: "按提交消息检索所有分支（--all --grep）")
            } else {
                List(search.commitResults) { commit in
                    Button {
                        model.centerMode = .history
                        model.detail.select(.commit(commit))
                        onClose()
                    } label: {
                        HStack(spacing: 8) {
                            Text(commit.subject)
                                .lineLimit(1)
                            Spacer()
                            Text(commit.authorName)
                                .foregroundStyle(.secondary)
                            Text(commit.shortSha)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            let count = search.tab == .code ? search.codeResults.count : search.commitResults.count
            Text("\(count) 个结果" + (search.codeResults.count >= 500 ? "（已截断）" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Enter 立即搜索 · 结果自动刷新")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
