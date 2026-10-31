import SwiftUI

/// Per-line blame view: author/date/sha gutter + syntax-highlighted content.
struct BlameView: View {
    let blame: BlameResult
    let fileName: String
    let truncated: Bool
    /// Present = short SHA is clickable and jumps to the commit in history.
    var onOpenCommit: ((String) -> Void)? = nil

    /// Row under the mouse -> bottom preview strip (popovers flicker).
    @State private var hoveredSha: String?

    var body: some View {
        let tracker = HighlightTracker(language: SyntaxLanguage.detect(fileName: fileName))
        VStack(spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blame.entries.enumerated()), id: \.offset) { index, entry in
                        row(entry, tracker: tracker, seed: index)
                            .onHover { hovering in
                                if hovering { hoveredSha = entry.sha }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            if let sha = hoveredSha, let commit = blame.commits[sha] {
                previewStrip(commit)
            }
        }
    }

    /// Hover preview: commit metadata without any extra git call.
    private func previewStrip(_ commit: BlameCommit) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.color(for: commit.sha))
                .frame(width: 4, height: 14)
            Text(commit.author)
                .font(.callout.weight(.medium))
            Text(Date(timeIntervalSince1970: TimeInterval(commit.timestamp)),
                 format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(commit.sha)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            if commit.isBoundary {
                Text("历史边界")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text(commit.summary)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let onOpenCommit {
                Button {
                    onOpenCommit(commit.sha)
                } label: {
                    Label("打开此提交", systemImage: "arrow.right.circle")
                }
                .controlSize(.small)
                .help("在历史视图中查看该提交详情")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func row(_ entry: BlameEntry, tracker: HighlightTracker, seed: Int) -> some View {
        let commit = blame.commits[entry.sha]
        return HStack(spacing: 0) {
            // Meta gutter: stable per-commit color chip + author + date + sha
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.color(for: entry.sha))
                    .frame(width: 4, height: 12)
                Text(commit?.author ?? "…")
                    .lineLimit(1)
                Text(Date(timeIntervalSince1970: TimeInterval(commit?.timestamp ?? 0)),
                     format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let onOpenCommit {
                    Button {
                        onOpenCommit(entry.sha)
                    } label: {
                        Text(String(entry.sha.prefix(7)))
                            .foregroundStyle(.tint)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .help("在历史中查看此提交")
                } else {
                    Text(String(entry.sha.prefix(7)))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .frame(width: 230, alignment: .leading)
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(0.03))
            .help(commit.map { "\($0.author): \($0.summary)" + ($0.isBoundary ? "（历史边界）" : "") } ?? "")
            // Content
            Text(tracker.attributed(DiffLine(kind: .context, oldNumber: nil,
                                             newNumber: entry.lineNumber,
                                             text: entry.content)))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                .padding(.trailing, 8)
        }
        .background(backgroundColor(commit))
    }

    private func backgroundColor(_ commit: BlameCommit?) -> Color {
        guard let commit, commit.isBoundary else { return .clear }
        return Color(nsColor: .separatorColor).opacity(0.15)
    }

    /// Deterministic per-sha hue from the digest (stable colors across runs).
    private static func color(for sha: String) -> Color {
        var value: UInt64 = 0
        for byte in sha.utf8.prefix(8) {
            value = value &* 31 &+ UInt64(byte)
        }
        let hue = Double(value % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.75)
    }
}
