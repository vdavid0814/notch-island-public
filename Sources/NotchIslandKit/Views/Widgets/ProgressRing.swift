import SwiftUI

/// A line bent round: the ring of a level, of a load, of the battery, and the fan's and the chip's
/// dials. Drawn exactly as a line is (`ProgressLook`, `ScrubTrack`): its track and the part filled
/// in the look's colours, its ends round, rounded or sharp, a knob where it stands, thicker or
/// thinner, smaller, and moved from where the layout puts it. Every field of the look at its default
/// is the ring as its widget draws it.
struct ProgressRing: View {
    /// 0…1 of the sweep filled.
    let fraction: Double
    /// The room it is laid out in: a square this wide.
    let diameter: CGFloat
    /// Its thickness before the look's.
    let line: CGFloat
    var look: ProgressLook = .plain
    /// Where it starts (degrees clockwise from three o'clock) and how far round it goes: a whole
    /// ring from the top, or a dial open at the bottom.
    var start: Double = -90
    var sweep: Double = 360
    var automaticTrack: Color = .white.opacity(0.16)
    /// The least drawn of a round-ended fill: a dial shows a dot where it begins even at nothing.
    var minimumFill: Double = 0
    var automaticFill: AnyShapeStyle = AnyShapeStyle(.tint)
    /// Where the knob stands when not at the fill's end (the speed a fan is held at).
    var knobAt: Double?
    /// A knob drawn even where the look has none (Base): the fan's dial while it is held.
    var forcesKnob = false
    /// Whether the knob follows its place smoothly (not while it is dragged).
    var animatesKnob = true
    /// How the fill follows a new value; nil: at once.
    var animation: Animation?
    /// In Customize's panel for the line: where it is drawn (`ProgressPartFramesKey`).
    var reportsFrame = false

    /// For the cover's colour alone: a ring drawn on its own (a test) has no model.
    @Environment(AppModel.self) private var model: AppModel?

    /// The ring's own diameter and thickness under `look`, in a room `diameter` wide.
    static func metrics(diameter: CGFloat, line: CGFloat, look: ProgressLook) -> (diameter: CGFloat, line: CGFloat) {
        let drawn = max(diameter * look.barLength, 4)
        return (drawn, min(max(line * look.barThickness, 1), drawn * 0.45))
    }

    var body: some View {
        let metrics = Self.metrics(diameter: diameter, line: line, look: look)
        let thickness = metrics.line
        let filled = min(max(fraction, 0), 1)
        let radius = (metrics.diameter - thickness) / 2
        ZStack {
            RingArc(to: 1, start: start, sweep: sweep, thickness: thickness, ends: look.ends)
                .fill(color(look.trackColor) ?? AnyShapeStyle(automaticTrack))
            RingArc(to: look.ends == .round ? max(filled, minimumFill) : filled, start: start, sweep: sweep, thickness: thickness,
                    ends: look.ends)
                .fill(color(look.fillColor) ?? automaticFill)
                .animation(animation, value: filled)
            if let knob = knobSize(thickness) {
                let place = min(max(knobAt ?? filled, 0), 1)
                let angle = start + sweep * place
                RoundedRectangle(cornerRadius: (forcesKnob && look.knob == .base ? .circle : look.knob).radius(size: knob), style: .continuous)
                    .fill(.white)
                    .frame(width: knob.width, height: knob.height)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    // Along the ring: a capsule lies on it.
                    .rotationEffect(.degrees(angle + 90))
                    .offset(x: cos(angle * .pi / 180) * radius, y: sin(angle * .pi / 180) * radius)
                    .animation(animatesKnob ? .easeOut(duration: 0.3) : nil, value: place)
            }
        }
        .frame(width: metrics.diameter, height: metrics.diameter)
        .reportsProgressPart(.bar, if: reportsFrame)
        .offset(x: look.barOffset.x, y: look.barOffset.y)
        .frame(width: diameter, height: diameter)
    }

    private func knobSize(_ thickness: CGFloat) -> CGSize? {
        look.knob.size(height: thickness) ?? (forcesKnob ? ProgressLook.Knob.circle.size(height: thickness) : nil)
    }

