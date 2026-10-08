import SwiftUI

/// Where the layout puts each movable part of the widget in Customize's editor, in the widget's own
/// points (from its top-leading corner, `space`), without the part's offset.
struct ElementFramesKey: PreferenceKey {
    static let space = "widgetElements"

    static var defaultValue: [ElementID: CGRect] { [:] }

    static func reduce(value: inout [ElementID: CGRect], nextValue: () -> [ElementID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// A part of `widget` Customize can move: drawn `widget.offset(of: id)` away from where the
    /// layout puts it, resized by `widget.scale(of: id)` (the layout itself is not changed: nothing
    /// else moves or grows with it), over or under its neighbours by its layer.
    /// `drawsScale` false: the part draws itself at its size (a shape, whose lines stay as thick).
    func movableElement(_ id: ElementID, of widget: IslandWidget, drawsScale: Bool = true) -> some View {
        modifier(MovableElement(id: id, offset: widget.offset(of: id), scale: drawsScale ? widget.scale(of: id) : .one,
                                isGlass: widget.isGlass(id)))
            .zIndex(Double(widget.layer(of: id)))
    }

    /// Cut to the widget's outline, its corners included, where it is given: a part grown to the
    /// widget's edges or over all of it (`ImageLook.Fit`) goes no further than the widget. `origin`
    /// is the widget's corner from the part's own (where the layout puts it: its offset and size are
    /// drawn inside). Without an outline nothing is cut.
    func clipped(to outline: WidgetShape?, from origin: CGPoint) -> some View {
        clipShape(WidgetOutline(size: outline?.size, corners: outline?.corners ?? .uniform(0), origin: origin))
    }

    /// A row or column of movable parts, over or under its neighbours as its parts are
    /// (`IslandWidget.layer(ofGroup:)`).
    func elementGroup(_ ids: [ElementID], of widget: IslandWidget) -> some View {
        zIndex(widget.layer(ofGroup: ids))
    }
}

/// The widget's outline from a part's corner (`clipped(to:from:)`); without one, as large as can be.
nonisolated private struct WidgetOutline: Shape {
    /// The widget's size; nil, nothing to cut to.
    let size: CGSize?
    let corners: RectangleCornerRadii
    let origin: CGPoint

    func path(in rect: CGRect) -> Path {
        guard let size else { return Path(rect.insetBy(dx: -100_000, dy: -100_000)) }
        let frame = CGRect(origin: CGPoint(x: rect.minX + origin.x, y: rect.minY + origin.y), size: size)
        return UnevenRoundedRectangle(cornerRadii: corners, style: .continuous).path(in: frame)
    }
}

private struct MovableElement: ViewModifier {
    let id: ElementID
    let offset: ElementOffset
    let scale: ElementScale
    /// A button or a ruler on Liquid Glass: in the underlay (`WidgetLayerPass`), the only part drawn.
    let isGlass: Bool

    @Environment(\.isElementEditing) private var isEditing
    @Environment(\.widgetLayerPass) private var layerPass
    @Environment(\.elementOverlaps) private var overlaps
    @Environment(\.inkPart) private var inkPart

    /// How far the editor's fading mask reaches past the part, in points.
    private static let maskReach: CGFloat = 1000

    func body(content: Content) -> some View {
        Group {
            if isEditing {
                sized(editing(content))
            } else {
                // On the island nothing more than the size and offset (no mask or shadow to draw).
                sized(content)
            }
        }
        // Another part's ink read alone: this one unseen.
        .opacity((inkPart == nil || inkPart == id) && (layerPass != .underlay || isGlass) ? 1 : 0)
        .environment(\.elementMove, CGSize(width: offset.x, height: offset.y))
        .offset(x: offset.x, y: offset.y)
        // On the offset view, so the frame is the layout's, not where the part is drawn; a text
        // part's is its styled box (`WidgetLabel`), from the same corner.
        .backgroundPreferenceValue(LabelBoxKey.self) { box in
            if isEditing {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(ElementFramesKey.space))
                    Color.clear.preference(key: ElementFramesKey.self, value: [id: box.map {
                        CGRect(x: frame.minX + $0.minX, y: frame.minY + $0.minY, width: $0.width, height: $0.height)
                    } ?? frame])
                }
            }
        }
    }

    /// Resized from its top-leading corner; a part at its own size is left as it is (no transform
    /// to draw).
    @ViewBuilder private func sized(_ view: some View) -> some View {
        if scale == .one {
            view
        } else {
            view.scaleEffect(x: scale.x, y: scale.y, anchor: .topLeading)
        }
    }

    /// In the editor: what of it is under another part, faded, and lifted where it is over one.
    @ViewBuilder private func editing(_ content: Content) -> some View {
        let covered = overlaps.covered[id] ?? []
        let lifted = overlaps.lifted.contains(id)
        if covered.isEmpty {
            // A shadow draws the part in a layer of its own at the widget's size, which the editor
            // enlarges: only a part over another has one, the rest stay sharp.
            if lifted {
                content.shadow(color: .black.opacity(0.85), radius: 2.5)
            } else {
                content
            }
        } else {
            content
                // Far past its box on every side: a text part is drawn beyond the box it lays out in.
                .mask(alignment: .topLeading) {
                    let reach = Self.maskReach
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        context.blendMode = .copy
                        for rect in covered {
                            context.fill(Path(rect.offsetBy(dx: reach, dy: reach)), with: .color(.white.opacity(0.3)))
                        }
                    }
                    .frame(width: 2 * reach, height: 2 * reach)
                    .offset(x: -reach, y: -reach)
                }
                .shadow(color: .black.opacity(lifted ? 0.85 : 0), radius: lifted ? 2.5 : 0)
        }
    }
}
