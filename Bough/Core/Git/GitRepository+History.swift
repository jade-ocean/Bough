import Foundation

/// History, diff, and HEAD-mutating operations (Phase 3).
extension GitRepository {

    // MARK: - History

    /// `git log --topo-order` with optional filters; parents included for the graph.
    func commits(filter: HistoryFilter) async throws -> [Commit] {
        var args = ["log", "--topo-order", "-n", "2000"]
        if filter.allBranches { args.append("--all") }
        args.append(contentsOf: [
            "--pretty=format:%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%s%x1e",
        ])
        if !filter.author.isEmpty {
            args += ["--author", filter.author]
        }
        if !filter.text.isEmpty {
            args += ["--grep", filter.text, "--regexp-ignore-case"]
        }
        if let since = filter.since {
            args += ["--since", Self.gitDate(since)]
        }
        if let until = filter.until {
            args += ["--until", Self.gitDate(until)]
        }
        if !filter.path.isEmpty {
            args += ["--", filter.path]
        }
        let result = try await runOrThrow(args)
        return GitLogParser.parseHistory(result.stdoutText)
    }

    private static func gitDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Commit metadata (with body) for the detail header.
    func commitBody(sha: String) async throws -> Commit? {
        let result = try await runOrThrow([
            "log", "-1", "--encoding=UTF-8",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%b%x1e",
            sha,
        ])
        return GitLogParser.parseSingle(result.stdoutText)
    }

    /// sha -> decorations (HEAD / branches / tags / remotes) via for-each-ref.
    func refDecorations() async throws -> [String: [RefDecoration]] {
        let result = try await runOrThrow([
            "for-each-ref",
            "--format=%(objectname)%00%(refname)%00%(HEAD)",
        ])
        var map: [String: [RefDecoration]] = [:]
        for line in result.stdoutText.split(separator: "\n") {
            let fields = line.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { continue }
            guard let decoration = RefDecoration(refname: fields[1], isHead: fields.count > 2 && fields[2] == "*") else {
                continue
            }
            map[fields[0], default: []].append(decoration)
        }
        return map
    }

    /// HEAD sha; nil on unborn repository.
    func headSha() async throws -> String? {
        let result = try await run(["rev-parse", "--verify", "-q", "HEAD"])
        guard result.succeeded else { return nil }
        let text = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension GitRepository {

    // MARK: - Diff

    /// Files changed by a commit (name-status merged with numstat for binary flags).
    func changedFiles(sha: String) async throws -> [FileChange] {
        let statusResult = try await runOrThrow([
            "diff-tree", "--no-commit-id", "--name-status", "--root", "-r", "-M", sha,
        ])
        let numstatResult = try await run([
            "diff-tree", "--no-commit-id", "--numstat", "--root", "-r", "-M", sha,
        ])
        let binaryPaths = Self.binaryPaths(from: numstatResult.stdoutText)
        var changes: [FileChange] = []
        for line in statusResult.stdoutText.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let letter = columns.first, let kind = FileChange.Kind(rawValue: String(letter.prefix(1))) else {
                continue
            }
            switch kind {
            case .renamed, .copied:
                guard columns.count >= 3 else { continue }
                changes.append(FileChange(path: columns[2], originalPath: columns[1],
                                          kind: kind, isBinary: binaryPaths.contains(columns[2])))
            default:
                guard columns.count >= 2 else { continue }
                changes.append(FileChange(path: columns[1], originalPath: nil,
                                          kind: kind, isBinary: binaryPaths.contains(columns[1])))
            }
        }
        return changes
    }

    /// numstat lines "-\t-\tpath" mark binary content.
    private static func binaryPaths(from numstat: String) -> Set<String> {
        var paths: Set<String> = []
        for line in numstat.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if columns.count >= 3, columns[0] == "-", columns[1] == "-" {
                paths.insert(columns[2])
            }
        }
        return paths
    }

    /// Unified diff text for one file within a commit (root-commit aware).
    func fileDiff(sha: String, path: String) async throws -> Data {
        let isRoot = try await isRootCommit(sha)
        let args: [String]
        if isRoot {
            args = ["show", "--format=", "--no-color", "-U3", sha, "--", path]
        } else {
            args = ["diff", "--no-color", "-U3", "\(sha)^", sha, "--", path]
        }
        return try await runOrThrow(args).stdout
    }

    private func isRootCommit(_ sha: String) async throws -> Bool {
        let result = try await run(["rev-list", "--parents", "-n", "1", sha])
        // "sha parent1 parent2" - root commits list no parents.
        let line = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.split(separator: " ").count == 1
    }

    /// Unified diff for a working-copy file (staged / unstaged / untracked).
    func worktreeDiff(path: String, staged: Bool, isUntracked: Bool) async throws -> Data {
        if isUntracked {
            // Exit code 1 = differences found (expected).
            let result = try await run(["diff", "--no-index", "--no-color", "-U3", "--", "/dev/null", path])
            return result.stdout
        }
        let args = staged
            ? ["diff", "--cached", "--no-color", "-U3", "--", path]
            : ["diff", "--no-color", "-U3", "--", path]
        return try await runOrThrow(args).stdout
    }

    /// Blob content at a ref (for image previews): `git show <ref>:<path>`.
    func blobContent(ref: String, path: String) async throws -> Data {
        try await runOrThrow(["show", "\(ref):\(path)"]).stdout
    }

    // MARK: - HEAD operations (context menu)

    /// Detach HEAD onto a commit.
    func checkoutCommit(sha: String) async throws {
        try await runOrThrow(["checkout", "-q", sha])
    }

    /// Create a revert commit for sha.
    func revert(sha: String) async throws {
        try await runOrThrow(["revert", "--no-edit", sha])
    }

    func cherryPick(sha: String) async throws {
        try await runOrThrow(["cherry-pick", sha])
    }

    enum ResetMode: String, CaseIterable, Sendable {
        case soft
        case mixed
        case hard
    }

    func reset(sha: String, mode: ResetMode) async throws {
        try await runOrThrow(["reset", "--" + mode.rawValue, sha])
    }
}
