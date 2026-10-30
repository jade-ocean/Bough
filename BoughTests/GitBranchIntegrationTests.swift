import XCTest
@testable import Bough

/// Integration tests for branch/sync operations against a real bare remote.
final class GitBranchIntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughBrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        repo = nil
    }

    /// Seed a bare origin + a cloned work repo (branch "main", one commit, upstream set).
    private func makeRepo() async throws -> GitRepository {
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: tempRoot)
        func git(_ args: [String]) async throws {
            let result = try await setup.run(GitCommand(args))
            guard result.succeeded else {
                throw GitError.executionFailed(command: args.joined(separator: " "),
                                               exitCode: result.exitCode, stderr: result.stderr)
            }
        }
        try await git(["init", "-q", "--bare", "-b", "main", "origin.git"])
        try await git(["-c", "init.defaultBranch=main", "clone", "-q", "origin.git", "work"])
        let work = tempRoot.appendingPathComponent("work")
        try await git(["-C", work.path, "config", "user.name", "Br Test"])
        try await git(["-C", work.path, "config", "user.email", "br@bough.local"])
        try "one\n".write(to: work.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try await git(["-C", work.path, "add", "."])
        try await git(["-C", work.path, "commit", "-q", "-m", "c1"])
        try await git(["-C", work.path, "push", "-q", "-u", "origin", "main"])
        return try GitRepository(root: work, gitBinary: gitBinary)
    }

    private func write(_ repo: GitRepository, _ path: String, _ content: String) throws {
        try content.write(to: repo.root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func commit(_ repo: GitRepository, _ message: String) async throws {
        try await repo.runOrThrow(["add", "-A"])
        _ = try await repo.commit(message: message)
    }

    func testBranchListAndCurrentFlag() async throws {
        let repo = try await makeRepo()
        try await repo.createBranch("feat")
        let result = try await repo.branches()
        XCTAssertEqual(result.local.map(\.name).sorted(), ["feat", "main"])
        XCTAssertEqual(result.local.filter(\.isCurrent).map(\.name), ["main"])
        XCTAssertEqual(result.local.first { $0.name == "feat" }?.sha,
                       result.local.first { $0.name == "main" }?.sha)
    }

    func testAheadBehindTracking() async throws {
        let repo = try await makeRepo()
        try write(repo, "one.txt", "changed\n")
        try await commit(repo, "local ahead")
        let branches = try await repo.branches()
        let main = try XCTUnwrap(branches.local.first { $0.name == "main" })
        XCTAssertEqual(main.upstream, "origin/main")
        XCTAssertEqual(main.ahead, 1)
        XCTAssertEqual(main.behind, 0)

        // Simulate a remote commit: second clone pushes; after fetch we are behind.
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: tempRoot)
        try await setup.run(GitCommand(["-c", "init.defaultBranch=main", "clone", "-q", "origin.git", "other"]))
        let other = tempRoot.appendingPathComponent("other")
        try "remote\n".write(to: other.appendingPathComponent("remote.txt"), atomically: true, encoding: .utf8)
        _ = try await setup.run(GitCommand(["-C", other.path, "config", "user.name", "Other"]))
        _ = try await setup.run(GitCommand(["-C", other.path, "config", "user.email", "o@bough.local"]))
        _ = try await setup.run(GitCommand(["-C", other.path, "add", "."]))
        _ = try await setup.run(GitCommand(["-C", other.path, "commit", "-q", "-m", "remote work"]))
        _ = try await setup.run(GitCommand(["-C", other.path, "push", "-q", "origin", "main"]))

        try await repo.fetch()
        let afterFetch = try await repo.branches()
        let fetched = try XCTUnwrap(afterFetch.local.first { $0.name == "main" })
        XCTAssertEqual(fetched.ahead, 1)
        XCTAssertEqual(fetched.behind, 1)
    }

    func testCreateRenameDeleteRoundtrip() async throws {
        let repo = try await makeRepo()
        try await repo.createBranch("topic", startPoint: "main", checkout: true)
        var local = try await repo.branches().local
        XCTAssertEqual(local.filter(\.isCurrent).map(\.name), ["topic"])

        try await repo.renameBranch("topic", to: "renamed")
        local = try await repo.branches().local
        XCTAssertTrue(local.contains { $0.name == "renamed" })
        XCTAssertFalse(local.contains { $0.name == "topic" })

        // Current branch cannot be deleted - switch away first.
        try await repo.checkoutBranch("main")
        try await repo.deleteBranch("renamed", force: false)
        local = try await repo.branches().local
        XCTAssertFalse(local.contains { $0.name == "renamed" })
    }

    func testDeleteCurrentBranchFails() async throws {
        let repo = try await makeRepo()
        do {
            try await repo.deleteBranch("main", force: false)
            XCTFail("deleting the current branch must fail")
        } catch {
            // expected
        }
    }

    func testMergeAndRebase() async throws {
        let repo = try await makeRepo()
        try await repo.createBranch("feat", checkout: true)
        try write(repo, "feat.txt", "feat\n")
        try await commit(repo, "f1")
        try await repo.checkoutBranch("main")
        try write(repo, "main.txt", "main\n")
        try await commit(repo, "m2")

        // Rebase feat onto main: feat now contains main's commit first.
        try await repo.checkoutBranch("feat")
        try await repo.rebase(onto: "main")
        let featLog = try await repo.commits(filter: HistoryFilter(allBranches: false))
        XCTAssertTrue(featLog.contains { $0.subject == "m2" })

        // Merge feat into main (fast-forward allowed).
        try await repo.checkoutBranch("main")
        let headBefore = try await repo.headSha()
        try await repo.merge("feat")
        let headAfter = try await repo.headSha()
        XCTAssertNotEqual(headBefore, headAfter)
    }

    func testPullStrategiesAndPush() async throws {
        let repo = try await makeRepo()
        try write(repo, "local.txt", "local\n")
        try await commit(repo, "local commit")
        try await repo.push()
        let pushed = try await repo.remotes()
        XCTAssertEqual(pushed.first?.name, "origin")

        try await repo.pull(strategy: .merge)
        try await repo.pull(strategy: .rebase)
        let status = try await repo.status()
        XCTAssertTrue(status.unmerged.isEmpty)
    }

    func testRemoteManagement() async throws {
        let repo = try await makeRepo()
        try await repo.addRemote(name: "mirror", url: "\(tempRoot.path)/origin.git")
        let remotes = try await repo.remotes()
        XCTAssertEqual(remotes.map(\.name), ["mirror", "origin"])
        try await repo.removeRemote(name: "mirror")
        let after = try await repo.remotes()
        XCTAssertEqual(after.map(\.name), ["origin"])
    }

    func testBranchNameValidation() async {
        let repo = try? await makeRepo()
        guard let repo else { return }
        let bad = await repo.isBranchNameValid("bad name")
        let dots = await repo.isBranchNameValid("a..b")
        let good = await repo.isBranchNameValid("feature/login-2")
        XCTAssertFalse(bad)
        XCTAssertFalse(dots)
        XCTAssertTrue(good)
    }
}
