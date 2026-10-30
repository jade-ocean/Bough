import XCTest
@testable import Bough

/// Partial (hunk-level) staging: patch builder + real git apply --cached.
final class HunkStagingTests: XCTestCase {

    // MARK: - Patch builder (pure)

    private let twoHunkDiff = """
    diff --git a/f.txt b/f.txt
    index 111..222 100644
    --- a/f.txt
    +++ b/f.txt
    @@ -1,3 +1,3 @@ first
     a
    -b
    +B
     c
    @@ -8,3 +8,3 @@ second
     h
    -i
    +I
     j
    """

    func testPatchBuilderSelectsSingleHunk() throws {
        let patch = try XCTUnwrap(DiffParser.patch(fromDiff: twoHunkDiff, selecting: [1]))
        XCTAssertTrue(patch.hasPrefix("diff --git a/f.txt b/f.txt"))
        XCTAssertTrue(patch.contains("@@ -8,3 +8,3 @@ second"))
        XCTAssertFalse(patch.contains("@@ -1,3 +1,3 @@ first"))
        XCTAssertFalse(patch.contains("+B"))
        XCTAssertTrue(patch.contains("+I"))
    }

    func testPatchBuilderKeepsAscendingOrderAndHeader() throws {
        let patch = try XCTUnwrap(DiffParser.patch(fromDiff: twoHunkDiff, selecting: [1, 0]))
        let firstAt = try XCTUnwrap(patch.range(of: "@@ -1,3"))
        let secondAt = try XCTUnwrap(patch.range(of: "@@ -8,3"))
        XCTAssertLessThan(firstAt.lowerBound, secondAt.lowerBound)
        XCTAssertTrue(patch.contains("+B"))
        XCTAssertTrue(patch.contains("+I"))
    }

    func testPatchBuilderRejectsInvalidSelection() {
        XCTAssertNil(DiffParser.patch(fromDiff: twoHunkDiff, selecting: []))
        XCTAssertNil(DiffParser.patch(fromDiff: twoHunkDiff, selecting: [5]))
        XCTAssertNil(DiffParser.patch(fromDiff: "no hunks here", selecting: [0]))
    }

    // MARK: - Integration (real git)

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughHunkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        repo = nil
    }

    /// 10-line file on main; worktree changes line 2 and line 10 -> 2 hunks at -U3.
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
        try await git(["config", "user.name", "Hunk Test"])
        try await git(["config", "user.email", "h@bough.local"])
        let original = (1...10).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try original.write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."])
        try await git(["commit", "-q", "-m", "base"])
        var lines = (1...10).map { "line\($0)" }
        lines[1] = "line2-changed"
        lines[9] = "line10-changed"
        try (lines.joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        return try GitRepository(root: dir, gitBinary: gitBinary)
    }

    func testStageOneHunkLeavesRestUnstaged() async throws {
        let repo = try await makeRepo()
        let diff = try await repo.worktreeDiff(path: "f.txt", staged: false, isUntracked: false)
        let hunks = DiffParser.parse(String(decoding: diff, as: UTF8.self)).first?.hunks ?? []
        XCTAssertEqual(hunks.count, 2)

        try await repo.stageHunks(path: "f.txt", hunkIndices: [0])

        let status = try await repo.status()
        let entry = try XCTUnwrap(status.entries.first)
        XCTAssertEqual(entry.path, "f.txt")
        XCTAssertEqual(entry.indexStatus, .modified)   // hunk 1 staged
        XCTAssertEqual(entry.worktreeStatus, .modified) // hunk 2 still worktree-only

        let stagedDiff = String(decoding: try await repo.worktreeDiff(path: "f.txt", staged: true, isUntracked: false), as: UTF8.self)
        XCTAssertTrue(stagedDiff.contains("line2-changed"))
        XCTAssertFalse(stagedDiff.contains("line10-changed"))
    }

    func testUnstageOneHunkReversesIndex() async throws {
        let repo = try await makeRepo()
        try await repo.stage(["f.txt"]) // both hunks staged
        try await repo.unstageHunks(path: "f.txt", hunkIndices: [1])

        let stagedDiff = String(decoding: try await repo.worktreeDiff(path: "f.txt", staged: true, isUntracked: false), as: UTF8.self)
        XCTAssertTrue(stagedDiff.contains("line2-changed"))
        XCTAssertFalse(stagedDiff.contains("line10-changed"))

        let status = try await repo.status()
        let entry = try XCTUnwrap(status.entries.first)
        XCTAssertEqual(entry.indexStatus, .modified)
        XCTAssertEqual(entry.worktreeStatus, .modified)
    }
}
