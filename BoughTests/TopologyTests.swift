import XCTest
@testable import Bough

/// Submodule & worktree topology parsing (real git).
final class TopologyTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughTopologyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    private func shell(_ args: [String], in directory: URL) async throws {
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: directory)
        let result = try await setup.run(GitCommand(args))
        guard result.succeeded else {
            throw GitError.executionFailed(command: args.joined(separator: " "),
                                           exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    private func makeRepo(name: String) async throws -> URL {
        let dir = tempRoot.appendingPathComponent(name, isDirectory: true)
        try await shell(["init", "-q", "-b", "main", dir.path], in: tempRoot)
        try await shell(["config", "user.name", "Topo"], in: dir)
        try await shell(["config", "user.email", "t@bough.local"], in: dir)
        return dir
    }

    func testNoSubmodulesOrWorktrees() async throws {
        let dir = try await makeRepo(name: "plain")
        try "x\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: dir)
        try await shell(["commit", "-q", "-m", "c1"], in: dir)
        let repo = try GitRepository(root: dir, gitBinary: gitBinary)
        let subs = await repo.submodules()
        let wts = await repo.worktrees()
        XCTAssertTrue(subs.isEmpty)
        XCTAssertEqual(wts.count, 1)
        XCTAssertTrue(wts[0].isMain)
        XCTAssertTrue(wts[0].isCurrent)
    }

    func testSubmoduleStatusParsing() async throws {
        let inner = try await makeRepo(name: "inner")
        try "lib\n".write(to: inner.appendingPathComponent("lib.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: inner)
        try await shell(["commit", "-q", "-m", "lib"], in: inner)
        let outer = try await makeRepo(name: "outer")
        try await shell(["-c", "protocol.file.allow=always",
                         "submodule", "add", "-q", inner.path, "vendor/lib"], in: outer)
        try await shell(["commit", "-q", "-m", "add submodule"], in: outer)

        let repo = try GitRepository(root: outer, gitBinary: gitBinary)
        let subs = await repo.submodules()
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].path, "vendor/lib")
        XCTAssertEqual(subs[0].sha.count, 40)
        XCTAssertTrue(subs[0].isInitialized)
        XCTAssertFalse(subs[0].differsFromRecorded)
        XCTAssertEqual(subs[0].stateText, "正常")
    }

    func testWorktreeListParsing() async throws {
        let dir = try await makeRepo(name: "wt-main")
        try "x\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: dir)
        try await shell(["commit", "-q", "-m", "c1"], in: dir)
        try await shell(["branch", "topic"], in: dir)
        try await shell(["worktree", "add", "-q", "../wt-topic", "topic"], in: dir)

        let repo = try GitRepository(root: dir, gitBinary: gitBinary)
        let wts = await repo.worktrees()
        XCTAssertEqual(wts.count, 2)
        XCTAssertTrue(wts[0].isMain)
        XCTAssertTrue(wts[0].isCurrent)
        XCTAssertEqual(wts[0].branchName, "main")
        XCTAssertFalse(wts[1].isMain)
        XCTAssertFalse(wts[1].isCurrent)
        XCTAssertEqual(wts[1].branchName, "topic")
        XCTAssertTrue(wts[1].path.hasSuffix("wt-topic"))
    }
}
