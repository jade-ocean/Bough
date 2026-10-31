import XCTest
@testable import Bough

/// Integration tests for history/diff operations against real git.
final class GitHistoryIntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughHistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        repo = nil
    }

    /// Seed: c1 <- c2 on main; feature branch with f1; merge m into main.
    private func makeRepo() async throws -> GitRepository {
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: repoDir)
        func git(_ args: [String]) async throws {
            let result = try await setup.run(GitCommand(args))
            guard result.succeeded else {
                throw GitError.executionFailed(command: args.joined(separator: " "),
                                               exitCode: result.exitCode, stderr: result.stderr)
            }
        }
        try await git(["init", "-q", "-b", "main"])
        try await git(["config", "user.name", "Hist Test"])
        try await git(["config", "user.email", "hist@bough.local"])
        try "one\n".write(to: repoDir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "c1"])
        try "two\n".write(to: repoDir.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "c2"])

        try await git(["checkout", "-q", "-b", "feature"])
        try "feat\n".write(to: repoDir.appendingPathComponent("feat.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "f1"])
        try await git(["checkout", "-q", "main"])
        try await git(["merge", "-q", "--no-ff", "-m", "merge m", "feature"])

        return try GitRepository(root: repoDir, gitBinary: gitBinary)
    }

    func testHistoryWithMergeAndParents() async throws {
        let repo = try await makeRepo()
        let commits = try await repo.commits(filter: HistoryFilter())
        // merge m, f1, c2, c1 (topo order)
        XCTAssertEqual(commits.count, 4)
        XCTAssertEqual(commits[0].subject, "merge m")
        XCTAssertEqual(commits[0].parents.count, 2)
        let rows = GraphLayouter.layout(commits)
        // merge row has a curved edge into the feature lane
        XCTAssertTrue(rows[0].edges.contains { $0.fromLane != $0.toLane })
    }

    func testRefDecorationsContainBranchesAndHead() async throws {
        let repo = try await makeRepo()
        let decorations = try await repo.refDecorations()
        let names = decorations.values.flatMap { $0 }.map(\.name)
        XCTAssertTrue(names.contains("main"))
        XCTAssertTrue(names.contains("feature"))
        let heads = decorations.values.flatMap { $0 }.filter { $0.isHead }
        XCTAssertFalse(heads.isEmpty)
    }

    func testChangedFilesAndFileDiff() async throws {
        let repo = try await makeRepo()
        let commits = try await repo.commits(filter: HistoryFilter())
        let c2 = try XCTUnwrap(commits.first { $0.subject == "c2" })
        let files = try await repo.changedFiles(sha: c2.sha)
        XCTAssertEqual(files.map(\.path), ["two.txt"])
        XCTAssertEqual(files.first?.kind, .added)

        let diff = try await repo.fileDiff(sha: c2.sha, path: "two.txt")
        let text = String(decoding: diff, as: UTF8.self)
        XCTAssertTrue(text.contains("+++ b/two.txt"))
        XCTAssertTrue(text.contains("+two"))
    }

    func testWorktreeDiffStagedAndUntracked() async throws {
        let repo = try await makeRepo()
        try "changed\n".write(to: repo.root.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let staged = String(decoding: try await repo.worktreeDiff(path: "one.txt", staged: false, isUntracked: false), as: UTF8.self)
        XCTAssertTrue(staged.contains("-one") && staged.contains("+changed"))

        try "fresh\n".write(to: repo.root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let untracked = String(decoding: try await repo.worktreeDiff(path: "new.txt", staged: false, isUntracked: true), as: UTF8.self)
        XCTAssertTrue(untracked.contains("+++"))
    }

    func testFileHistoryFollowsCommits() async throws {
        let repo = try await makeRepo()
        // one.txt touched by c1 only; add c3 touching one.txt again.
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: repo.root)
        try "one-v2\n".write(to: repo.root.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let add = try await setup.run(GitCommand(["add", "."]))
        guard add.succeeded else { throw GitError.executionFailed(command: "add", exitCode: 1, stderr: add.stderr) }
        _ = try await repo.commit(message: "c3 one")
        let history = try await repo.fileHistory(path: "one.txt")
        XCTAssertEqual(history.map(\.subject), ["c3 one", "c1"])
    }

    func testBlobContentAtRef() async throws {
        let repo = try await makeRepo()
        let head = try await repo.headSha()
        let data = try await repo.blobContent(ref: "HEAD", path: "one.txt")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "one\n")
        XCTAssertNotNil(head)
    }

    func testRevertAndResetOperations() async throws {
        let repo = try await makeRepo()
        let before = try await repo.commits(filter: HistoryFilter())
        try await repo.revert(sha: before[1].sha) // revert f1
        let afterRevert = try await repo.commits(filter: HistoryFilter())
        XCTAssertEqual(afterRevert.count, 5)
        XCTAssertTrue(afterRevert[0].subject.lowercased().contains("revert"))

        try await repo.reset(sha: before[0].sha, mode: .hard) // back to merge
        let afterReset = try await repo.commits(filter: HistoryFilter())
        XCTAssertEqual(afterReset.count, 4)
        let headAfterReset = try await repo.headSha()
        XCTAssertEqual(headAfterReset, before[0].sha)

        try await repo.checkoutCommit(sha: before[1].sha) // detach
        let status = try await repo.status()
        XCTAssertEqual(status.branch, nil) // detached HEAD has no branch name
    }

    func testCommitBodyFetch() async throws {
        let repo = try await makeRepo()
        let commits = try await repo.commits(filter: HistoryFilter())
        let body = try await repo.commitBody(sha: commits[0].sha)
        XCTAssertEqual(body?.subject, "merge m")
        XCTAssertEqual(body?.sha, commits[0].sha)
    }
}
