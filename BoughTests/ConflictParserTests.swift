import XCTest
@testable import Bough

final class ConflictParserTests: XCTestCase {

    private let standardConflict = """
    header line
    <<<<<<< HEAD
    ours line
    =======
    theirs line
    >>>>>>> feature
    footer line
    """

    private let diff3Conflict = """
    a
    <<<<<<< HEAD
    ours
    ||||||| merged common ancestors
    base
    =======
    theirs
    >>>>>>> other
    b
    """

    func testParsesStandardMarkers() {
        let result = ConflictParser.parse(standardConflict)
        XCTAssertEqual(result.blocks.count, 1)
        let block = result.blocks[0]
        XCTAssertEqual(block.ours, ["ours line"])
        XCTAssertEqual(block.theirs, ["theirs line"])
        XCTAssertTrue(block.base.isEmpty)
        XCTAssertEqual(result.unresolvedCount, 1)
        XCTAssertFalse(result.allResolved)
    }

    func testParsesDiff3Base() {
        let result = ConflictParser.parse(diff3Conflict)
        let block = result.blocks[0]
        XCTAssertEqual(block.base, ["base"])
        XCTAssertEqual(block.ours, ["ours"])
        XCTAssertEqual(block.theirs, ["theirs"])
    }

    func testChoiceApplicationAndRebuild() {
        var result = ConflictParser.parse(standardConflict)
        // flip through all three choices and rebuild
        result.segments[1] = .conflict(ConflictParser.ConflictBlock(
            ours: result.blocks[0].ours, theirs: result.blocks[0].theirs,
            base: [], choice: .ours))
        var text = ConflictParser.resolvedText(result)
        XCTAssertEqual(text, "header line\nours line\nfooter line\n")

        result.segments[1] = .conflict(ConflictParser.ConflictBlock(
            ours: result.blocks[0].ours, theirs: result.blocks[0].theirs,
            base: [], choice: .theirs))
        text = ConflictParser.resolvedText(result)
        XCTAssertEqual(text, "header line\ntheirs line\nfooter line\n")

        result.segments[1] = .conflict(ConflictParser.ConflictBlock(
            ours: result.blocks[0].ours, theirs: result.blocks[0].theirs,
            base: [], choice: .both))
        text = ConflictParser.resolvedText(result)
        XCTAssertEqual(text, "header line\nours line\ntheirs line\nfooter line\n")
    }

    func testMultipleBlocksAndUnresolvedCount() {
        let text = """
        <<<<<<< HEAD
        o1
        =======
        t1
        >>>>>>> x
        middle
        <<<<<<< HEAD
        o2
        =======
        t2
        >>>>>>> x
        """
        let result = ConflictParser.parse(text)
        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.unresolvedCount, 2)
        var updated = result
        updated.segments[0] = .conflict(ConflictParser.ConflictBlock(
            ours: ["o1"], theirs: ["t1"], base: [], choice: .both))
        XCTAssertEqual(updated.unresolvedCount, 1)
    }

    func testEmptyContentYieldsEmpty() {
        let result = ConflictParser.parse("")
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertTrue(ConflictParser.resolvedText(result).isEmpty)
    }
}
