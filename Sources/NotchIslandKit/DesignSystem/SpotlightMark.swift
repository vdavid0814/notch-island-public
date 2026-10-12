import SwiftUI

/// NotchIsland's Spotlight mark: a ring with a wave flowing across it, from the left a little
/// above the middle down to the right. Drawn as a path, so it is sharp at any size.
nonisolated struct SpotlightMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * side, y: origin.y + y * side) }
        let ring: CGFloat = 0.11
        let outer = CGPath(ellipseIn: CGRect(origin: origin, size: CGSize(width: side, height: side)), transform: nil)
        let innerRect = CGRect(origin: point(ring, ring), size: CGSize(width: side * (1 - 2 * ring), height: side * (1 - 2 * ring)))
        let inner = CGPath(ellipseIn: innerRect, transform: nil)
        // The wave reaches a little into the ring, so the two are one.
        let reach = CGPath(ellipseIn: innerRect.insetBy(dx: -side * 0.02, dy: -side * 0.02), transform: nil)
        let half: CGFloat = 0.058
        let wave = CGMutablePath()
        wave.move(to: point(-0.05, 0.50 - half))
        wave.addCurve(to: point(1.05, 0.60 - half), control1: point(0.33, 0.27 - half), control2: point(0.64, 0.83 - half))
        wave.addLine(to: point(1.05, 0.60 + half))
        wave.addCurve(to: point(-0.05, 0.50 + half), control1: point(0.64, 0.83 + half), control2: point(0.33, 0.27 + half))
        wave.closeSubpath()
        let joined = outer.subtracting(inner).union(wave.intersection(reach))
        // The wave flows into the ring: its joins rounded (the shape grown, then shrunk back).
        let round = side * 0.035
        let grown = joined.union(joined.copy(strokingWithWidth: 2 * round, lineCap: .round, lineJoin: .round, miterLimit: 1))
        return Path(grown.subtracting(grown.copy(strokingWithWidth: 2 * round, lineCap: .round, lineJoin: .round, miterLimit: 1)))
    }
}

/// The mark as an app icon: dark, from deep blue-black at the top to slate grey, on a white tile
/// with the system's icon corners, a little raised (a soft shadow, a light rim).
struct SpotlightIcon: View {
    var side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 1), Color(white: 0.91)], startPoint: .top, endPoint: .bottom))
            .overlay {
                SpotlightMark()
                    .fill(LinearGradient(colors: [Color(red: 0.04, green: 0.15, blue: 0.21),
                                                  Color(red: 0.30, green: 0.38, blue: 0.44),
                                                  Color(red: 0.55, green: 0.60, blue: 0.64)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        SpotlightMark()
                            .stroke(.white.opacity(0.35), lineWidth: max(0.5, side * 0.006))
                            .blendMode(.plusLighter)
                    }
                    .shadow(color: .black.opacity(0.18), radius: side * 0.025, y: side * 0.015)
                    .padding(side * 0.12)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
