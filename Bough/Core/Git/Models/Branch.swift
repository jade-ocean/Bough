import Foundation

/// A local or remote branch with optional ahead/behind tracking info.
struct Branch: Identifiable, Equatable, Sendable {
    /// Local: short name ("feature/x"). Remote: "origin/feature/x".
    let name: String
    let sha: String
    let isRemote: Bool
    /// Remote-tracking short name ("origin/main"); local branches only.
    let upstream: String?
    let ahead: Int
    let behind: Int
    /// True when HEAD points at this branch (local branches only).
    let isCurrent: Bool

    var id: String { (isRemote ? "r:" : "l:") + name }
    var displayName: String { isRemote ? name : name }
}

/// Entry from `git remote -v`.
struct RemoteInfo: Identifiable, Equatable, Sendable {
    let name: String
    /// Fetch URL (push URL falls back to it unless overridden).
    let url: String
    let pushURL: String?

    var id: String { name }
}
