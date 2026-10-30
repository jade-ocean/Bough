import Foundation

/// One horizontal connection from a commit node to one of its parents.
struct GraphEdge: Equatable, Sendable {
    let fromLane: Int
    let toLane: Int
    /// Merge connections (all parents except the first) render curved.
    var isMergeCurve: Bool { fromLane != toLane }
}

/// Layout result for one history row.
struct GraphRow: Equatable, Sendable, Identifiable {
    var id: String { commit.sha }

    let commit: Commit
    /// Lane the node sits on.
    let lane: Int
    /// Other lanes carrying a straight line through this row.
    let passThrough: [Int]
    /// Node -> parent connections drawn below the node.
    let edges: [GraphEdge]
    /// Active lane count on this row (for coordinate space alignment).
    let laneCount: Int
}

/// Lane assignment over topologically ordered commits.
///
/// Classic approach: `lanes[i]` holds the sha each lane expects to see next.
/// First parent continues the node lane; additional parents curve into their
/// existing lane or claim a fresh one. Runs in O(commits x lanes).
enum GraphLayouter {
    static func layout(_ commits: [Commit]) -> [GraphRow] {
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            // 1. Node lane: where this commit was expected, or a free slot.
            var nodeLane = lanes.firstIndex(of: commit.sha)
            if nodeLane == nil {
                nodeLane = lanes.firstIndex(of: nil) ?? lanes.count
                if nodeLane! == lanes.count { lanes.append(commit.sha) }
            }

            // 2. Pass-through: every other occupied lane draws a straight line here.
            var passThrough: [Int] = []
            for index in 0..<lanes.count where index != nodeLane && lanes[index] != nil {
                passThrough.append(index)
            }

            // 3. Edges to parents.
            var edges: [GraphEdge] = []
            if commit.parents.isEmpty {
                // Root commit: lane terminates at the node.
                lanes[nodeLane!] = nil
            } else {
                for (parentIndex, parent) in commit.parents.enumerated() {
                    if parentIndex == 0 {
                        if let existing = lanes.firstIndex(of: parent), existing != nodeLane {
                            // First parent is already awaited on another lane: curve to it.
                            edges.append(GraphEdge(fromLane: nodeLane!, toLane: existing))
                            lanes[nodeLane!] = nil
                        } else {
                            // Straight continuation through the node lane.
                            lanes[nodeLane!] = parent
                            edges.append(GraphEdge(fromLane: nodeLane!, toLane: nodeLane!))
                        }
                        continue
                    }
                    if let existing = lanes.firstIndex(of: parent) {
                        // Merge into the lane already waiting for this parent.
                        edges.append(GraphEdge(fromLane: nodeLane!, toLane: existing))
                    } else {
                        let target: Int
                        if let free = lanes.firstIndex(of: nil) {
                            target = free
                            lanes[free] = parent
                        } else {
                            target = lanes.count
                            lanes.append(parent)
                        }
                        edges.append(GraphEdge(fromLane: nodeLane!, toLane: target))
                    }
                }
            }

            // 4. Effective width: shrink back when trailing lanes freed.
            var width = max(nodeLane! + 1, lanes.lastIndex(where: { $0 != nil }).map { $0 + 1 } ?? 0)
            if let maxEdge = edges.map(\.toLane).max() {
                width = max(width, maxEdge + 1)
            }

            rows.append(GraphRow(commit: commit, lane: nodeLane!,
                                 passThrough: passThrough, edges: edges,
                                 laneCount: width))
        }
        return rows
    }
}
