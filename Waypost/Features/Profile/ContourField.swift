import SwiftUI

/// A topographic map of nowhere, for the pass to sit on.
///
/// Contours of one height field can never cross each other, and that is the whole reason
/// this is a field rather than a stack of wobbled rings. Rings drawn round separate peaks
/// cut through one another, which no contour map has ever done and which the eye picks up
/// immediately even when it cannot say why.
///
/// So: a handful of Gaussian hills and hollows, sampled on a grid, and the lines walked out
/// of it by marching squares. Worked out once for the whole launch — it is a pure function
/// of eight numbers that never change — and scaled wherever it is drawn.
struct ContourField: Shape {
    func path(in rect: CGRect) -> Path {
        Self.unit.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }

    // MARK: The field

    private static let cols = 48
    private static let rows = 64
    private static let levels = 11

    /// Hills at a positive amplitude, hollows at a negative one. Placed by hand so the
    /// close-packed slopes fall down the left and the open ground sits under the card.
    private static let bumps: [(x: Double, y: Double, amp: Double, spread: Double)] = [
        (0.26, 0.18,  1.00, 0.30), (0.76, 0.36,  0.86, 0.26),
        (0.34, 0.70,  0.94, 0.28), (0.84, 0.88,  0.72, 0.24),
        (0.06, 0.52,  0.60, 0.22), (0.55, 0.52, -0.55, 0.20),
        (0.62, 0.05, -0.40, 0.16), (0.14, 0.92, -0.45, 0.18),
    ]

    private static func height(_ x: Double, _ y: Double) -> Double {
        var total = 0.0
        for bump in bumps {
            let dx = (x - bump.x) / bump.spread
            let dy = (y - bump.y) / bump.spread
            total += bump.amp * exp(-(dx * dx + dy * dy))
        }
        return total
    }

    /// The contours, in a unit square.
    private static let unit: Path = {
        var samples: [[Double]] = []
        samples.reserveCapacity(rows)
        for row in 0..<rows {
            let y = Double(row) / Double(rows - 1)
            samples.append((0..<cols).map { height(Double($0) / Double(cols - 1), y) })
        }

        let low = samples.flatMap { $0 }.min() ?? 0
        let high = samples.flatMap { $0 }.max() ?? 1

        var path = Path()
        let across = Double(cols - 1), down = Double(rows - 1)

        /// Where a contour crosses one edge of a cell, in the unit square.
        func cross(_ a: (Int, Int), _ b: (Int, Int),
                   _ av: Double, _ bv: Double, _ level: Double) -> CGPoint {
            let t = bv == av ? 0.5 : (level - av) / (bv - av)
            return CGPoint(x: (Double(a.0) + (Double(b.0) - Double(a.0)) * t) / across,
                           y: (Double(a.1) + (Double(b.1) - Double(a.1)) * t) / down)
        }

        for step in 1...levels {
            let level = low + (high - low) * Double(step) / Double(levels + 1)
            for row in 0..<(rows - 1) {
                for col in 0..<(cols - 1) {
                    // The cell's corners, clockwise from the top left.
                    let corners = [(col, row), (col + 1, row), (col + 1, row + 1), (col, row + 1)]
                    let values = [samples[row][col], samples[row][col + 1],
                                  samples[row + 1][col + 1], samples[row + 1][col]]

                    var crossings: [CGPoint] = []
                    for edge in 0..<4 {
                        let a = edge, b = (edge + 1) % 4
                        if (values[a] < level) != (values[b] < level) {
                            crossings.append(cross(corners[a], corners[b], values[a], values[b], level))
                        }
                    }
                    // Two crossings is one line through the cell; four is a saddle, and
                    // pairing them in order is the ambiguous case drawn the simple way.
                    if crossings.count >= 2 {
                        path.move(to: crossings[0])
                        path.addLine(to: crossings[1])
                    }
                    if crossings.count == 4 {
                        path.move(to: crossings[2])
                        path.addLine(to: crossings[3])
                    }
                }
            }
        }
        return path
    }()
}
