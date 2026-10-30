import XCTest
@testable import Bough

/// Integration tests against real git binary on temp repositories.
final class GitRepositoryTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughGitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    /// Create an initialized repo with local identity configured.
    private func makeRepo() async throws -> GitRepository {
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: repoDir)
        _ = try await awaitRun(setup, ["init", "-q"])
        _ = try await awaitRun(setup, ["config", "user.name", "Bough Test"])
        _ = try await awaitRun(setup, ["config", "user.email", "test@bough.local"])
        return try GitRepository(root: repoDir, gitBinary: gitBinary)
    }

    private func awaitRun(_ executor: GitCommandExecutor, _ args: [String]) async throws -> GitResult {
        try await executor.run(GitCommand(args))
    }

    private func write(_ repo: GitRepository, _ relPath: String, _ content: String) throws {
        let url = repo.root.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Seed: initial commit so HEAD exists.
    private func seedInitialCommit(_ repo: GitRepository) async throws {
        try write(repo, "seed.txt", "seed")
        try await repo.stage(["seed.txt"])
        _ = try await repo.commit(message: "initial")
    }

    func testVersionProbe() async throws {
        let repo = try await makeRepo()
        let version = try await repo.version()
        XCTAssertTrue(version.contains("git"))
    }

    func testStatusLifecycle() async throws {
        let repo = try await makeRepo()
        try await seedInitialCommit(repo)

        // modify + create untracked
        try write(repo, "seed.txt", "changed")
        try write(repo, "new.md", "hello")

        let dirty = try await repo.status()
        XCTAssertEqual(dirty.unstaged.map(\.path), ["seed.txt"])
        XCTAssertEqual(dirty.untracked.map(\.path), ["new.md"])

        try await repo.stage(["seed.txt", "new.md"])
        let staged = try await repo.status()
        XCTAssertEqual(staged.staged.map(\.path).sorted(), ["new.md", "seed.txt"])
        XCTAssertTrue(staged.unstaged.isEmpty)
        XCTAssertTrue(staged.untracked.isEmpty)

        let sha = try await repo.commit(message: "second commit")
        XCTAssertFalse(sha.isEmpty)

        let clean = try await repo.status()
        XCTAssertFalse(clean.hasChanges)
        XCTAssertFalse(clean.isUnborn)
        XCTAssertNotNil(clean.branch)
    }

    func testUnstageReturnsFileToUntracked() async throws {
        let repo = try await makeRepo()
        try await seedInitialCommit(repo)
        try write(repo, "added.txt", "content")
        try await repo.stage(["added.txt"])
        let stagedCount = try await repo.status().staged.count
        XCTAssertEqual(stagedCount, 1)

        try await repo.unstage(["added.txt"])
        let status = try await repo.status()
        XCTAssertEqual(status.untracked.map(\.path), ["added.txt"])
        XCTAssertTrue(status.staged.isEmpty)
    }

    func testDiscardRevertsTrackedChanges() async throws {
        let repo = try await makeRepo()
        try await seedInitialCommit(repo)
        try write(repo, "seed.txt", "modified")
        try await repo.discard(["seed.txt"])
        let status = try await repo.status()
        XCTAssertFalse(status.hasChanges)
        let content = try String(contentsOf: repo.root.appendingPathComponent("seed.txt"), encoding: .utf8)
        XCTAssertEqual(content, "seed")
    }

    func testDiscardUntrackedDeletesFile() async throws {
        let repo = try await makeRepo()
        try await seedInitialCommit(repo)
        try write(repo, "junk.log", "noise")
        try await repo.discardUntracked(["junk.log"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.root.appendingPathComponent("junk.log").path))
    }

    func testAmendRewritesLastCommit() async throws {
        let repo = try await makeRepo()
        try await seedInitialCommit(repo)
        let before = try await repo.lastCommit()
        try await repo.stageAll()
        _ = try await repo.commit(message: "amended subject", amend: true)
        let after = try await repo.lastCommit()
        XCTAssertEqual(after?.subject, "amended subject")
        XCTAssertNotEqual(before?.sha, after?.sha)
    }

    func testIdentityAndLastCommitParsing() async throws {
        let repo = try await makeRepo()
        try await seedInitialCommit(repo)
        let identity = try await repo.identity()
        XCTAssertEqual(identity.name, "Bough Test")
        XCTAssertEqual(identity.email, "test@bough.local")

        let commit = try await repo.lastCommit()
        XCTAssertEqual(commit?.authorName, "Bough Test")
        XCTAssertEqual(commit?.subject, "initial")
        XCTAssertFalse(commit?.sha.isEmpty ?? true)
    }

    func testUnbornHeadHasNoLastCommit() async throws {
        let repo = try await makeRepo()
        let commit = try await repo.lastCommit()
        XCTAssertNil(commit)
        let status = try await repo.status()
        XCTAssertTrue(status.isUnborn)
    }
}
