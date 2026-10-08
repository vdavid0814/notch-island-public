import SwiftUI

/// The handles round a part picked in the panels under Customize's editor (a button's symbol, a
/// playback line's parts): small squares at its corners and the middles of its sides — those
/// that keep apart: a part too thin (or too narrow) for three in a row keeps the middles of its
/// sides, which size it one way each, and drops its corners. Drawn only: the panel's one gesture
/// asks `hit` which a press is on, the nearest within reach, before anything else.
enum PanelHandles {
    /// A handle's side on screen.
    static let size: CGFloat = 5
    /// From the part's edge to the handles' middles.
    static let pad: CGFloat = 2
    /// A press this near a handle's middle takes it (on screen).
    static let reach: CGFloat = 5

    /// The handles round `frame`: the middles of its sides always, its corners where there is room
    /// for three in a row both ways.
    static func handles(for frame: CGRect) -> [ButtonSymbolPanel.Handle] {
        let room = 3 * size + 2
        let corners = frame.height + 2 * pad >= room && frame.width + 2 * pad >= room
        return ButtonSymbolPanel.handles.filter { handle in corners || handle.x == 0 || handle.y == 0 }
    }

    static func position(of handle: ButtonSymbolPanel.Handle, round frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX + CGFloat(handle.x) * (frame.width / 2 + pad),
                y: frame.midY + CGFloat(handle.y) * (frame.height / 2 + pad))
    }

    /// The handle a press at `point` takes: the nearest within reach.
    static func hit(_ point: CGPoint, round frame: CGRect) -> ButtonSymbolPanel.Handle? {
        handles(for: frame)
            .map { ($0, hypot(position(of: $0, round: frame).x - point.x, position(of: $0, round: frame).y - point.y)) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
    }

    /// The handles drawn round `frame`.
    static func drawn(round frame: CGRect) -> some View {
        ForEach(handles(for: frame), id: \.self) { handle in
            Rectangle()
                .fill(.white)
                .frame(width: size, height: size)
                .overlay { Rectangle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                .position(position(of: handle, round: frame))
        }
        .allowsHitTesting(false)
    }
}
