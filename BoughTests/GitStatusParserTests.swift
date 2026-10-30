import XCTest
@testable import Bough

final class GitStatusParserTests: XCTestCase {

    private func parse(_ records: [String]) throws -> GitStatus {
        let data = Data(records.joined(separator: "\0").utf8) + Data([0])
        return try GitStatusParser.parse(data)
    }

    func testCleanRepository() throws {
        let status = try parse([
            "# branch.oid ab12",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +1 -2",
        ])
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertEqual(status.ahead, 1)
        XCTAssertEqual(status.behind, 2)
        XCTAssertTrue(status.entries.isEmpty)
        XCTAssertFalse(status.isUnborn)
    }

    func testModifiedAndStagedSides() throws {
        let status = try parse([
            "# branch.head main",
            "1 MM N... 100644 100644 100644 abc123 def456 hello.txt",
        ])
        let entry = try XCTUnwrap(status.entries.first)
        XCTAssertEqual(entry.path, "hello.txt")
        XCTAssertEqual(entry.indexStatus, .modified)
        XCTAssertEqual(entry.worktreeStatus, .modified)
    }

    func testStagedNewFileAndUntracked() throws {
        let status = try parse([
            "# branch.head main",
            "1 A. N... 000000 100644 000000 000000 e69de new.swift",
            "? notes.md",
        ])
        XCTAssertEqual(status.staged.map(\.path), ["new.swift"])
        XCTAssertEqual(status.untracked.map(\.path), ["notes.md"])
        XCTAssertTrue(status.staged[0].worktreeStatus == nil)
        XCTAssertFalse(status.hasChanges == false)
    }

    func testRenameRecord() throws {
        // "2" record: <tag> <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path> NUL <origPath>
        // path = new name, origPath = old name.
        let payload = "2 R. N... 100644 100644 100644 abc abc R100 new-name.txt\0old.txt\0"
        let data = Data("# branch.head main\0".utf8) + Data(payload.utf8)
        let status = try GitStatusParser.parse(data)
        let entry = try XCTUnwrap(status.entries.first)
        XCTAssertEqual(entry.path, "new-name.txt")
        XCTAssertEqual(entry.indexStatus, .renamed)
        XCTAssertEqual(entry.originalPath, "old.txt")
    }

    func testConflictRecord() throws {
        let status = try parse([
            "# branch.head main",
            "u UU N... 100644 100644 100644 100644 abc def ghi conflicted.txt",
        ])
        let entry = try XCTUnwrap(status.entries.first)
        XCTAssertEqual(entry.path, "conflicted.txt")
        XCTAssertEqual(entry.worktreeStatus, .conflicted)
        XCTAssertTrue(status.hasChanges)
    }

    func testUnbornBranch() throws {
        let status = try parse(["# branch.oid (initial)", "# branch.head master"])
        XCTAssertTrue(status.isUnborn)
        XCTAssertEqual(status.branch, "master")
    }
}