    /// A colour the look picked; nil where it picked none.
    private func color(_ color: TextStyle.TextColor) -> AnyShapeStyle? {
        switch color {
        case .automatic: nil
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model?.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }
}

/// A ring's arc as a shape to fill, `thickness` thick, inside its rectangle: from its start as far
/// as `to` of its sweep, its ends as a line's (`ProgressLook.Ends`).
nonisolated struct RingArc: Shape {
    var to: Double
    let start: Double
    let sweep: Double
    let thickness: CGFloat
    let ends: ProgressLook.Ends

    var animatableData: Double {
        get { to }
        set { to = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - thickness / 2
        let length = sweep * min(max(to, 0), 1)
        guard radius > 0, length > 0 else { return Path() }
        func arc(from: Double, to: Double) -> Path {
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
            return path
        }
        // All the way round: it has no ends.
        if length >= 360 {
            return arc(from: 0, to: 360).strokedPath(StrokeStyle(lineWidth: thickness))
        }
        switch ends {
        case .round:
            return arc(from: start, to: start + length).strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
        case .sharp:
            return arc(from: start, to: start + length).strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .butt))
        case .rounded:
            // A thinner, shorter arc grown by the corners' radius on every side: its corners round.
            let inset = Double(radius) > 0 ? min(Double(ends.radius(height: thickness)), Double(radius) * length * .pi / 360) : 0
            let corner = CGFloat(inset)
            guard corner > 0.05, thickness - 2 * corner > 0.1 else {
                return arc(from: start, to: start + length).strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .butt))
            }
            let degrees = inset / Double(radius) * 180 / .pi
            let core = arc(from: start + degrees, to: start + length - degrees)
                .strokedPath(StrokeStyle(lineWidth: thickness - 2 * corner, lineCap: .butt))
            return core.union(core.strokedPath(StrokeStyle(lineWidth: 2 * corner, lineJoin: .round)))
        }
    }
}

/// A text inside a ring or a dial (a load's name, the chip's degrees): set as the widget sets it, or
/// in its style from Customize (`WidgetKindSpec.innerTexts`), and moved as the ring's look says —
/// the same as the texts at a line's ends (`StatBar`).
struct RingText: View {
    let text: Text
    let style: TextStyle?
    let size: CGFloat
    var weight: NSFont.Weight = .medium
    var design: Font.Design = .default
    var automatic = AnyShapeStyle(.secondary)
    let part: ProgressLook.Part
    let look: ProgressLook
    var reportsFrame = false
    /// The widest it is drawn (its ring's inside): set larger in Customize, its letters shrink to
    /// this. nil: as wide as its letters.
    var limit: CGFloat?

    /// For the cover's colour alone: a ring drawn on its own (a test) has no model.
    @Environment(AppModel.self) private var model: AppModel?

    /// The largest a ring's text is set, in points: Customize's slider and handles stop here, and a
    /// size stored larger is drawn at this.
    static let largest = 25.0

    /// `style` no larger than a ring's texts are.
    static func capped(_ style: TextStyle?) -> TextStyle? {
        guard var style, let size = style.size, size > largest else { return style }
        style.size = largest
        return style
    }

    /// A text across a ring's middle is no wider than this (the ring's inside, a little clear of
    /// it), one in a dial's opening than `nameLimit`.
    static func valueLimit(diameter: CGFloat, line: CGFloat) -> CGFloat { max((diameter - 2 * line) * 0.94, 8) }
    static func nameLimit(diameter: CGFloat) -> CGFloat { max(diameter * 0.52, 8) }

    var body: some View {
        let offset = look.offset(of: part)
        let style = Self.capped(style)
        Group {
            if let style {
                text
                    .font(Font(style.font(size: size, weight: weight)).monospacedDigit())
                    .underline(style.isUnderlined)
                    .strikethrough(style.isStruckThrough)
                    .foregroundStyle(color(style.color))
            } else {
                text
                    .font(.system(size: size, weight: Font.Weight(weight), design: design).monospacedDigit())
                    .foregroundStyle(automatic)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(limit == nil ? 0.6 : 0.05)
        // As the widget sets it, it shrinks to its room; set or moved in Customize, it is as large
        // as set — up to its limit, where it has one.
        .fixedSize(horizontal: limit == nil && (style != nil || offset != .zero || reportsFrame), vertical: false)
        .reportsProgressPart(part, if: reportsFrame)
        .frame(maxWidth: limit)
        .offset(x: offset.x, y: offset.y)
    }

    private func color(_ color: TextStyle.TextColor) -> AnyShapeStyle {
        switch color {
        case .automatic: automatic
        case .custom(let rgb): AnyShapeStyle(rgb.color)
        case .artwork: AnyShapeStyle(model?.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }
}

private extension Font.Weight {
    init(_ weight: NSFont.Weight) {
        switch weight {
        case .regular: self = .regular
        case .semibold: self = .semibold
        case .bold: self = .bold
        default: self = .medium
        }
    }
}
