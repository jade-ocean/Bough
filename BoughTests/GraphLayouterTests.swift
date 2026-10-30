import XCTest
@testable import Bough

final class GraphLayouterTests: XCTestCase {

    private func commit(_ sha: String, parents: [String]) -> Commit {
        Commit(sha: sha, shortSha: String(sha.prefix(7)),
               authorName: "A", authorEmail: "a@b.c", timestamp: 0,
               subject: sha, body: "", parents: parents)
    }

    func testLinearHistorySingleLane() {
        let rows = GraphLayouter.layout([
            commit("c3", parents: ["c2"]),
            commit("c2", parents: ["c1"]),
            commit("c1", parents: []),
        ])
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.lane == 0 })
        XCTAssertTrue(rows.allSatisfy { $0.laneCount == 1 })
        XCTAssertTrue(rows.allSatisfy { $0.passThrough.isEmpty })
    }

    func testBranchCreatesSecondLane() {
        // c2 (main) --- d2 (feature)
        //   |
        // c1
        let rows = GraphLayouter.layout([
            commit("c2", parents: ["c1"]),
            commit("d2", parents: ["c1"]),
            commit("c1", parents: []),
        ])
        XCTAssertEqual(rows[0].lane, 0)
        XCTAssertEqual(rows[1].lane, 1) // feature commit lands in a new lane
        XCTAssertEqual(rows[1].passThrough, [0]) // main's line passes through
        XCTAssertEqual(rows[2].laneCount, 1) // lanes collapsed back to one
    }

    func testMergeCurvesIntoExistingLane() {
        // m1 has parents [c1, d1]: c1 straight, d1 curves from lane 1.
        let rows = GraphLayouter.layout([
            commit("m1", parents: ["c1", "d1"]),
            commit("d1", parents: ["c1"]),
            commit("c1", parents: []),
        ])
        // m1: first parent straight (lane 0); second parent d1 gets lane 1.
        XCTAssertEqual(rows[0].edges.count, 2)
        XCTAssertTrue(rows[0].edges.contains(GraphEdge(fromLane: 0, toLane: 0)))
        XCTAssertTrue(rows[0].edges.contains(GraphEdge(fromLane: 0, toLane: 1)))
        // d1 row: its node sits on lane 1 (expected there), straight to c1.
        XCTAssertEqual(rows[1].lane, 1)
        XCTAssertEqual(rows[2].lane, 0)
    }

    func testMergeIntoAlreadyWaitingLane() {
        // Order: m1 (parents c1, x1) then c1 arrives while x1 waits on lane 1.
        let rows = GraphLayouter.layout([
            commit("m1", parents: ["c1", "x1"]),
            commit("c1", parents: ["x1"]),
            commit("x1", parents: []),
        ])
        // c1 row: lane 0 straight; x1 lane (1) passes through.
        XCTAssertEqual(rows[1].lane, 0)
        XCTAssertTrue(rows[1].passThrough.contains(1))
        // Edge from m1 curved into lane 1 where x1 was already expected.
        XCTAssertTrue(rows[0].edges.contains(GraphEdge(fromLane: 0, toLane: 1)))
    }

    func testRootCommitTerminatesLane() {
        let rows = GraphLayouter.layout([commit("only", parents: [])])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].lane, 0)
        XCTAssertTrue(rows[0].edges.isEmpty)
        XCTAssertEqual(rows[0].laneCount, 1)
    }
}
