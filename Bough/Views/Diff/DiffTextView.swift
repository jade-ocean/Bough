import SwiftUI

/// Text diff renderer: inline (single column) or side-by-side.
struct DiffTextView: View {
    let file: DiffFile
    let fileName: String
    let showsSideBySide: Bool

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsSideBySide {
                    SideBySideBody(file: file, fileName: fileName)
                } else {
                    InlineBody(file: file, fileName: fileName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }
}

// MARK: - Inline body

private struct InlineBody: View {
    let file: DiffFile
    let fileName: String

    var body: some View {
        let tracker = HighlightTracker(language: SyntaxLanguage.detect(fileName: fileName))
        ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
            HunkHeader(hunk: hunk)
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                InlineRow(line: line, tracker: tracker)
            }
        }
    }
}

private struct HunkHeader: View {
    let hunk: DiffHunk

    var body: some View {
        Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@ \(hunk.section)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .separatorColor).opacity(0.25))
    }
}

private struct InlineRow: View {
    let line: DiffLine
    let tracker: HighlightTracker

    var body: some View {
        HStack(spacing: 0) {
            GutterCell(value: line.oldNumber, width: 44)
            GutterCell(value: line.newNumber, width: 44)
            Text(tracker.attributed(line))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                .padding(.trailing, 8)
        }
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added: return Color.green.opacity(0.12)
        case .deleted: return Color.red.opacity(0.10)
        case .context: return .clear
        }
    }
}

private struct GutterCell: View {
    let value: Int?
    let width: CGFloat

    var body: some View {
        Text(value.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: width, alignment: .trailing)
            .padding(.horizontal, 4)
    }
}

// MARK: - Side-by-side body

private struct SideBySideBody: View {
    let file: DiffFile
    let fileName: String

    var body: some View {
        let tracker = HighlightTracker(language: SyntaxLanguage.detect(fileName: fileName))
        ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
            HStack(spacing: 0) {
                columnCaption("旧")
                Divider()
                columnCaption("新")
            }
            ForEach(Array(DiffParser.sideBySidePairs(hunk).enumerated()), id: \.offset) { _, pair in
                SideBySideRow(pair: pair, tracker: tracker)
            }
        }
    }

    private func columnCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .separatorColor).opacity(0.25))
    }
}

private struct SideBySideRow: View {
    let pair: DiffParser.SidePair
    let tracker: HighlightTracker

    var body: some View {
        HStack(spacing: 0) {
            halfColumn(line: pair.left)
            Divider()
            halfColumn(line: pair.right)
        }
        .background(backgroundColor)
    }

    @ViewBuilder
    private func halfColumn(line: DiffLine?) -> some View {
        HStack(spacing: 0) {
            GutterCell(value: line?.oldNumber ?? line?.newNumber, width: 40)
            Text(line.map { tracker.attributed($0) } ?? AttributedString(" "))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundColor: Color {
        if let kind = pair.left?.kind, kind == .deleted { return Color.red.opacity(0.10) }
        if let kind = pair.right?.kind, kind == .added { return Color.green.opacity(0.12) }
        return .clear
    }
}
