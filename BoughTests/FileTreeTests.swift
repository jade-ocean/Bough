import XCTest
@testable import Bough

final class FileTreeTests: XCTestCase {

    // MARK: - Tree builder (pure)

    private func item(_ path: String, size: Int? = 10) -> GitRepository.TreeItem {
        GitRepository.TreeItem(mode: "100644", type: "blob", sha: "a", size: size, path: path)
    }

    func testBuildsNestedFoldersFoldersFirst() {
        let root = GitTreeParser.buildTree([
            item("b.txt"),
            item("src/deep/x.swift"),
            item("a.txt"),
            item("src/main.swift"),
        ])
        XCTAssertEqual(root.children?.map(\.name), ["src", "a.txt", "b.txt"])
        let src = root.children?.first { $0.name == "src" }
        XCTAssertEqual(src?.kind, .folder)
        XCTAssertEqual(src?.children?.map(\.name), ["deep", "main.swift"])
        XCTAssertEqual(src?.children?.first { $0.name == "deep" }?.children?.first?.path,
                       "src/deep/x.swift")
    }

    func testSizesCarriedToFiles() {
        let root = GitTreeParser.buildTree([item("big.bin", size: 4096)])
        let file = root.children?.first
        XCTAssertEqual(file?.size, 4096)
    }

    // MARK: - Integration (real git)

    private var tempRoot: URL!
    private var gitBinary: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughTreeTests-\(UUID().uuidString)", isDirectory: true)
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
        try await git(["config", "user.name", "Tree"])
        try await git(["config", "user.email", "t@bough.local"])
        try "readme\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "let x = 1\n".write(to: dir.appendingPathComponent("src/a.swift"), atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "c1"])
        return try GitRepository(root: dir, gitBinary: gitBinary)
    }

    func testLazyTreeDirTopLevelAndNested() async throws {
        let repo = try await makeRepo()
        // Top level: one folder + one file, folder NOT loaded yet.
        let root = try await repo.treeDir(ref: "HEAD", prefix: "")
        XCTAssertEqual(root.children?.map(\.name), ["src", "README.md"])
        let src = root.children?.first { $0.name == "src" }
        XCTAssertEqual(src?.kind, .folder)
        XCTAssertEqual(src?.childrenLoaded, false)
        XCTAssertNil(src?.children)

        // Load the folder on demand.
        let level = try await repo.treeDir(ref: "HEAD", prefix: "src")
        XCTAssertEqual(level.children?.map(\.name), ["a.swift"])
        XCTAssertEqual(level.children?.first?.childrenLoaded, true)
        XCTAssertEqual(level.children?.first?.size, Int("let x = 1\n".utf8.count))

        // Path-addressed update splices children into the root copy.
        let updated = GitTreeParser.updateChildren(of: "src", in: root, with: level)
        let updatedSrc = updated.children?.first { $0.name == "src" }
        XCTAssertEqual(updatedSrc?.childrenLoaded, true)
        XCTAssertEqual(updatedSrc?.children?.first?.path, "src/a.swift")
        // Original root untouched (value semantics).
        XCTAssertEqual(root.children?.first { $0.name == "src" }?.childrenLoaded, false)
    }

    func testListTreeAndBlobContentAtRef() async throws {
        let repo = try await makeRepo()
        let items = try await repo.listTree(ref: "HEAD")
        XCTAssertEqual(Set(items.map(\.path)), ["README.md", "src/a.swift"])
        let swift = try XCTUnwrap(items.first { $0.path == "src/a.swift" })
        XCTAssertEqual(swift.type, "blob")
        XCTAssertEqual(swift.size, Int("let x = 1\n".utf8.count))

        let tree = try await repo.fileTree(ref: "HEAD")
        XCTAssertEqual(tree.children?.map(\.name), ["src", "README.md"])
        let blob = try await repo.blobContent(ref: "HEAD", path: "src/a.swift")
        XCTAssertEqual(String(decoding: blob, as: UTF8.self), "let x = 1\n")
    }
}
