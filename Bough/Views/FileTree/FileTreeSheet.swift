import SwiftUI

/// Browse a commit's snapshot with LAZY directory loading: top level via
/// one `ls-tree` call, each folder expanded on demand (scales to huge repos).
struct FileTreeSheet: View {
    @ObservedObject var model: WorkspaceModel
    let ref: String
    let title: String
    let onClose: () -> Void

    @State private var root: GitRepository.TreeNode?
    @State private var expanded: Set<String> = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var selectedFile: GitRepository.TreeNode?
    @State private var fileContent: AttributedString?
    @State private var fileImage: NSImage?
    @State private var isFileBinary = false
    @State private var isLoadingFile = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView("读取文件树…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                EmptyStateView(icon: "exclamationmark.triangle",
                               title: "读取失败", message: errorText)
            } else {
                HSplitView {
                    treePane
                        .frame(minWidth: 240, maxWidth: 320)
                    contentPane
                        .frame(minWidth: 420)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("文件树")
                    .font(.headline)
                Text("\(title) · \(String(ref.prefix(7)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Tree pane (lazy)

    @ViewBuilder
    private var treePane: some View {
        if let root {
            List {
                ForEach(root.children ?? []) { node in
                    nodeRows(node)
                }
            }
            .listStyle(.sidebar)
        } else {
            EmptyView()
        }
    }

    private func nodeRows(_ node: GitRepository.TreeNode) -> AnyView {
        if node.isFile {
            return AnyView(fileRow(node))
        } else {
            return AnyView(DisclosureGroup(isExpanded: expansionBinding(node)) {
                if node.childrenLoaded {
                    ForEach(node.children ?? []) { child in
                        nodeRows(child)
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text("加载中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                folderLabel(node)
            })
        }
    }

    private func expansionBinding(_ node: GitRepository.TreeNode) -> Binding<Bool> {
        Binding(get: { expanded.contains(node.path) },
                set: { wants in
                    if wants {
                        expanded.insert(node.path)
                        if node.childrenLoaded == false {
                            Task { await loadChildren(node) }
                        }
                    } else {
                        expanded.remove(node.path)
                    }
                })
    }

    private func folderLabel(_ node: GitRepository.TreeNode) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            Text(node.name)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private func fileRow(_ node: GitRepository.TreeNode) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "doc")
                .foregroundStyle(Color.secondary)
                .font(.caption)
            Text(node.name)
                .lineLimit(1)
            Spacer()
            if let size = node.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await loadFile(node) }
        }
        .contextMenu {
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
        }
    }

    // MARK: - Content pane

    @ViewBuilder
    private var contentPane: some View {
        if let selectedFile {
            VStack(spacing: 0) {
                contentHeader(selectedFile)
                if isLoadingFile {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let image = fileImage {
                    ScrollView {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 640)
                            .padding(16)
                    }
                } else if isFileBinary {
                    EmptyStateView(icon: "doc.questionmark",
                                   title: "二进制文件",
                                   message: "此文件为二进制内容，无法以文本查看")
                } else if let content = fileContent {
                    ScrollView([.vertical, .horizontal]) {
                        Text(content)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass",
                           title: "选择文件",
                           message: "左侧树中点击文件查看内容（目录展开时按需加载）")
        }
    }

    private func contentHeader(_ file: GitRepository.TreeNode) -> some View {
        HStack(spacing: 8) {
            Text(file.path)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.head)
                .help(file.path)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制路径")
            Button {
                saveFile(file)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("另存为…")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            root = try await model.repository.treeDir(ref: ref, prefix: "")
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadChildren(_ node: GitRepository.TreeNode) async {
        do {
            let loaded = try await model.repository.treeDir(ref: ref, prefix: node.path)
            root = GitTreeParser.updateChildren(of: node.path, in: root ?? loaded,
                                                with: loaded)
        } catch {
            model.banner = .error(error.localizedDescription)
        }
    }

    private func loadFile(_ node: GitRepository.TreeNode) async {
        selectedFile = node
        isLoadingFile = true
        defer { isLoadingFile = false }
        fileContent = nil
        fileImage = nil
        isFileBinary = false
        do {
            let data = try await model.repository.blobContent(ref: ref, path: node.path)
            if node.isImageFile {
                fileImage = NSImage(data: data)
                if fileImage != nil { return }
            }
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("\u{0}") {
                isFileBinary = true
                return
            }
            var result = AttributedString()
            let language = SyntaxLanguage.detect(fileName: node.name)
            var state = SyntaxHighlighter.State()
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                for token in SyntaxHighlighter.highlight(String(line), language: language, state: &state) {
                    var segment = AttributedString(token.text + "\n")
                    segment.foregroundColor = HighlightTracker.color(for: token.kind)
                    result += segment
                }
            }
            fileContent = result
        } catch {
            fileContent = AttributedString("读取失败：\(error.localizedDescription)")
        }
    }

    private func saveFile(_ node: GitRepository.TreeNode) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = node.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let data = try? await model.repository.blobContent(ref: ref, path: node.path) {
                try? data.write(to: url)
            }
        }
    }
}

extension GitRepository.TreeNode {
    /// Image detection by extension (shared rules with FileChange).
    var isImageFile: Bool {
        let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
        return ["png", "jpg", "jpeg", "gif", "tiff", "tif", "webp", "heic", "bmp", "icns"].contains(ext)
    }
}
