import SwiftUI

/// Per-row graph drawing: pass-through lanes, node, edges to parents.
struct GraphCellView: View {
    let row: GraphRow
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let isHead: Bool

    private static let palette: [Color] = [
        Color(red: 0.42, green: 0.56, blue: 0.50), // moss green (brand)
        Color(red: 0.36, green: 0.52, blue: 0.72), // steel blue
        Color(red: 0.70, green: 0.45, blue: 0.42), // clay red
        Color(red: 0.72, green: 0.58, blue: 0.35), // amber
        Color(red: 0.55, green: 0.45, blue: 0.66), // muted violet
        Color(red: 0.48, green: 0.60, blue: 0.60), // teal gray
    ]

    var body: some View {
        Canvas { context, size in
            func laneX(_ lane: Int) -> CGFloat {
                CGFloat(lane) * columnWidth + columnWidth / 2 + 2
            }
            let midY = rowHeight / 2

            // Pass-through lanes: straight lines spanning the row.
            for lane in row.passThrough {
                let x = laneX(lane)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: rowHeight))
                context.stroke(path, with: .color(color(for: lane)), lineWidth: 1.6)
            }

            // Node lane: line above and below the node.
            let nx = laneX(row.lane)
            var topHalf = Path()
            topHalf.move(to: CGPoint(x: nx, y: 0))
            topHalf.addLine(to: CGPoint(x: nx, y: midY))
            context.stroke(topHalf, with: .color(color(for: row.lane)), lineWidth: 1.6)
            if !row.commit.parents.isEmpty {
                var bottomHalf = Path()
                bottomHalf.move(to: CGPoint(x: nx, y: midY))
                bottomHalf.addLine(to: CGPoint(x: nx, y: rowHeight))
                context.stroke(bottomHalf, with: .color(color(for: row.lane)), lineWidth: 1.6)
            }

            // Edges to parents (drawn below the node).
            for edge in row.edges {
                let tx = laneX(edge.toLane)
                var path = Path()
                path.move(to: CGPoint(x: nx, y: midY))
                if edge.fromLane == edge.toLane {
                    path.addLine(to: CGPoint(x: tx, y: rowHeight))
                } else {
                    path.addCurve(
                        to: CGPoint(x: tx, y: rowHeight),
                        control1: CGPoint(x: nx, y: midY + (rowHeight - midY) * 0.6),
                        control2: CGPoint(x: tx, y: midY + (rowHeight - midY) * 0.4))
                }
                context.stroke(path, with: .color(color(for: edge.toLane)),
                               lineWidth: edge.isMergeCurve ? 1.2 : 1.6)
            }

            // Node
            let nodeRect = CGRect(x: nx - 4, y: midY - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: nodeRect), with: .color(color(for: row.lane)))
            if isHead {
                let ring = CGRect(x: nx - 6.5, y: midY - 6.5, width: 13, height: 13)
                context.stroke(Path(ellipseIn: ring),
                               with: .color(.accentColor), lineWidth: 1.5)
            }
        }
        .frame(width: CGFloat(row.laneCount) * columnWidth + 4, height: rowHeight)
    }

    private func color(for lane: Int) -> Color {
        Self.palette[lane % Self.palette.count]
    }
}
