import Foundation

/// Typed facade over one repository's git operations.
/// All calls run through the per-repo actor executor (serialized per repo).
struct GitRepository: Sendable {
    let root: URL

    private let executor: GitCommandExecutor

    /// - Parameters:
    ///   - root: validated worktree root (from RepositoryAccessProvider).
    ///   - gitBinary: explicit binary path; nil uses GitLocator.
    init(root: URL, gitBinary: String? = nil) throws {
        self.root = root
        let binary: String
        if let gitBinary {
            binary = gitBinary
        } else {
            binary = try GitLocator.locate()
        }
        self.executor = GitCommandExecutor(gitBinary: binary, workingDirectory: root)
    }

    // MARK: - Primitives

    /// Internal so the +History extension (separate file) can reuse the executor.
    @discardableResult
    func run(_ arguments: [String], timeout: TimeInterval = 30,
             extraEnvironment: [String: String] = [:]) async throws -> GitResult {
        try await executor.run(GitCommand(arguments, timeout: timeout,
                                          extraEnvironment: extraEnvironment))
    }

    /// Fail with a typed error when git exits non-zero.
    func runOrThrow(_ arguments: [String], timeout: TimeInterval = 30,
                    extraEnvironment: [String: String] = [:]) async throws -> GitResult {
        let result = try await run(arguments, timeout: timeout, extraEnvironment: extraEnvironment)
        guard result.succeeded else {
            throw GitError.executionFailed(
                command: arguments.joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderr)
        }
        return result
    }

    // MARK: - Introspection

    /// Canonical root via `git rev-parse --show-toplevel` (cross-checks the locator).
    static func validateRoot(_ url: URL, gitBinary: String) async throws -> URL {
        let executor = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: url)
        let result = try await executor.run(GitCommand(["rev-parse", "--show-toplevel"]))
        guard result.succeeded else {
            throw GitError.executionFailed(command: "rev-parse --show-toplevel",
                                           exitCode: result.exitCode, stderr: result.stderr)
        }
        let path = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw GitError.unexpectedOutput("empty toplevel") }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// `git --version` smoke probe used by tests and diagnostics.
    func version() async throws -> String {
        let result = try await runOrThrow(["--version"])
        return result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // MARK: - Status

    /// `git status --porcelain=v2 -z --branch --untracked-files=all`
    func status() async throws -> GitStatus {
        let result = try await runOrThrow([
            "status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all",
        ])
        return try GitStatusParser.parse(result.stdout)
    }

    // MARK: - Identity

    /// Repo-visible identity (local config overrides ~/.gitconfig); nil when unset.
    func identity() async throws -> GitIdentity {
        GitIdentity(name: try await configValue("user.name"),
                    email: try await configValue("user.email"))
    }

    /// Internal so extensions can read repo config (SSL settings etc.).
    func configValue(_ key: String) async throws -> String? {
        // Exit code 1 = key unset (not an error for our purposes).
        guard let result = try? await run(["config", "--get", key]) else { return nil }
        let value = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Staging

    /// `git add -A -- <paths>`: stages content, modification, and deletion in one shot.
    func stage(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await runOrThrow(["add", "-A", "--"] + paths)
    }

    /// Stage every current change (same as clicking each row).
    func stageAll() async throws {
        try await runOrThrow(["add", "-A"])
    }

    /// `git restore --staged -- <paths>`; on unborn HEAD falls back to
    /// `git rm --cached -r -q --` which also handles the no-commit repo.
    func unstage(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let restore = try await run(["restore", "--staged", "--"] + paths)
        if restore.succeeded { return }
        _ = try await runOrThrow(["rm", "--cached", "-r", "-q", "--"] + paths)
    }

    // MARK: - Discard

    /// Discard tracked-file changes back to HEAD (index + worktree), and delete
    /// untracked files. Destructive - the UI must confirm first.
    func discard(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await runOrThrow(["checkout", "HEAD", "--"] + paths)
    }

    /// Delete untracked files: `git clean -f -q -- <paths>`.
    func discardUntracked(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await runOrThrow(["clean", "-f", "-q", "--"] + paths)
    }

    // MARK: - Commit

    /// `git commit -m <msg> [--amend] [--gpgsign|--no-gpgsign]`
    /// Returns the new HEAD sha (via `rev-parse HEAD` after success).
    @discardableResult
    func commit(message: String, amend: Bool = false, signing: CommitSigning = .followConfig) async throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitError.executionFailed(command: "commit", exitCode: -1, stderr: "提交信息为空")
        }
        var args = ["commit", "-m", trimmed]
        if amend { args += ["--amend"] }
        args += signing.arguments
        _ = try await runOrThrow(args)
        let head = try await runOrThrow(["rev-parse", "HEAD"])
        return head.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Last commit on HEAD for amend prefill; nil on unborn HEAD.
    func lastCommit() async throws -> Commit? {
        let isUnborn = try await isHeadUnborn()
        if isUnborn { return nil }
        let result = try await runOrThrow([
            "log", "-1", "--encoding=UTF-8",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%b%x1e",
        ])
        return GitLogParser.parseSingle(result.stdoutText)
    }

    private func isHeadUnborn() async throws -> Bool {
        let result = try await run(["rev-parse", "--verify", "-q", "HEAD"])
        return !result.succeeded
    }
}
