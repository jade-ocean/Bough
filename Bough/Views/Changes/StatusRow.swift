import SwiftUI

/// Which side of a StatusEntry a row represents.
enum ChangeSide: String, Sendable {
    case staged
    case worktree
}

/// One file row: status glyph + name + directory, per side.
struct StatusRow: View {
    let entry: StatusEntry
    let side: ChangeSide

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.callout)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if let original = entry.originalPath {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(original)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Text(directory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .help(entry.path)
    }

    private var effective: FileStatus {
        switch side {
        case .staged: entry.indexStatus ?? .added
        case .worktree: entry.worktreeStatus ?? .untracked
        }
    }

    private var displayName: String {
        entry.path.split(separator: "/").last.map(String.init) ?? entry.path
    }

    private var directory: String {
        let parts = entry.path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return "仓库根目录" }
        return parts.dropLast().joined(separator: "/")
    }

    private var symbol: String {
        switch effective {
        case .added: "plus.circle"
        case .modified: "pencil"
        case .deleted: "minus.circle"
        case .renamed: "arrow.triangle.swap"
        case .copied: "doc.on.doc"
        case .typechange: "arrow.triangle.2.circlepath"
        case .conflicted: "exclamationmark.triangle"
        case .untracked: "questionmark.circle"
        case .unmodified: "circle"
        }
    }

    private var color: Color {
        switch effective {
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        case .renamed: .blue
        case .copied: .blue
        case .typechange: .purple
        case .conflicted: .red
        case .untracked: .gray
        case .unmodified: .secondary
        }
    }
}
