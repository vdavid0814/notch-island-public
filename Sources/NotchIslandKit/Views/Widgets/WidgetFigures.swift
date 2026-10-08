import SwiftUI

/// The shapes added to a widget (`WidgetFigure`), over its parts: each laid out at its own size in
/// the middle of the widget's inside, then moved and sized as Customize set it.
struct WidgetFiguresLayer: View {
    let widget: IslandWidget

    var body: some View {
        ZStack {
            ForEach(widget.figures) { figure in
                WidgetFigureView(figure: figure, scale: widget.scale(of: figure.id))
                    // Drawn at its size, not stretched: a ring's line stays as thick.
                    .movableElement(figure.id, of: widget, drawsScale: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// One shape: its layout box at its own size, the shape drawn `scale` times as large from its
/// top-leading corner (as a scaled part is, `ElementScale.applied`), its lines as thick at any size.
struct WidgetFigureView: View {
    let figure: WidgetFigure
    let scale: ElementScale
    /// Drawn this many times larger (Customize's panel under the editor): its own size, its lines
    /// as thick, drawn sharp at that size rather than enlarged after.
    var zoom: CGFloat = 1

    @Environment(AppModel.self) private var model

    var body: some View {
        let base = CGSize(width: figure.kind.size.width * zoom, height: figure.kind.size.height * zoom)
        Color.clear
            .frame(width: base.width, height: base.height)
            .overlay(alignment: .topLeading) {
                let size = CGSize(width: base.width * scale.x, height: base.height * scale.y)
                shape(size)
                    .foregroundStyle(color)
                    .frame(width: size.width, height: size.height)
                    // About its middle: where it is and how large it is stay as they were.
                    .rotationEffect(.degrees(figure.rotation))
            }
    }

    @ViewBuilder private func shape(_ size: CGSize) -> some View {
        switch figure.kind {
        case .line:
            RoundedRectangle(cornerRadius: figure.effectiveCorners.radius(size, line: true), style: .continuous)
        case .ring: Ellipse().strokeBorder(lineWidth: 2.5 * zoom)
        case .disc: Ellipse()
        case .square:
            let square = RoundedRectangle(cornerRadius: figure.effectiveCorners.radius(size, line: false), style: .continuous)
            if figure.isFilled { square } else { square.strokeBorder(lineWidth: 2.5 * zoom) }
        case .arrow, .turnArrow, .circleArrow, .twoWayArrow:
            Image(systemName: figure.kind.symbol)
                .resizable()
                .fontWeight(.semibold)
        }
    }

    private var color: AnyShapeStyle {
        switch figure.color {
        case .automatic: AnyShapeStyle(.primary)
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }
}
