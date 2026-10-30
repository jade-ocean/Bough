import Foundation

/// A stash entry from `git stash list`.
struct StashEntry: Identifiable, Equatable, Sendable {
    /// Reflog selector, e.g. "stash@{0}".
    let selector: String
    let sha: String
    /// Reflog subject, e.g. "WIP on main: abc1234 msg".
    let message: String
    let timestamp: Int

    var id: String { selector }
}

/// Stash lifecycle (Phase 5).
extension GitRepository {

    /// `git stash list --pretty=format:%gd%x1f%H%x1f%at%x1f%gs%x1e`
    func stashList() async throws -> [StashEntry] {
        let result = try await runOrThrow([
            "stash", "list", "--pretty=format:%gd%x1f%H%x1f%at%x1f%gs%x1e",
        ])
        return result.stdoutText
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { raw in
                let record = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard fields.count == 4 else { return nil }
                return StashEntry(selector: String(fields[0]),
                                  sha: String(fields[1]),
                                  message: String(fields[3]),
                                  timestamp: Int(fields[2]) ?? 0)
            }
    }

    /// Stash all current changes; optionally include untracked files.
    func stashPush(message: String?, includeUntracked: Bool) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message, !message.isEmpty {
            args += ["-m", message]
        }
        _ = try await runOrThrow(args)
    }

    /// - Parameter restoreIndex: `--index` restores staged/unstaged split but
    ///   refuses when the index state doesn't match HEAD (auto-stash flows
    ///   should pass false - they only need the worktree content back).
    func stashApply(_ selector: String, restoreIndex: Bool = true) async throws {
        var args = ["stash", "apply"]
        if restoreIndex { args.append("--index") }
        args.append(selector)
        _ = try await runOrThrow(args)
    }

    func stashPop(_ selector: String) async throws {
        _ = try await runOrThrow(["stash", "pop", selector])
    }

    func stashDrop(_ selector: String) async throws {
        _ = try await runOrThrow(["stash", "drop", selector])
    }

    /// Patch text of a stash for viewing (reuses the diff pipeline).
    func stashShow(_ selector: String) async throws -> Data {
        try await runOrThrow(["stash", "show", "--no-color", "-U3", "--include-untracked", selector]).stdout
    }
}
