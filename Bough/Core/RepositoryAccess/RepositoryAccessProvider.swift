import Foundation

/// Filesystem access abstraction for repositories.
///
/// Architecture rule: all repository path I/O must go through this protocol.
/// - DirectPathAccessProvider: non-sandboxed direct paths (current mode)
/// - SecurityScopedAccessProvider: sandboxed bookmark-based skeleton (reserved)
protocol RepositoryAccessProvider: Sendable {
    /// Validate `path` and return the enclosing worktree root.
    func resolveWorkTreeRoot(at path: String) throws -> URL

    /// Return the real gitdir behind a worktree root.
    func resolveGitDirectory(forWorkTreeRoot root: URL) throws -> URL

    /// Read a file inside the worktree (conflict resolution, worktree image preview).
    func dataForFile(at absoluteURL: URL) throws -> Data

    /// Write a file inside the worktree (resolved conflict content).
    func writeData(_ data: Data, to absoluteURL: URL) throws
}
