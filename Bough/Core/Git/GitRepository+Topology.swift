import Foundation

/// Read-only topology display (P1 #11): submodules + linked worktrees.
extension GitRepository {

    // MARK: - Submodules

    struct SubmoduleInfo: Identifiable, Equatable, Sendable {
        let path: String
        let sha: String
        /// ' ' in sync, '-' not initialized, '+' checked-out commit differs.
        let stateMarker: Character

        var id: String { path }
        var isInitialized: Bool { stateMarker != "-" }
        var differsFromRecorded: Bool { stateMarker == "+" }

        var stateText: String {
            switch stateMarker {
            case "-": return "未初始化"
            case "+": return "与记录不一致"
            case "U": return "有冲突"
            default: return "正常"
            }
        }
    }

    /// `git submodule status --recursive` (empty output when none).
    func submodules() async -> [SubmoduleInfo] {
        guard let result = try? await run(["submodule", "status", "--recursive"], serial: false) else {
            return []
        }
        guard result.succeeded else { return [] }
        return result.stdoutText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard line.count > 42 else { return nil }
                let marker = line.first ?? " "
                let sha = String(line.dropFirst().prefix(40))
                let rest = String(line.dropFirst(41)).trimmingCharacters(in: .whitespaces)
                let path = rest.split(separator: " ").first.map(String.init) ?? rest
                guard !path.isEmpty, sha.count == 40 else { return nil }
                return SubmoduleInfo(path: path, sha: sha, stateMarker: marker)
            }
    }

    // MARK: - Worktrees

    struct WorktreeInfo: Identifiable, Equatable, Sendable {
        let path: String
        let sha: String?
        /// Short branch name; nil when detached or bare.
        let branchName: String?
        let isBare: Bool
        let isLocked: Bool
        /// First entry of `git worktree list` is the main worktree.
        let isMain: Bool

        var id: String { path }
        var isCurrent: Bool
    }

    /// Path equality after resolving symlinks on BOTH sides (macOS /var ->
    /// /private/var makes raw string comparison unreliable for temp dirs).
    fileprivate static func samePath(_ a: String, _ b: String) -> Bool {
        (a as NSString).resolvingSymlinksInPath == (b as NSString).resolvingSymlinksInPath
    }

    /// `git worktree list --porcelain` block format.
    func worktrees() async -> [WorktreeInfo] {
        guard let result = try? await run(["worktree", "list", "--porcelain"], serial: false) else {
            return []
        }
        guard result.succeeded else { return [] }
        var infos: [WorktreeInfo] = []
        var current: (path: String, sha: String?, branch: String?, bare: Bool, locked: Bool)?
        func flush() {
            guard let entry = current else { return }
            let isMain = infos.isEmpty
            infos.append(WorktreeInfo(
                path: entry.path, sha: entry.sha,
                branchName: entry.branch.map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 },
                isBare: entry.bare, isLocked: entry.locked, isMain: isMain,
                isCurrent: Self.samePath(entry.path, root.path)))
            current = nil
        }
        for line in result.stdoutText.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("worktree ") {
                flush()
                current = (String(line.dropFirst("worktree ".count)), nil, nil, false, false)
            } else if line.hasPrefix("HEAD ") {
                current?.sha = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                current?.branch = String(line.dropFirst("branch ".count))
            } else if line == "bare" {
                current?.bare = true
            } else if line.hasPrefix("locked") {
                current?.locked = true
            }
        }
        flush()
        return infos
    }
}
