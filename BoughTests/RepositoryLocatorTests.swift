import XCTest
@testable import Bough

final class RepositoryLocatorTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughLocatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    // MARK: - Helpers

    /// Fabricate a minimal valid gitdir (HEAD + objects/ + refs/).
    private func makeGitDir(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("objects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try "ref: refs/heads/main".write(to: url.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
    }

    /// Fabricate a repo whose .git is a directory.
    private func makeRepo(gitAsDirectory: Bool = true) throws -> URL {
        let root = tempRoot.appendingPathComponent("repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if gitAsDirectory {
            try makeGitDir(at: root.appendingPathComponent(".git"))
        } else {
            let gitdir = tempRoot.appendingPathComponent("gitdir-\(UUID().uuidString)", isDirectory: true)
            try makeGitDir(at: gitdir)
            try "gitdir: \(gitdir.path)".write(to: root.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        }
        return root
    }

    // MARK: - locateWorkTreeRoot

    func testLocatesRootWhenSelectingRootDirectly() throws {
        let root = try makeRepo()
        XCTAssertEqual(try RepositoryLocator.locateWorkTreeRoot(at: root.path), root)
    }

    func testWalksUpFromSubdirectory() throws {
        let root = try makeRepo()
        let deep = root.appendingPathComponent("src/feature/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        XCTAssertEqual(try RepositoryLocator.locateWorkTreeRoot(at: root.path), root)
    }

    func testResolvesWorktreeGitFileWithAbsolutePath() throws {
        let root = try makeRepo(gitAsDirectory: false)
        let gitdir = try RepositoryLocator.resolveGitDirectory(inWorkTree: root)
        XCTAssertTrue(gitdir.path.hasPrefix(tempRoot.path))
    }

    func testResolvesRelativeGitDirReference() throws {
        let root = tempRoot.appendingPathComponent("wt-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let gitdir = tempRoot.appendingPathComponent("shared-gitdir", isDirectory: true)
        try makeGitDir(at: gitdir)
        try "gitdir: ../shared-gitdir".write(to: root.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let resolved = try RepositoryLocator.resolveGitDirectory(inWorkTree: root)
    }

    func testMalformedGitFileThrows() throws {
        let root = tempRoot.appendingPathComponent("bad-git-file", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "hello world".write(to: root.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try RepositoryLocator.resolveGitDirectory(inWorkTree: root))
    }

    func testInvalidGitDirectoryThrows() throws {
        let root = tempRoot.appendingPathComponent("invalid-gitdir", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try RepositoryLocator.resolveGitDirectory(inWorkTree: root))
    }

    func testNotARepositoryThrows() throws {
        let empty = tempRoot.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try RepositoryLocator.locateWorkTreeRoot(at: empty.path))
    }

    func testPathDoesNotExistThrows() {
        XCTAssertThrowsError(try RepositoryLocator.locateWorkTreeRoot(at: "/nonexistent/bough/path"))
    }
}
