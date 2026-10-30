import Foundation

/// Worktree/index state of a single file, from `git status --porcelain=v2`.
enum FileStatus: Character, Sendable, Equatable {
    case unmodified = "."
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case typechange = "T"
    case untracked = "?"
    case conflicted = "U"
}

/// One file's state; a file with staged AND unstaged changes yields one entry
/// with both sides set (XY = "MM") and shows in both lists.
struct StatusEntry: Identifiable, Equatable, Sendable {
    let path: String
    /// X column (staged side), nil when nothing staged.
    let indexStatus: FileStatus?
    /// Y column (worktree side), nil when worktree matches index.
    let worktreeStatus: FileStatus?
    let isUntracked: Bool
    /// Rename/copy source path.
    let originalPath: String?

    var id: String { path }
}

/// Parsed `git status --porcelain=v2 --branch` snapshot.
struct GitStatus: Equatable, Sendable {
    var branch: String?
    /// True before the first commit ("(initial)" in porcelain branch.head).
    var isUnborn = false
    var upstream: String?
    var ahead = 0
    var behind = 0
    var entries: [StatusEntry] = []

    var staged: [StatusEntry] { entries.filter { $0.indexStatus != nil } }
    var unstaged: [StatusEntry] { entries.filter { $0.worktreeStatus != nil && !$0.isUntracked } }
    var untracked: [StatusEntry] { entries.filter { $0.isUntracked } }
    var unmerged: [StatusEntry] { entries.filter { $0.worktreeStatus == .conflicted } }
    var hasChanges: Bool { !entries.isEmpty }
}
