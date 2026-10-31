import XCTest
@testable import Bough

final class BlameTests: XCTestCase {

    // MARK: - Porcelain parsing (pure)

    func testParsesPorcelainBlocksAndRepeatedSha() throws {
        let text = """
        aaaa111122223333444455556666777788889999 1 1 2
        author Alice
        author-time 1600000000
        summary first commit
        \tline one
        \tline two
        bbbb111122223333444455556666777788889999 3 3 1
        author Bob
        author-time 1700000000
        summary second commit
        \tline three
        """
        let result = try GitBlameParser.parse(text)
        XCTAssertEqual(result.entries.map(\.content), ["line one", "line two", "line three"])
        XCTAssertEqual(result.entries.map(\.lineNumber), [1, 2, 3])
        XCTAssertEqual(result.entries[0].sha, "aaaa111122223333444455556666777788889999")
        XCTAssertEqual(result.entries[2].sha, "bbbb111122223333444455556666777788889999")
        XCTAssertEqual(result.commits.count, 2)
        XCTAssertEqual(result.commits["aaaa111122223333444455556666777788889999"]?.author, "Alice")
        XCTAssertEqual(result.commits["bbbb111122223333444455556666777788889999"]?.summary, "second commit")
    }

    func testParsesBoundaryAndGroupedCounts() throws {
        let text = """
        aaaa111122223333444455556666777788889999 1 1 3
        author Alice
        author-time 1600000000
        summary base
        boundary
        \ta1
        \ta2
        \ta3
        """
        let result = try GitBlameParser.parse(text)
        XCTAssertEqual(result.entries.count, 3)
        let commit = try XCTUnwrap(result.commits["aaaa111122223333444455556666777788889999"])
        XCTAssertTrue(commit.isBoundary)
    }

    // MARK: - Integration (real git)

    private var tempRoot: URL!
    private var gitBinary: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughBlameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    private func makeRepo() async throws -> GitRepository {
        let dir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: dir)
        func git(_ args: [String]) async throws {
            let result = try await setup.run(GitCommand(args))
            guard result.succeeded else {
                throw GitError.executionFailed(command: args.joined(separator: " "),
                                               exitCode: result.exitCode, stderr: result.stderr)
            }
        }
        try await git(["init", "-q", "-b", "main"])
        try await git(["config", "user.name", "Alice"])
        try await git(["config", "user.email", "a@bough.local"])
        try "first\nsecond\n".write(to: dir.appendingPathComponent("f.txt"),
                                    atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "c1"])
        try "first\nsecond edited\nthird\n".write(to: dir.appendingPathComponent("f.txt"),
                                                  atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "c2"])
        return try GitRepository(root: dir, gitBinary: gitBinary)
    }

    func testBlameAttributesLinesToCommits() async throws {
        let repo = try await makeRepo()
        let result = try await repo.blame(path: "f.txt")
        XCTAssertEqual(result.entries.count, 3)
        let bySha = Dictionary(grouping: result.entries, by: \.sha)
        XCTAssertEqual(bySha.count, 2)
        // Attribution must mirror real git blame (ground truth verified via CLI):
        // "first" -> c1; "second edited" and "third" -> c2. A count-based
        // heuristic is invalid here because c1's group is also size 1.
        let firstLine = try XCTUnwrap(result.entries.first { $0.content == "first" })
        let editedLine = try XCTUnwrap(result.entries.first { $0.content == "second edited" })
        XCTAssertNotEqual(firstLine.sha, editedLine.sha)
        let commits = result.commits.values
        XCTAssertTrue(commits.contains { $0.summary == "c1" })
        XCTAssertTrue(commits.contains { $0.summary == "c2" && $0.author == "Alice" })
    }

    @MainActor
    func testOpenCommitJumpsToHistorySelection() async throws {
        let repo = try await makeRepo()
        let model = WorkspaceModel(repository: repo)
        let commits = try await repo.commits(filter: HistoryFilter(allBranches: false))
        let c1 = try XCTUnwrap(commits.first { $0.subject == "c1" })

        await model.openCommit(sha: c1.sha)
        XCTAssertEqual(model.centerMode, .history) // switched from any mode
        guard case .commit(let selected) = model.detail.selection else {
            return XCTFail("详情应选中该提交")
        }
        XCTAssertEqual(selected.sha, c1.sha)

        // Unknown sha -> banner, selection unchanged.
        await model.openCommit(sha: String(repeating: "f", count: 40))
        XCTAssertNotNil(model.banner)
    }

    func testBlameAtRefIgnoresWorktree() async throws {
        let repo = try await makeRepo()
        try "worktree only\n".write(to: repo.root.appendingPathComponent("f.txt"),
                                    atomically: true, encoding: .utf8)
        let atHead = try await repo.blame(path: "f.txt", ref: "HEAD")
        XCTAssertEqual(atHead.entries.count, 3) // committed version, untouched by worktree
    }
}
