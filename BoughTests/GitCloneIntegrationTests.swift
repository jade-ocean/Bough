import XCTest
@testable import Bough

final class GitCloneIntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughCloneTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    /// Seed a local "remote" repo with one commit; returns its path.
    private func makeRemote() async throws -> String {
        let remote = tempRoot.appendingPathComponent("remote-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let setup = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: remote)
        func run(_ args: [String]) async throws -> GitResult {
            try await setup.run(GitCommand(args))
        }
        _ = try await run(["init", "-q", "-b", "main"])
        try "hello\n".write(to: remote.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try await run(["add", "."])
        _ = try await run(["-c", "user.name=Seed", "-c", "user.email=s@bough.local",
                           "commit", "-q", "-m", "seed"])
        return remote.path
    }

    func testCloneFromLocalPath() async throws {
        let remote = try await makeRemote()
        let parent = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let dest = try await CloneService.clone(url: remote, folderName: "my-clone",
                                                into: parent, gitBinary: gitBinary)
        XCTAssertEqual(dest.lastPathComponent, "my-clone")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("README.md").path))
        let repo = try GitRepository(root: dest, gitBinary: gitBinary)
        let status = try await repo.status()
        XCTAssertFalse(status.hasChanges)
        XCTAssertEqual(status.branch, "main")
    }

    func testCloneIntoExistingFolderFails() async throws {
        let remote = try await makeRemote()
        let parent = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent("taken"), withIntermediateDirectories: true)

        do {
            _ = try await CloneService.clone(url: remote, folderName: "taken",
                                             into: parent, gitBinary: gitBinary)
            XCTFail("clone into existing folder must fail")
        } catch {
            // expected
        }
    }

    func testSuggestedFolderName() {
        XCTAssertEqual(CloneService.suggestedFolderName(
            for: "https://github.com/user/Bough.git"), "Bough")
        XCTAssertEqual(CloneService.suggestedFolderName(
            for: "git@gitlab.example.com:group/sub/repo.git"), "repo")
        XCTAssertEqual(CloneService.suggestedFolderName(
            for: "https://gitlab.example.com:8443/a/b/"), "b")
    }

    func testSourceValidation() {
        XCTAssertFalse(CloneService.isValidSource(""))
        XCTAssertFalse(CloneService.isValidSource("-upload-pack=x")) // option injection
        XCTAssertTrue(CloneService.isValidSource("https://github.com/u/r.git"))
        XCTAssertTrue(CloneService.isValidSource("git@host:group/repo.git"))
        XCTAssertTrue(CloneService.isValidSource("ssh://git@host:2222/group/repo.git"))
        XCTAssertTrue(CloneService.isValidSource("/Users/me/code/repo"))
    }
}
