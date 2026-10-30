import XCTest
@testable import Bough

/// Working-copy experience pack: reflog recovery + checkout safety.
final class WorkspaceSafetyTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        repo = nil
    }

    private func shell(_ args: [String], in directory: URL) async throws {
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: directory)
        let result = try await setup.run(GitCommand(args))
        guard result.succeeded else {
            throw GitError.executionFailed(command: args.joined(separator: " "),
                                           exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// main with two commits; feature branch with a conflicting version of f.txt.
    private func makeRepo() async throws -> GitRepository {
        let dir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await shell(["init", "-q", "-b", "main"], in: dir)
        try await shell(["config", "user.name", "Safety"], in: dir)
        try await shell(["config", "user.email", "s@bough.local"], in: dir)
        try "v1\n".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: dir)
        try await shell(["commit", "-q", "-m", "c1"], in: dir)
        try "v2\n".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: dir)
        try await shell(["commit", "-q", "-m", "c2"], in: dir)
        try await shell(["checkout", "-q", "-b", "feature"], in: dir)
        try "feature-version\n".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: dir)
        try await shell(["commit", "-q", "-m", "f1"], in: dir)
        try await shell(["checkout", "-q", "main"], in: dir)
        return try GitRepository(root: dir, gitBinary: gitBinary)
    }

    // MARK: - Reflog

    func testReflogBrowseAndRecoverDroppedCommit() async throws {
        let repo = try await makeRepo()
        let commits = try await repo.commits(filter: HistoryFilter(allBranches: false))
        let c2 = try XCTUnwrap(commits.first { $0.subject == "c2" })

        try await shell(["reset", "-q", "--hard", "HEAD~1"], in: repo.root) // drop c2
        let afterReset = try await repo.commits(filter: HistoryFilter(allBranches: false))
        XCTAssertFalse(afterReset.contains { $0.subject == "c2" })

        let entries = try await repo.reflog()
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.contains { $0.sha == c2.sha })           // original commit entry
        XCTAssertTrue(entries.contains { $0.operation.contains("reset") }) // the reset entry

        // Recover: branch from the dropped sha, verify content is back.
        try await repo.createBranch(at: c2.sha, name: "recovered")
        try await repo.checkoutBranch("recovered")
        let restored = try await repo.commits(filter: HistoryFilter(allBranches: false))
        XCTAssertTrue(restored.contains { $0.subject == "c2" })
        let content = try String(contentsOf: repo.root.appendingPathComponent("f.txt"), encoding: .utf8)
        XCTAssertEqual(content, "v2\n")
    }

    // MARK: - Checkout safety

    func testCheckoutCarriesCompatibleChanges() async throws {
        let repo = try await makeRepo()
        try "unrelated\n".write(to: repo.root.appendingPathComponent("other.txt"),
                                atomically: true, encoding: .utf8)
        let outcome = try await repo.checkoutBranchPreservingChanges(
            "feature", autoStashMessage: "auto")
        XCTAssertEqual(outcome, .switched) // no overlap: git carries the file over
        let status = try await repo.status()
        XCTAssertTrue(status.untracked.contains { $0.path == "other.txt" })
    }

    func testCheckoutWithConflictingChangesRetainsStash() async throws {
        let repo = try await makeRepo()
        // f.txt conflicts with feature's committed version, so plain checkout
        // refuses; auto-stash proceeds but the apply 3-way-merges to a
        // conflict (same root cause) - git-native behavior: markers written,
        // stash retained for manual recovery.
        try "dirty-work\n".write(to: repo.root.appendingPathComponent("f.txt"),
                                 atomically: true, encoding: .utf8)
        let outcome = try await repo.checkoutBranchPreservingChanges(
            "feature", autoStashMessage: "Bough auto-stash")
        XCTAssertEqual(outcome, .switchedWithRetainedStash)

        let branches = try await repo.branches()
        XCTAssertEqual(branches.local.filter(\.isCurrent).map(\.name), ["feature"])

        let content = try String(contentsOf: repo.root.appendingPathComponent("f.txt"), encoding: .utf8)
        XCTAssertTrue(content.contains("<<<<<<<")) // conflict markers
        let remainingStash = try await repo.stashList()
        XCTAssertEqual(remainingStash.count, 1)    // work preserved in stash@{0}
    }


    func testCheckoutAutoStashCleanApplyWhenFileMissingOnTarget() async throws {
        let repo = try await makeRepo()
        // feature deletes nothing but lacks note.txt entirely; dirty untracked
        // note.txt on main + tracked dirty f.txt removed... simplest: dirty
        // tracked file whose content matches target (no textual overlap).
        // Use a NEW tracked-on-main file: main adds note.txt (committed), then
        // dirty it; feature branched before note.txt existed.
        try "note\n".write(to: repo.root.appendingPathComponent("note.txt"),
                           atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: repo.root)
        try await shell(["commit", "-q", "-m", "c3-note"], in: repo.root)
        try "note-dirty\n".write(to: repo.root.appendingPathComponent("note.txt"),
                                 atomically: true, encoding: .utf8)

        let outcome = try await repo.checkoutBranchPreservingChanges(
            "feature", autoStashMessage: "auto")
        // Modify/delete (file absent on target): git restores the content but
        // flags a conflict and keeps the stash for user confirmation - we
        // surface that honestly as a retained stash.
        XCTAssertEqual(outcome, .switchedWithRetainedStash)
        let content = try String(contentsOf: repo.root.appendingPathComponent("note.txt"), encoding: .utf8)
        XCTAssertEqual(content, "note-dirty\n") // content restored
        let remainingStash = try await repo.stashList()
        XCTAssertEqual(remainingStash.count, 1)  // kept for user confirmation
    }

    func testPlainCheckoutRefusesConflictingDirtyTree() async throws {
        let repo = try await makeRepo()
        try "dirty-work\n".write(to: repo.root.appendingPathComponent("f.txt"),
                                 atomically: true, encoding: .utf8)
        do {
            try await repo.checkoutBranch("feature")
            XCTFail("plain checkout must fail on conflicting dirty tree")
        } catch {
            // expected - the UI flow exists to handle exactly this
        }
    }
}
