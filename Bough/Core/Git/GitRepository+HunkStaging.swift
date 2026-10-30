import Foundation

/// Partial staging via `git apply --cached` (hunk granularity, P0 patch mode).
extension GitRepository {

    /// Apply a patch to the index only. `reverse: true` removes the patch's
    /// changes from the index (used for hunk-level unstage).
    func applyPatch(_ patch: Data, reverse: Bool = false) async throws {
        var args = ["apply", "--cached", "--whitespace=nowarn"]
        if reverse { args.append("--reverse") }
        try await runOrThrow(args, stdinData: patch)
    }

    /// Stage only the selected hunks (indices into the file's unstaged diff).
    func stageHunks(path: String, hunkIndices: [Int]) async throws {
        let diff = try await worktreeDiff(path: path, staged: false, isUntracked: false)
        guard let patch = DiffParser.patch(fromDiff: String(decoding: diff, as: UTF8.self),
                                           selecting: hunkIndices) else {
            throw GitError.unexpectedOutput("无效的 hunk 选择：\\(hunkIndices)")
        }
        try await applyPatch(Data(patch.utf8))
    }

    /// Unstage only the selected hunks (indices into the file's staged diff).
    func unstageHunks(path: String, hunkIndices: [Int]) async throws {
        let diff = try await worktreeDiff(path: path, staged: true, isUntracked: false)
        guard let patch = DiffParser.patch(fromDiff: String(decoding: diff, as: UTF8.self),
                                           selecting: hunkIndices) else {
            throw GitError.unexpectedOutput("无效的 hunk 选择：\\(hunkIndices)")
        }
        try await applyPatch(Data(patch.utf8), reverse: true)
    }
}
