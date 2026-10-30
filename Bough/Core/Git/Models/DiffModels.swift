import Foundation

/// One line of a unified diff.
struct DiffLine: Equatable, Sendable {
    enum Kind: Character, Sendable, Equatable {
        case context = " "
        case added = "+"
        case deleted = "-"
    }

    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
}

/// A `@@ -a,b +c,d @@` hunk with its lines.
struct DiffHunk: Equatable, Sendable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let section: String
    let lines: [DiffLine]
}

/// Parsed diff of one file (first file if the payload contained several).
struct DiffFile: Equatable, Sendable {
    let hunks: [DiffHunk]
    let isBinary: Bool
    /// Path extracted from the "+++ b/..." header when present.
    let path: String?
}

/// History query parameters, translated into `git log` arguments.
struct HistoryFilter: Equatable, Sendable {
    var text = ""
    /// Empty means all authors.
    var author = ""
    var path = ""
    var since: Date?
    var until: Date?
    /// `--all`: include refs other than HEAD.
    var allBranches = true

    var isEmpty: Bool {
        text.isEmpty && author.isEmpty && path.isEmpty && since == nil && until == nil
    }
}
