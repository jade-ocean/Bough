import SwiftUI

/// One history list row: graph cell, subject, author/date, ref badges.
struct HistoryRowView: View {
    let row: GraphRow
    let showsGraph: Bool
    let graphWidth: CGFloat
    let decorations: [RefDecoration]
    let isHead: Bool

    static let rowHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            if showsGraph {
                GraphCellView(row: row,
                              columnWidth: 14,
                              rowHeight: Self.rowHeight,
                              isHead: isHead)
                    .frame(width: graphWidth, height: Self.rowHeight, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.commit.subject)
                        .lineLimit(1)
                    ForEach(decorations) { decoration in
                        RefBadge(decoration: decoration)
                    }
                }
                HStack(spacing: 6) {
                    Text(row.commit.authorName)
                        .foregroundStyle(.secondary)
                    Text(Date(timeIntervalSince1970: TimeInterval(row.commit.timestamp)),
                         format: .relative(presentation: .named))
                    Text(row.commit.shortSha)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .lineLimit(1)
            }
        }
        .frame(height: Self.rowHeight)
    }
}

/// Colored capsule for HEAD / branch / tag / remote decorations.
struct RefBadge: View {
    let decoration: RefDecoration

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .help(kindName)
    }

    private var label: String {
        switch decoration.kind {
        case .head: return "HEAD"
        case .branch: return decoration.name
        case .remote: return decoration.name
        case .tag: return "\(decoration.name)"
        }
    }

    private var color: Color {
        switch decoration.kind {
        case .head: return .accentColor
        case .branch: return Color(red: 0.36, green: 0.52, blue: 0.72)
        case .remote: return Color(red: 0.48, green: 0.60, blue: 0.60)
        case .tag: return Color(red: 0.72, green: 0.58, blue: 0.35)
        }
    }

    private var kindName: String {
        switch decoration.kind {
        case .head: return "HEAD"
        case .branch: return "本地分支"
        case .remote: return "远程分支"
        case .tag: return "标签"
        }
    }
}
