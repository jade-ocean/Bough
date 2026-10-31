import XCTest
@testable import Bough

@MainActor
final class DetailModelTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughDetailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    private func makeRepo() async throws -> WorkspaceModel {
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
        try await git(["config", "user.name", "Det"])
        try await git(["config", "user.email", "d@bough.local"])
        try "one\n".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "seed one"])
        try "two\n".write(to: dir.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-q", "-m", "seed two"])
        let repo = try GitRepository(root: dir, gitBinary: gitBinary)
        return WorkspaceModel(repository: repo)
    }

    func testSelectCommitPopulatesHeaderFilesAndDiff() async throws {
        let model = try await makeRepo()
        let commits = try await model.repository.commits(filter: HistoryFilter(allBranches: false))
        let seedTwo = try XCTUnwrap(commits.first { $0.subject == "seed two" })

        model.detail.select(.commit(seedTwo))

        // Async load: poll for header + files + rendered diff.
        for _ in 0..<30 {
            if model.detail.headerCommit != nil, !model.detail.files.isEmpty,
               model.detail.rendered != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(model.detail.headerCommit?.subject, "seed two")
        XCTAssertEqual(model.detail.files.map(\.path), ["two.txt"])
        XCTAssertNotNil(model.detail.rendered?.diff, "应渲染出 diff")
    }

    func testSelectWithPendingFilePicksThatFile() async throws {
        let model = try await makeRepo()
        let commits = try await model.repository.commits(filter: HistoryFilter(allBranches: false))
        let seedTwo = try XCTUnwrap(commits.first { $0.subject == "seed two" })

        model.detail.select(commit: seedTwo, filePath: "two.txt")
        for _ in 0..<30 {
            if model.detail.selectedFile != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(model.detail.selectedFile?.path, "two.txt")
    }
}
