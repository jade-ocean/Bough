import XCTest
@testable import Bough

/// Phase 5 integration: stash, tags, conflicts, interactive rebase (real git).
final class GitPhase5IntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var gitBinary: String!
    private var repo: GitRepository!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughP5Tests-\(UUID().uuidString)", isDirectory: true)
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

    /// Seed: bare origin + two clones with diverging edits on shared.txt.
    private func makeConflictingRepos() async throws -> (work: URL, other: URL) {
        try await shell(["init", "-q", "--bare", "-b", "main", "origin.git"], in: tempRoot)
        try await shell(["-c", "init.defaultBranch=main", "clone", "-q", "origin.git", "work"], in: tempRoot)
        let work = tempRoot.appendingPathComponent("work")
        let other = tempRoot.appendingPathComponent("other")
        try await shell(["config", "user.name", "P5 Test"], in: work)
        try await shell(["config", "user.email", "p5@bough.local"], in: work)
        try "base\n".write(to: work.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: work)
        try await shell(["commit", "-q", "-m", "base"], in: work)
        try await shell(["push", "-q", "-u", "origin", "main"], in: work)
        try await shell(["-c", "init.defaultBranch=main", "clone", "-q", "origin.git", "other"], in: tempRoot)
        try await shell(["config", "user.name", "P5 Test"], in: other)
        try await shell(["config", "user.email", "p5@bough.local"], in: other)
        return (work, other)
    }

    private func makeRepo() async throws -> GitRepository {
        let work = tempRoot.appendingPathComponent("work")
        return try GitRepository(root: work, gitBinary: gitBinary)
    }

    // MARK: - Stash

    func testStashLifecycle() async throws {
        _ = try await makeConflictingRepos()
        let repo = try await makeRepo()
        let initial = try await repo.stashList()
        XCTAssertTrue(initial.isEmpty)

        try "changed\n".write(to: repo.root.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repo.root.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        try await repo.stashPush(message: "wip", includeUntracked: true)
        var entries = try await repo.stashList()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].message.contains("wip"))

        // Worktree is clean after stash (incl. untracked)
        let clean = try await repo.status()
        XCTAssertFalse(clean.hasChanges)

        try await repo.stashApply(entries[0].selector)
        let applied = try await repo.status()
        XCTAssertTrue(applied.hasChanges)

        // Drop consumes the entry
        try await repo.stashDrop(entries[0].selector)
        entries = try await repo.stashList()
        XCTAssertTrue(entries.isEmpty)
    }

    func testStashPop() async throws {
        _ = try await makeConflictingRepos()
        let repo = try await makeRepo()
        try "x\n".write(to: repo.root.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try await repo.stashPush(message: nil, includeUntracked: false)
        let entries = try await repo.stashList()
        XCTAssertEqual(entries.count, 1)
        try await repo.stashPop(entries[0].selector)
        let afterPop = try await repo.stashList()
        let popStatus = try await repo.status()
        XCTAssertTrue(afterPop.isEmpty)
        XCTAssertTrue(popStatus.hasChanges)
    }

    // MARK: - Tags

    func testTagLifecycle() async throws {
        _ = try await makeConflictingRepos()
        let repo = try await makeRepo()

        try await repo.createTag("v1-light", target: nil)
        try await repo.createAnnotatedTag("v1-note", message: "release one", target: nil)

        let tags = try await repo.tagList()
        XCTAssertEqual(tags.map(\.name).sorted(), ["v1-light", "v1-note"])
        let annotated = tags.first { $0.name == "v1-note" }
        XCTAssertTrue(annotated?.isAnnotated == true)
        XCTAssertEqual(annotated?.message, "release one")
        let lightweight = tags.first { $0.name == "v1-light" }
        XCTAssertTrue(lightweight?.isAnnotated == false)

        try await repo.deleteTag("v1-light")
        let after = try await repo.tagList()
        XCTAssertEqual(after.map(\.name), ["v1-note"])
    }

    // MARK: - Conflict resolution

    func testConflictResolutionRoundTrip() async throws {
        let (work, other) = try await makeConflictingRepos()
        try "ours change\n".write(to: work.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: work)
        try await shell(["commit", "-q", "-m", "ours"], in: work)
        try await shell(["push", "-q", "origin", "main"], in: work)
        try "theirs change\n".write(to: other.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try await shell(["add", "."], in: other)
        try await shell(["commit", "-q", "-m", "theirs"], in: other)
        try await shell(["push", "-q", "-f", "origin", "main"], in: other)

        let repo = try await makeRepo()
        // Exit code 1 = automatic merge failed (the conflict we want).
        let puller = GitCommandExecutor(gitBinary: gitBinary, workingDirectory: work)
        _ = try await puller.run(GitCommand(["pull", "--no-rebase"]))
        let status = try await repo.status()
        XCTAssertEqual(status.unmerged.map(\.path), ["shared.txt"])

        // Parse the conflicted working file through the access provider path.
        let provider = DirectPathAccessProvider()
        let fileURL = work.appendingPathComponent("shared.txt")
        let data = try provider.dataForFile(at: fileURL)
        var parsed = ConflictParser.parse(String(decoding: data, as: UTF8.self))
        XCTAssertEqual(parsed.blocks.count, 1)

        // Choose ours, rebuild, write back, stage (block position varies).
        let conflictIndex = parsed.segments.firstIndex { segment in
            if case .conflict = segment { return true }
            return false
        } ?? 0
        parsed.segments[conflictIndex] = .conflict(ConflictParser.ConflictBlock(
            ours: parsed.blocks[0].ours, theirs: parsed.blocks[0].theirs,
            base: parsed.blocks[0].base, choice: .ours))
        let resolved = ConflictParser.resolvedText(parsed)
        XCTAssertEqual(resolved, "ours change\n")
        try provider.writeData(Data(resolved.utf8), to: fileURL)
        try await repo.runOrThrow(["add", "--", "shared.txt"])

        let after = try await repo.status()
        XCTAssertTrue(after.unmerged.isEmpty)
    }

    // MARK: - Interactive rebase (simplified)

    func testInteractiveRebaseDropAndReorder() async throws {
        _ = try await makeConflictingRepos()
        let repo = try await makeRepo()
        for (name, content) in [("a.txt", "a\n"), ("b.txt", "b\n"), ("c.txt", "c\n")] {
            try content.write(to: repo.root.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try await repo.runOrThrow(["add", "-A"])
            _ = try await repo.commit(message: "add \(name)")
        }
        let before = try await repo.commits(filter: HistoryFilter(allBranches: false))
        // before: [add c.txt, add b.txt, add a.txt, base]
        XCTAssertEqual(before[0].subject, "add c.txt")

        let base = before[3]
        var steps = try await repo.rebasePlan(base: base.sha)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps.map(\.subject), ["add a.txt", "add b.txt", "add c.txt"])

        // Drop b, reorder c before a.
        steps[1].dropped = true
        steps.swapAt(0, 2)
        try await repo.rebaseInteractive(base: base.sha, steps: steps)

        let after = try await repo.commits(filter: HistoryFilter(allBranches: false))
        let subjects = after.prefix(3).map(\.subject)
        // Replayed in todo order c-then-a, so newest-first log is a, c, base.
        XCTAssertEqual(subjects, ["add a.txt", "add c.txt", "base"])
    }
}
