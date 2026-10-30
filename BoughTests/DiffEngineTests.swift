import XCTest
@testable import Bough

final class DiffEngineTests: XCTestCase {

    private var diffText: String {
        [
            "diff --git a/a.txt b/a.txt",
            "index 111..222 100644",
            "--- a/a.txt",
            "+++ b/a.txt",
            "@@ -1,4 +1,5 @@ struct Foo {",
            " line1",
            "-old2",
            "+new2",
            "+extra",
            " line3",
            "-gone",
            "\\ No newline at end of file",
        ].joined(separator: "\n")
    }

    func testParsesHunksAndLineNumbers() throws {
        let files = DiffParser.parse(diffText)
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.path, "a.txt")
        XCTAssertEqual(file.hunks.count, 1)
        let hunk = try XCTUnwrap(file.hunks.first)
        XCTAssertEqual(hunk.oldStart, 1)
        XCTAssertEqual(hunk.newStart, 1)
        XCTAssertEqual(hunk.section, "struct Foo {")

        let kinds = hunk.lines.map(\.kind)
        XCTAssertEqual(kinds, [.context, .deleted, .added, .added, .context, .deleted])
        XCTAssertEqual(hunk.lines[1].text, "old2")
        XCTAssertEqual(hunk.lines[1].oldNumber, 2)
        XCTAssertEqual(hunk.lines[2].newNumber, 2)
        XCTAssertEqual(hunk.lines[3].newNumber, 3)
        XCTAssertEqual(hunk.lines[4].text, "line3")
        XCTAssertEqual(hunk.lines[4].oldNumber, 3)
        XCTAssertEqual(hunk.lines[5].text, "gone")
    }

    func testSideBySidePairing() throws {
        let files = DiffParser.parse(diffText)
        let hunk = try XCTUnwrap(files.first?.hunks.first)
        let pairs = DiffParser.sideBySidePairs(hunk)
        // context, (old2|new2), (nil|extra), (line3|line3), (gone|nil)
        XCTAssertEqual(pairs.count, 5)
        XCTAssertNil(pairs[2].left)
        XCTAssertEqual(pairs[2].right?.text, "extra")
        XCTAssertNil(pairs[4].right)
        XCTAssertEqual(pairs[4].left?.text, "gone")
        XCTAssertEqual(pairs[0].left?.text, "line1")
        XCTAssertEqual(pairs[0].right?.text, "line1")
    }

    func testBinaryFileMarker() {
        let text = """
        diff --git a/img.png b/img.png
        index 111..222 100644
        Binary files a/img.png and b/img.png differ
        """
        let files = DiffParser.parse(text)
        XCTAssertEqual(files.first?.isBinary, true)
        XCTAssertEqual(files.first?.path, "img.png")
    }

    func testMultiFileSplit() {
        let text = """
        diff --git a/one.txt b/one.txt
        @@ -1 +1 @@
        -x
        +y
        diff --git a/two.txt b/two.txt
        @@ -1 +1 @@
        -p
        +q
        """
        let files = DiffParser.parse(text)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].path, "one.txt")
        XCTAssertEqual(files[1].path, "two.txt")
        XCTAssertEqual(files[1].hunks.first?.lines.map(\.text), ["p", "q"])
    }

    func testHunkHeaderSingleLineCounts() {
        let header = DiffParser.parseHunkHeader("@@ -10 +10,2 @@ foo")
        XCTAssertEqual(header?.oldStart, 10)
        XCTAssertEqual(header?.oldCount, 1)
        XCTAssertEqual(header?.newStart, 10)
        XCTAssertEqual(header?.newCount, 2)
        XCTAssertEqual(header?.section, "foo")
    }
}
