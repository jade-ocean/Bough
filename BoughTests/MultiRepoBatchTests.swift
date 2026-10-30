import XCTest
@testable import Bough

/// Multi-repo batch operations against real git repositories.
final class MultiRepoBatchTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughMultiTests-\(UUID().uuidString)", isDirectory: true)
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

    /// bare origin + clone-a (clean) + clone-b (dirty file) + a plain folder.
    private func seed() async throws -> (a: URL, b: URL, junk: URL) {
        try await shell(["init", "-q", "--bare", "-b", "main", "origin.git"], in: tempRoot)
        try await shell(["-c", "init.defaultBranch=main", "clone", "-q", "origin.git", "a"], in: tempRoot)
        let a = tempRoot.appendingPathComponent("a")
        try await shell(["config", "user.name", "Multi"], in: a)
        try await shell(["config", "user.email", "m@bough.local"], in: a)
        try "seed\n".write(to: a.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: a)
        try await shell(["commit", "-q", "-m", "seed"], in: a)
        try await shell(["push", "-q", "-u", "origin", "main"], in: a)
        // Clone b AFTER the seed push so main has upstream tracking from birth.
        try await shell(["-c", "init.defaultBranch=main", "clone", "-q", "origin.git", "b"], in: tempRoot)
        let b = tempRoot.appendingPathComponent("b")
        try "dirty\n".write(to: b.appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
        let junk = tempRoot.appendingPathComponent("junk-folder")
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        return (a, b, junk)
    }

    func testScanReportsValidDirtyAndInvalid() async throws {
        let (a, b, junk) = try await seed()
        let snapshots = await MultiRepoBatch.scan(paths: [a.path, b.path, junk.path],
                                                  gitBinary: gitBinary)
        XCTAssertEqual(snapshots.count, 3)
        let sa = try XCTUnwrap(snapshots.first { $0.path == a.path })
        XCTAssertEqual(sa.branch, "main")
        XCTAssertEqual(sa.dirtyCount, 0)
        XCTAssertTrue(sa.isValid)
        let sb = try XCTUnwrap(snapshots.first { $0.path == b.path })
        XCTAssertEqual(sb.dirtyCount, 1) // untracked dirty.txt
        let sj = try XCTUnwrap(snapshots.first { $0.path == junk.path })
        XCTAssertFalse(sj.isValid)
        XCTAssertNotNil(sj.message)
    }

    func testBatchFetchUpdatesBehind() async throws {
        let (a, b, junk) = try await seed()
        // a pushes new work; b falls behind.
        try "more\n".write(to: a.appendingPathComponent("more.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: a)
        try await shell(["commit", "-q", "-m", "more"], in: a)
        try await shell(["push", "-q", "origin", "main"], in: a)

        let outcomes = await MultiRepoBatch.fetchAll(paths: [b.path], gitBinary: gitBinary)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes[0].succeeded)

        let after = await MultiRepoBatch.scan(paths: [b.path], gitBinary: gitBinary)
        let sb = try XCTUnwrap(after.first)
        XCTAssertEqual(sb.behind, 1)
    }

    func testBatchPullFastForward() async throws {
        let (a, b, _) = try await seed()
        try "more\n".write(to: a.appendingPathComponent("more.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: a)
        try await shell(["commit", "-q", "-m", "more"], in: a)
        try await shell(["push", "-q", "origin", "main"], in: a)

        _ = await MultiRepoBatch.fetchAll(paths: [b.path], gitBinary: gitBinary)
        let outcomes = await MultiRepoBatch.pullAll(paths: [b.path], strategy: .merge, gitBinary: gitBinary)
        XCTAssertTrue(outcomes.allSatisfy(\.succeeded))

        let after = await MultiRepoBatch.scan(paths: [b.path], gitBinary: gitBinary)
        let sb = try XCTUnwrap(after.first)
        XCTAssertEqual(sb.behind, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: b.appendingPathComponent("more.txt").path))
    }
}
