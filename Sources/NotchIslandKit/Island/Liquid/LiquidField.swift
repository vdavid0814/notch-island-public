import CoreGraphics
import Foundation

/// One moment of the liquid: the notch (swollen by `swell`), the drop, and the neck between them.
/// Global AppKit coordinates.
nonisolated struct LiquidScene: Sendable, Equatable {
    var notch: CGRect
    var notchRadius: CGFloat
    var drop: LiquidBlob
    /// From the notch's side to the drop's centre, `thickness` wide at its ends (0: no neck).
    var neckFrom: CGPoint
    var neckTo: CGPoint
    var neckThickness: CGFloat
}

/// The liquid's outline as a path: the shapes' signed distances merged with a smooth minimum (the
/// fillets a liquid makes where two parts meet, and a neck that parts by itself as it thins),
/// traced at zero by marching squares.
///
/// Worked out up front for every frame of a move and played by the render server
/// (`LiquidCard`): drawn with SwiftUI's blur and alpha threshold every frame instead, the liquid
/// cost ~1.5 s of CPU per volume change and peaked at 72 Energy Impact (measured).
nonisolated enum LiquidField {
    /// The smooth minimum's reach: the fillets' size (the blur's, before).
    static let smoothing: CGFloat = 12
    /// The grid the outline is traced on, in points.
    static let cell: CGFloat = 2

    static func path(_ scene: LiquidScene, clip: CGRect) -> CGPath {
        // Only where the shapes are, plus the fillets' reach; clipped to the window (the notch
        // reaches above it, where the outline closes out of sight).
        var bounds = scene.notch.union(scene.drop.rect)
        if scene.neckThickness >= 1 {
            bounds = bounds.union(CGRect(x: min(scene.neckFrom.x, scene.neckTo.x), y: min(scene.neckFrom.y, scene.neckTo.y),
                                         width: abs(scene.neckTo.x - scene.neckFrom.x), height: abs(scene.neckTo.y - scene.neckFrom.y)))
        }
        bounds = bounds.insetBy(dx: -(smoothing + 2 * cell), dy: -(smoothing + 2 * cell)).intersection(clip.insetBy(dx: -2 * cell, dy: -2 * cell))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return CGMutablePath() }
        let columns = Int((bounds.width / cell).rounded(.up)) + 1
        let rows = Int((bounds.height / cell).rounded(.up)) + 1
        var field = [Float](repeating: 1, count: (columns + 2) * (rows + 2))
        let stride = columns + 2
        // A border of "outside" all round, so every outline closes.
        for row in 0..<rows {
            let y = bounds.minY + CGFloat(row) * cell
            for column in 0..<columns {
                let x = bounds.minX + CGFloat(column) * cell
                field[(row + 1) * stride + column + 1] = Float(distance(CGPoint(x: x, y: y), scene))
            }
        }
        return trace(field, columns: columns + 2, rows: rows + 2,
                     origin: CGPoint(x: bounds.minX - cell, y: bounds.minY - cell))
    }

    /// The scene's signed distance at `p` (negative inside).
    static func distance(_ p: CGPoint, _ scene: LiquidScene) -> CGFloat {
        var d = roundedRect(p, scene.notch, scene.notchRadius)
        d = smoothMin(d, roundedRect(p, scene.drop.rect, scene.drop.radius), smoothing)
        if scene.neckThickness >= 1 {
            d = smoothMin(d, neck(p, scene.neckFrom, scene.neckTo, scene.neckThickness), smoothing)
        }
        return d
    }

    static func roundedRect(_ p: CGPoint, _ rect: CGRect, _ radius: CGFloat) -> CGFloat {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let qx = abs(p.x - rect.midX) - (rect.width / 2 - r)
        let qy = abs(p.y - rect.midY) - (rect.height / 2 - r)
        return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    }

    /// A tapering neck: `thickness` wide at both ends, thinner in the middle (where it parts).
    static func neck(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ thickness: CGFloat) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let length = abx * abx + aby * aby
        let h = length > 0 ? min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / length, 0), 1) : 0
        // A point and a half thinner than drawn, so the middle parts while it still has some body
        // (as the blur used to cut it) rather than thinning to a hairline.
        let radius = thickness / 2 * (1 - 0.55 * sin(.pi * h)) - 1.5
        return hypot(p.x - (a.x + abx * h), p.y - (a.y + aby * h)) - radius
    }

    /// Polynomial smooth minimum: `a` and `b` joined with a fillet of about `k`.
    static func smoothMin(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k / 4
    }

    // MARK: Marching squares

    /// The zero outline of a sampled field, as closed polygons. Crossings are kept in flat arrays
    /// indexed by grid edge (no hashing: this runs for every frame of a move).
    static func trace(_ field: [Float], columns: Int, rows: Int, origin: CGPoint) -> CGPath {
        let edges = columns * rows * 2
        var points = [CGPoint](repeating: .zero, count: edges)
        var hasPoint = [Bool](repeating: false, count: edges)
        var first = [Int32](repeating: -1, count: edges)
        var second = [Int32](repeating: -1, count: edges)
        var used: [Int] = []
        @inline(__always) func value(_ x: Int, _ y: Int) -> Float { field[y * columns + x] }
        @inline(__always) func crossing(_ x: Int, _ y: Int, _ direction: Int) -> Int {
            let k = ((y * columns) + x) * 2 + direction
            if !hasPoint[k] {
                hasPoint[k] = true
                used.append(k)
                let a = value(x, y)
                let b = direction == 0 ? value(x + 1, y) : value(x, y + 1)
                let t = CGFloat(a / (a - b))
                points[k] = CGPoint(x: origin.x + (CGFloat(x) + (direction == 0 ? t : 0)) * cell,
                                    y: origin.y + (CGFloat(y) + (direction == 1 ? t : 0)) * cell)
            }
            return k
        }
        @inline(__always) func link(_ a: Int, _ b: Int) {
            if first[a] < 0 { first[a] = Int32(b) } else { second[a] = Int32(b) }
            if first[b] < 0 { first[b] = Int32(a) } else { second[b] = Int32(a) }
        }
        for y in 0..<(rows - 1) {
            for x in 0..<(columns - 1) {
                let v0 = value(x, y), v1 = value(x + 1, y), v2 = value(x + 1, y + 1), v3 = value(x, y + 1)
                let index = (v0 < 0 ? 1 : 0) | (v1 < 0 ? 2 : 0) | (v2 < 0 ? 4 : 0) | (v3 < 0 ? 8 : 0)
                if index == 0 || index == 15 { continue }
                switch index {
                case 1, 14: link(crossing(x, y, 1), crossing(x, y, 0))
                case 2, 13: link(crossing(x, y, 0), crossing(x + 1, y, 1))
                case 3, 12: link(crossing(x, y, 1), crossing(x + 1, y, 1))
                case 4, 11: link(crossing(x + 1, y, 1), crossing(x, y + 1, 0))
                case 6, 9: link(crossing(x, y, 0), crossing(x, y + 1, 0))
                case 7, 8: link(crossing(x, y, 1), crossing(x, y + 1, 0))
                default:
                    // A saddle: the centre decides which corners join.
                    let centre = (v0 + v1 + v2 + v3) / 4
                    if (centre < 0) == (index == 5) {
                        link(crossing(x, y, 1), crossing(x, y + 1, 0)); link(crossing(x, y, 0), crossing(x + 1, y, 1))
                    } else {
                        link(crossing(x, y, 1), crossing(x, y, 0)); link(crossing(x + 1, y, 1), crossing(x, y + 1, 0))
                    }
                }
            }
        }
        let path = CGMutablePath()
        var visited = [Bool](repeating: false, count: edges)
        for start in used where !visited[start] {
            var previous = -1
            var current = start
            path.move(to: points[current])
            while current >= 0, !visited[current] {
                visited[current] = true
                if current != start { path.addLine(to: points[current]) }
                let a = Int(first[current]), b = Int(second[current])
                let next = a != previous ? a : b
                previous = current
                current = next
            }
            path.closeSubpath()
        }
        return path
    }
}
