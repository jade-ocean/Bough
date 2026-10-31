import SwiftUI

/// Renders the selected file's diff: text (inline/side-by-side), image preview,
/// or binary notice. Owns the display-mode toggle.
struct DiffContentView: View {
    let rendered: DetailModel.RenderedDiff?
    @Binding var showsSideBySide: Bool
    let isLoading: Bool
    /// Partial-staging action (worktree mode only): title nil hides the button.
    var hunkActionTitle: String? = nil
    var hunkActionEnabled: Bool = false
    var onHunkAction: (() -> Void)? = nil
    var hunkSelection: Binding<Set<Int>>? = nil
    // Blame mode (text files with history only).
    var showsBlame = false
    var blame: BlameResult? = nil
    var onToggleBlame: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            if isLoading {
                VStack {
                    ProgressView().controlSize(.regular)
                    Text("正在加载 diff…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let rendered {
                content(for: rendered)
                if rendered.truncated {
                    truncationNotice
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var blameToggleButton: some View {
        if showsBlame {
            Button {
                onToggleBlame?()
            } label: {
                Image(systemName: "text.justify.leading")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("退出 Blame")
        } else {
            Button {
                onToggleBlame?()
            } label: {
                Image(systemName: "text.justify.leading")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(rendered?.newImage != nil || rendered?.oldImage != nil
                      || rendered?.fileChange?.isImage == true)
            .help("逐行 Blame（作者 / 日期 / 提交）")
        }
    }

    private var modeBar: some View {
        HStack(spacing: 8) {
            Text(rendered?.fileChange?.displayPath ?? "未选择文件")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(rendered?.fileChange?.displayPath ?? "")
            Spacer()
            if let hunkActionTitle, let onHunkAction {
                Button(hunkActionTitle) { onHunkAction() }
                    .controlSize(.small)
                    .disabled(!hunkActionEnabled)
            }
            if let onToggleBlame {
                blameToggleButton
            }
            Picker("模式", selection: $showsSideBySide) {
                Text("内联").tag(false)
                Text("并排").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .disabled(rendered?.diff == nil || showsBlame)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func content(for rendered: DetailModel.RenderedDiff) -> some View {
        if let old = rendered.oldImage, let new = rendered.newImage {
            ImageDiffView(oldImage: old, newImage: new)
        } else if let image = rendered.newImage ?? rendered.oldImage {
            ImageDiffView(oldImage: nil, newImage: image)
        } else if rendered.diff?.isBinary == true {
            binaryNotice
        } else if let blame {
            BlameView(blame: blame,
                      fileName: rendered.fileChange?.path ?? "",
                      truncated: rendered.truncated)
        } else if let diff = rendered.diff {
            DiffTextView(file: diff,
                         fileName: rendered.fileChange?.path ?? "",
                         showsSideBySide: showsSideBySide,
                         hunkSelection: hunkSelection)
        } else {
            EmptyStateView(icon: "equal.circle",
                           title: "无差异",
                           message: "该文件在此提交中没有文本差异")
        }
    }

    private var binaryNotice: some View {
        EmptyStateView(icon: "doc.questionmark",
                       title: "二进制文件",
                       message: "此文件为二进制内容，无法渲染文本 diff")
    }

    private var truncationNotice: some View {
        Text("差异过大，仅显示前 5000 行")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}

/// Side-by-side preview of the two blob versions of an image file.
struct ImageDiffView: View {
    let oldImage: NSImage?
    let newImage: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let old = oldImage {
                imageCard(old, label: "旧版本")
            }
            if let new = newImage {
                imageCard(new, label: "新版本")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func imageCard(_ image: NSImage, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 360, maxHeight: 320)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}
