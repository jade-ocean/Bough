import SwiftUI

/// Three-way conflict resolution: per-block ours/theirs/both choices,
/// then save + `git add` to mark the file resolved.
struct ConflictSheet: View {
    @ObservedObject var conflict: ConflictModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                fileList
                    .frame(width: 220)
                Divider()
                blockArea
            }
        }
        .frame(width: 860, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.merge")
                .foregroundStyle(.orange)
            Text("解决冲突")
                .font(.headline)
            if !conflict.files.isEmpty {
                Text("剩 \(conflict.files.count) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let notice = conflict.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var fileList: some View {
        List(selection: Binding(
            get: { conflict.selectedFile?.path },
            set: { path in
                if let path, let file = conflict.files.first(where: { $0.path == path }) {
                    Task { await conflict.select(file) }
                }
            })) {
            ForEach(conflict.files) { file in
                Label(file.path, systemImage: "exclamationmark.triangle")
                    .lineLimit(1)
                    .tag(file.path)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var blockArea: some View {
        if conflict.selectedFile == nil {
            EmptyStateView(icon: "arrow.triangle.merge",
                           title: "选择冲突文件",
                           message: "逐块选择保留 ours / theirs / 两者，然后保存并标记解决")
        } else {
            VStack(spacing: 0) {
                blockList
                footer
            }
        }
    }

    private var blockList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(conflict.parseResult.segments.enumerated()), id: \.offset) { index, segment in
                    switch segment {
                    case .plain(let text):
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .conflict(let block):
                        ConflictBlockView(block: block, blockIndex: index) { choice, idx in
                            conflict.setChoice(choice, blockIndex: idx)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var footer: some View {
        HStack {
            let total = conflict.parseResult.blocks.count
            let resolved = total - conflict.parseResult.unresolvedCount
            Text("\(resolved)/\(total) 已选择")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("标记为已解决（外部编辑）") {
                if let file = conflict.selectedFile {
                    Task { await conflict.markExternallyResolved(file) }
                }
            }
            .controlSize(.small)
            Button("保存并标记已解决") {
                Task { await conflict.saveAndStage() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!conflict.parseResult.allResolved || conflict.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// One conflict hunk: ours vs theirs columns + choice buttons.
struct ConflictBlockView: View {
    let block: ConflictParser.ConflictBlock
    let blockIndex: Int
    let onChoose: (ConflictParser.ConflictBlock.Choice, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            choiceHeader
            columnsRow
            baseNote
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(block.choice == nil ? Color.orange.opacity(0.10) : Color.green.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(block.choice == nil ? Color.orange.opacity(0.4) : Color.green.opacity(0.4)))
    }

    private var choiceHeader: some View {
        HStack(spacing: 6) {
            Text("冲突 #\(blockIndex + 1)")
                .font(.caption.weight(.medium))
            Spacer()
            ForEach(ConflictParser.ConflictBlock.Choice.allCases, id: \.self) { choice in
                choiceButton(choice)
            }
        }
    }

    @ViewBuilder
    private func choiceButton(_ choice: ConflictParser.ConflictBlock.Choice) -> some View {
        if choice == block.choice {
            Button {
                onChoose(choice, blockIndex)
            } label: {
                Text(choiceLabel(choice))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button {
                onChoose(choice, blockIndex)
            } label: {
                Text(choiceLabel(choice))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var columnsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            sideColumn(title: "ours（当前分支）", lines: block.ours, highlight: showsOurs)
            sideColumn(title: "theirs（合入方）", lines: block.theirs, highlight: showsTheirs)
        }
    }

    private var showsOurs: Bool { block.choice == .ours || block.choice == .both }
    private var showsTheirs: Bool { block.choice == .theirs || block.choice == .both }

    @ViewBuilder
    private var baseNote: some View {
        if !block.base.isEmpty {
            Text("基线（diff3）：" + block.base.joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }

    private func choiceLabel(_ choice: ConflictParser.ConflictBlock.Choice) -> String {
        switch choice {
        case .ours: return "用 ours"
        case .theirs: return "用 theirs"
        case .both: return "两者保留"
        }
    }

    private func sideColumn(title: String, lines: [String], highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(highlight ? Color.green.opacity(0.10) : .clear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
