import XCTest
@testable import Bough

/// Phase 6 integration: git grep + commit search (real git).
final class GitSearchIntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughSearchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        gitBinary = try GitLocator.locate()
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        repo = nil
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
        try await git(["config", "user.name", "Search Test"])
        try await git(["config", "user.email", "s@bough.local"])
        try "let answer = 42\n".write(to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "func run() {}\n".write(to: dir.appendingPathComponent("b.go"), atomically: true, encoding: .utf8)
        try "answer twice\n".write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try await git(["add", "."])
        try await git(["commit", "-q", "-m", "initial answer"])
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "let answer2 = 43\n".write(to: dir.appendingPathComponent("sub/c.swift"), atomically: true, encoding: .utf8)
        try await git(["add", "."])
        try await git(["commit", "-q", "-m", "second answer commit"])
        return try GitRepository(root: dir, gitBinary: gitBinary)
    }

    func testGrepFixedString() async throws {
        let repo = try await makeRepo()
        let results = try await repo.grep("answer", options: GrepOptions())
        // a.swift, notes.md, sub/c.swift (tracked files only)
        XCTAssertEqual(results.map(\.file).sorted(), ["a.swift", "notes.md", "sub/c.swift"])
        XCTAssertTrue(results.allSatisfy { $0.line > 0 && $0.column > 0 })
    }

    func testGrepCaseSensitivityAndPathFilter() async throws {
        let repo = try await makeRepo()
        let sensitive = try await repo.grep(
            "Answer", options: GrepOptions(caseSensitive: true, useRegex: false, pathPrefix: ""))
        XCTAssertTrue(sensitive.isEmpty)

        let filtered = try await repo.grep(
            "answer", options: GrepOptions(caseSensitive: false, useRegex: false, pathPrefix: "sub"))
        XCTAssertEqual(filtered.map(\.file), ["sub/c.swift"])
    }

    func testGrepRegexAndNoMatch() async throws {
        let repo = try await makeRepo()
        let regex = try await repo.grep("answer[0-9]", options: GrepOptions(caseSensitive: false, useRegex: true, pathPrefix: ""))
        XCTAssertEqual(regex.map(\.file), ["sub/c.swift"])

        let none = try await repo.grep("definitely-not-present", options: GrepOptions())
        XCTAssertTrue(none.isEmpty)
    }

    func testGrepParse() {
        let parsed = GitRepository.parseGrep(
            "src/a.swift:12:5:let x = 1\nb.md:1:1:hello\n", limit: 10)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].file, "src/a.swift")
        XCTAssertEqual(parsed[0].line, 12)
        XCTAssertEqual(parsed[0].column, 5)
        XCTAssertEqual(parsed[0].text, "let x = 1")
        XCTAssertEqual(parsed[1].text, "hello")
    }

    func testCommitSearchAcrossBranches() async throws {
        let repo = try await makeRepo()
        try await repo.createBranch("feature", checkout: true)
        try "x\n".write(to: repo.root.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try await repo.runOrThrow(["add", "-A"])
        _ = try await repo.commit(message: "feature answer on branch")

        let hits = try await repo.searchCommits("answer")
        // both branches: initial + second + feature commit
        XCTAssertGreaterThanOrEqual(hits.count, 3)
        XCTAssertTrue(hits.contains { $0.subject == "feature answer on branch" })
    }
}
