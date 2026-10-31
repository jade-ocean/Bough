import SwiftUI

/// Per-line blame view: author/date/sha gutter + syntax-highlighted content.
struct BlameView: View {
    let blame: BlameResult
    let fileName: String
    let truncated: Bool
    /// Present = short SHA is clickable and jumps to the commit in history.
    var onOpenCommit: ((String) -> Void)? = nil

    var body: some View {
        let tracker = HighlightTracker(language: SyntaxLanguage.detect(fileName: fileName))
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blame.entries.enumerated()), id: \.offset) { index, entry in
                    row(entry, tracker: tracker, seed: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
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
