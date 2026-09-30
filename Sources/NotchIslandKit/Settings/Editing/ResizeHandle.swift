import AppKit
import SwiftUI

/// A handle on a selection's outline: the four corners and the middle of each edge. The board
/// resizes widgets by their corners only.
enum ResizeHandle: CaseIterable {
    case topLeading, top, topTrailing, leading, trailing, bottomLeading, bottom, bottomTrailing

    static let corners: [ResizeHandle] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]

    /// The vertical edge it drags: -1 the leading one, 1 the trailing one, 0 neither.
    var horizontal: Int {
        switch self {
        case .topLeading, .leading, .bottomLeading: -1
        case .top, .bottom: 0
        case .topTrailing, .trailing, .bottomTrailing: 1
        }
    }

    /// The horizontal edge it drags: -1 the top, 1 the bottom, 0 neither.
    var vertical: Int {
        switch self {
        case .topLeading, .top, .topTrailing: -1
        case .leading, .trailing: 0
        case .bottomLeading, .bottom, .bottomTrailing: 1
        }
    }

    var movesLeading: Bool { horizontal < 0 }
    var movesTop: Bool { vertical < 0 }

    /// The pointer over it: the system's resize arrows for its edge or corner.
    var pointer: PointerStyle {
        let position: FrameResizePosition = switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
        return .frameResize(position: position)
    }

    /// Where it sits on `frame`.
    func position(on frame: CGRect) -> CGPoint {
        CGPoint(x: horizontal < 0 ? frame.minX : horizontal > 0 ? frame.maxX : frame.midX,
                y: vertical < 0 ? frame.minY : vertical > 0 ? frame.maxY : frame.midY)
    }

    /// `start` with this handle's edges moved by `translation`, never smaller than `minimum`.
    func resized(_ start: CGRect, by translation: CGSize, minimum: CGSize) -> CGRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if horizontal < 0 { minX = min(start.minX + translation.width, maxX - minimum.width) }
        else if horizontal > 0 { maxX = max(start.maxX + translation.width, minX + minimum.width) }
        if vertical < 0 { minY = min(start.minY + translation.height, maxY - minimum.height) }
        else if vertical > 0 { maxY = max(start.maxY + translation.height, minY + minimum.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct HandleDot: View {
    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.islandAccent, lineWidth: 2))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(width: 26, height: 26)
            .contentShape(.rect)
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
    }
}
