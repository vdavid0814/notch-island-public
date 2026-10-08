import SwiftUI

/// A button of a widget as its `ButtonLook` sets it: the symbol alone (Regular), or on a shape of
/// its own — opaque (Solid) or Liquid Glass — in a circle or a capsule, with sharp, rounded or
/// round corners, filled with the plate, a colour, the cover's colour or nothing but a faint edge.
/// The symbol inside is as large and as far from the middle as the look says, with rounded or sharp
/// edges, in its colour or as an outline.
///
/// It takes the room the plain symbol takes, whatever the look: the shape, a larger symbol and its
/// offset are drawn over that room, so restyling a button never moves the parts around it — and
/// kept inside the widget, moved in from an edge it would reach past.
struct WidgetButtonLabel: View {
    let look: ButtonLook
    /// The system symbol the widget draws (`play.fill`…).
    let symbol: String
    /// The widget's own size for the symbol.
    let points: CGFloat
    /// Pressed: the button is a button of its own, as large as it is drawn and where it is drawn, so
    /// a click anywhere on its shape takes. (A button round the label took clicks only on the
    /// plain symbol's room, which a larger shape reaches past: a click beside the symbol was lost.)
    var action: (() -> Void)? = nil
    /// Its name, for the pointer's help and VoiceOver, with an `action`.
    var title: String? = nil

    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.drawsWidgetSurface) private var drawsSurface
    @Environment(\.widgetLayerPass) private var layerPass
    @Environment(\.widgetShape) private var widgetShape
    @Environment(\.elementMove) private var move
    @Environment(AppModel.self) private var model

    var body: some View {
        // The plain symbol's room, unseen; the button drawn over it.
        Image(systemName: symbol)
            .font(.system(size: points))
            .hidden()
            .overlay {
                GeometryReader { proxy in
                    // Where its layout puts it, before it is moved: kept inside the widget from
                    // there, the move then takes it where it was moved (even past the edge).
                    let room = proxy.frame(in: .named(WidgetShape.space)).offsetBy(dx: -move.width, dy: -move.height)
                    let drawn = Self.drawnSize(of: look, points: points, room: proxy.size)
                    let shift = widgetShape.map { Self.shift(room: room, drawn: drawn, widget: $0.size) } ?? .zero
                    pressable
                        .position(x: proxy.size.width / 2 + shift.width, y: proxy.size.height / 2 + shift.height)
                }
            }
    }

    @ViewBuilder private var pressable: some View {
        if let action {
            Button(action: action) { button }
                .buttonStyle(.plain)
                .help(title ?? "")
                .accessibilityLabel(title ?? "")
        } else {
            button
        }
    }

    @ViewBuilder private var button: some View {
        if look.material.hasShape {
            let size = Self.size(of: look, points: points)
            let shape = Self.shape(of: look, size: size)
            // Zoomed in Customize: the glass under the picture, the symbol (and any other
            // surface) in it (`SharpZoom`).
            let isGlass = ButtonLook.isGlass(look)
            scaledIcon
                .offset(x: look.iconOffset.x * size.width, y: look.iconOffset.y * size.height)
                .opacity(layerPass == .underlay ? 0 : 1)
                .frame(width: size.width, height: size.height)
                .background {
                    if layerPass == .all || (layerPass == .underlay) == isGlass { surface(shape) }
                }
                .contentShape(shape)
        } else {
            scaledIcon.opacity(layerPass == .underlay ? 0 : 1)
        }
    }

    /// How large the button is drawn over its room (`room`, the plain symbol's): its shape, or the
    /// symbol at its size.
    static func drawnSize(of look: ButtonLook, points: CGFloat, room: CGSize) -> CGSize {
        if look.material.hasShape { return size(of: look, points: points) }
        return CGSize(width: room.width * look.iconScale, height: room.height * look.iconScale)
    }

    /// The button's way in from the edges of a widget `widget` large, drawn `drawn` large over
    /// `room` (in the widget's points): nothing where it fits, centred where it is larger.
    static func shift(room: CGRect, drawn: CGSize, widget: CGSize) -> CGSize {
        func axis(_ middle: CGFloat, _ length: CGFloat, _ limit: CGFloat) -> CGFloat {
            let inset = Self.edgeInset
            guard length <= limit - 2 * inset else { return limit / 2 - middle }
            let low = middle - length / 2, high = middle + length / 2
            if low < inset { return inset - low }
            if high > limit - inset { return limit - inset - high }
            return 0
        }
        return CGSize(width: axis(room.midX, drawn.width, widget.width), height: axis(room.midY, drawn.height, widget.height))
    }

    /// The least room between a button and its widget's edge.
    static let edgeInset: CGFloat = 3

    /// Where the button is drawn, in the widget's points, for a symbol whose room is `room`.
    static func drawnFrame(of look: ButtonLook, points: CGFloat, room: CGRect, widget: CGSize) -> CGRect {
        let drawn = drawnSize(of: look, points: points, room: room.size)
        let shift = shift(room: room, drawn: drawn, widget: widget)
        return CGRect(x: room.midX + shift.width - drawn.width / 2, y: room.midY + shift.height - drawn.height / 2,
                      width: drawn.width, height: drawn.height)
    }

    /// The button's size for a symbol of `points`, at the look's size: about as large as the symbol
    /// alone was (a circle, or a capsule wider and lower), its symbol drawn smaller inside
    /// (`shapedIcon`) — so a shape changes the button's look, not how much of the widget it takes.
    static func size(of look: ButtonLook, points: CGFloat) -> CGSize {
        let base = look.shape == .circle ? CGSize(width: points * 1.35, height: points * 1.35)
            : CGSize(width: points * 1.7, height: points * 1.2)
        return CGSize(width: (base.width * look.size).rounded(), height: (base.height * look.size).rounded())
    }

    /// A symbol on a shape, as a share of its size alone: small enough to sit inside it. Back and
    /// forward, a circle with its seconds inside, fill it more: smaller, the seconds cannot be read.
    static let shapedIcon = 0.6
    static let shapedSeekIcon = 0.8

    /// The symbol's size as drawn, as a share of the plain one's.
    static func iconScale(of look: ButtonLook, symbol: String) -> Double {
        let shaped = DrawnSymbol(symbol: symbol)?.isSeek == true ? shapedSeekIcon : shapedIcon
        return look.iconScale * (look.material.hasShape ? shaped : 1)
    }

    static func shape(of look: ButtonLook, size: CGSize) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: look.corners.radius(height: size.height), style: .continuous)
    }

    // MARK: The symbol

    /// Sized by the look over its own room (a larger symbol takes no more of the widget): drawn at
    /// that size, not scaled after, so its details stay sharp.
    private var scaledIcon: some View {
        icon(points: points * CGFloat(Self.iconScale(of: look, symbol: symbol)))
    }

    @ViewBuilder private func icon(points: CGFloat) -> some View {
        if let drawn = DrawnSymbol(symbol: symbol) {
            drawn.view(points: points, edges: look.iconEdges,
                      style: look.iconFill == .none ? AnyShapeStyle(Self.outline) : iconStyle, outlined: look.iconFill == .none)
        } else if look.iconEdges == .sharp, let glyph = MediaGlyph(symbol: symbol) {
            let size = glyph.size(points: points)
            Group {
                if look.iconFill == .none {
                    glyph.stroke(Self.outline, lineWidth: max(1, points / 14))
                } else {
                    glyph.fill(iconStyle)
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            Image(systemName: look.iconFill == .none ? Self.outlined(symbol) : symbol)
                .font(.system(size: points))
                .foregroundStyle(look.iconFill == .none ? AnyShapeStyle(Self.outline) : iconStyle)
        }
    }

    private var iconStyle: AnyShapeStyle {
        switch look.iconFill {
        case .automatic, .none: AnyShapeStyle(.primary)
        case .colour: AnyShapeStyle((look.iconColor ?? model.preferences.theme.rgb).color)
        case .artwork: AnyShapeStyle(artworkColor)
        }
    }

    /// The faint grey of an outline (a symbol with no fill, a button with none).
    static let outline = Color.white.opacity(0.42)

    /// The symbol's outline variant: `play.fill` → `play`.
    static func outlined(_ symbol: String) -> String {
        symbol.hasSuffix(".fill") ? String(symbol.dropLast(".fill".count)) : symbol
    }

    private var artworkColor: Color {
        model.media.artworkColor.map { Color($0) } ?? .islandAccent
    }

    // MARK: The shape behind it

    private func surface(_ shape: RoundedRectangle) -> some View {
        LookSurface(material: look.material, fill: look.fill, fillColor: look.fillColor, shape: shape)
    }
}

/// What is behind a part as its look sets it — a button's shape (`ButtonLook`), a ruler's
/// background (`RulerLook`): an opaque fill (Solid) or Liquid Glass tinted by it, or with no fill a
/// faint grey edge alone.
struct LookSurface: View {
    let material: ButtonLook.Material
    let fill: ButtonLook.Fill
    let fillColor: IslandTheme.RGB?
    let shape: RoundedRectangle

    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.drawsWidgetSurface) private var drawsSurface
    @Environment(AppModel.self) private var model

    var body: some View {
        if fill == .none {
            shape.strokeBorder(WidgetButtonLabel.outline.opacity(0.7), lineWidth: 1)
        } else if material == .glass {
            glass
        } else {
            shape.fill(color(solid: true))
        }
    }

    /// The system's Liquid Glass in its clear variant, tinted by the fill (lightly: it stays
    /// see-through) — on the island and in Customize's editor alike. A drawing of
    /// it only in the gallery's pictures, where glass keeps backdrop buffers for nothing, and where
    /// the editor reads where the parts are drawn (glass draws nothing in a picture).
    @ViewBuilder private var glass: some View {
        if (isPreview && renderMode != .canvas) || !drawsSurface {
            shape.fill(color(solid: false))
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.08)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
        } else {
            let tint: Color? = switch fill {
            case .plate, .none: nil
            case .colour: (fillColor ?? model.preferences.theme.rgb).color.opacity(Self.glassTint)
            case .artwork: artworkColor.opacity(Self.glassTint)
            }
            // The clear variant: see-through, coloured only by its tint.
            Color.clear.glassEffect(Glass.clear.tint(tint).interactive(), in: shape)
        }
    }

    /// How strongly a colour tints glass: enough to show the colour, little enough to stay clear.
    static let glassTint = 0.22

    private var artworkColor: Color {
        model.media.artworkColor.map { Color($0) } ?? .islandAccent
    }

    /// The fill: opaque on a solid surface, see-through as glass tints it on a glass one.
    private func color(solid: Bool) -> Color {
        switch fill {
        case .plate: solid ? Color(white: 0.26) : .white.opacity(0.06)
        case .colour: (fillColor ?? model.preferences.theme.rgb).color.opacity(solid ? 1 : Self.glassTint)
        case .artwork: artworkColor.opacity(solid ? 1 : Self.glassTint)
        case .none: .clear
        }
    }
}

/// The media symbols drawn as shapes, so their corners can be sharp: play, pause, previous and
/// next. Each fills its frame (`size(points:)`), as wide and tall as the system's symbol about.
nonisolated enum MediaGlyph: Shape {
    case play, pause, backward, forward

    init?(symbol: String) {
        switch symbol {
        case "play.fill", "play": self = .play
        case "pause.fill", "pause": self = .pause
        case "backward.fill", "backward": self = .backward
        case "forward.fill", "forward": self = .forward
        default: return nil
        }
    }

    /// Its frame for a symbol of `points`.
    func size(points: CGFloat) -> CGSize {
        switch self {
        case .play: CGSize(width: points * 0.8, height: points * 0.92)
        case .pause: CGSize(width: points * 0.72, height: points * 0.9)
        case .backward, .forward: CGSize(width: points * 1.1, height: points * 0.64)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch self {
        case .play:
            path.addLines([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                           CGPoint(x: rect.minX, y: rect.maxY)])
            path.closeSubpath()
        case .pause:
            let bar = rect.width * 0.36
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: bar, height: rect.height))
            path.addRect(CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height))
        case .forward, .backward:
            let half = rect.width / 2
            for start in [rect.minX, rect.minX + half] {
                let tip = self == .forward ? start + half : start
                let base = self == .forward ? start : start + half
                path.addLines([CGPoint(x: base, y: rect.minY), CGPoint(x: tip, y: rect.midY), CGPoint(x: base, y: rect.maxY)])
                path.closeSubpath()
            }
        }
        return path
    }
}

/// System symbols drawn by hand, so they stay sharp at any size and can have rounded or sharp
/// ends: back or forward by some seconds (`gobackward.15`), a turning arrow (`arrow.counterclockwise`),
/// Wi-Fi (`wifi`, `wifi.slash`) and the speaker (`speaker.wave.2.fill`, `speaker.slash.fill`) — and
/// the logos the system has no symbol for, by names of their own: Bluetooth's and AirDrop's. Each is
/// centred in its frame (`size(points:)`), about as large as the system's symbol.
nonisolated enum DrawnSymbol: Equatable {
    case seek(back: Bool, seconds: Int)
    case turn(back: Bool)
    case wifi(on: Bool)
    /// 0…3 waves; muted: struck through.
    case speaker(waves: Int, muted: Bool)
    /// The joined runes ᚼ and ᛒ.
    case bluetooth
    /// Three rings open at the bottom.
    case airDrop

    /// The logos' names, standing in for a system symbol's wherever a button's symbol is named.
    static let bluetoothName = "notchisland.bluetooth"
    static let airDropName = "notchisland.airdrop"

    /// A name only `DrawnSymbol` draws: the system has no symbol by it.
    static func isOwn(_ symbol: String) -> Bool { symbol == bluetoothName || symbol == airDropName }

    init?(symbol: String) {
        let name = symbol.hasSuffix(".fill") ? String(symbol.dropLast(".fill".count)) : symbol
        switch name {
        case Self.bluetoothName: self = .bluetooth
        case Self.airDropName: self = .airDrop
        case "arrow.counterclockwise": self = .turn(back: true)
        case "arrow.clockwise": self = .turn(back: false)
        case "wifi": self = .wifi(on: true)
        case "wifi.slash": self = .wifi(on: false)
        case "speaker": self = .speaker(waves: 0, muted: false)
        case "speaker.slash": self = .speaker(waves: 0, muted: true)
        case "speaker.wave.1": self = .speaker(waves: 1, muted: false)
        case "speaker.wave.2": self = .speaker(waves: 2, muted: false)
        case "speaker.wave.3": self = .speaker(waves: 3, muted: false)
        default:
            let back = name.hasPrefix("gobackward."), forward = name.hasPrefix("goforward.")
            guard back || forward, let seconds = Int(name.split(separator: ".").last ?? "") else { return nil }
            self = .seek(back: back, seconds: seconds)
        }
    }

    /// Back or forward, a circle with its seconds: it fills a button's shape more than other symbols.
    var isSeek: Bool { if case .seek = self { true } else { false } }

    /// Its frame for a symbol of `points`.
    func size(points: CGFloat) -> CGSize {
        switch self {
        case .seek: CGSize(width: points * 1.08, height: points * 1.08)
        case .turn: CGSize(width: points, height: points)
        case .wifi: CGSize(width: points * 1.25, height: points * 0.95)
        case .speaker: CGSize(width: points * 1.45, height: points)
        case .bluetooth: CGSize(width: points * 0.62, height: points * 1.1)
        case .airDrop: CGSize(width: points * 1.1, height: points * 1.1)
        }
    }

    @MainActor func view(points: CGFloat, edges: ButtonLook.IconEdges, style: AnyShapeStyle, outlined: Bool) -> some View {
        let frame = size(points: points)
        let rounded = edges == .rounded
        let line = max(1, min(frame.width, frame.height) * (isSeek ? 0.085 : 0.1))
        let stroke = StrokeStyle(lineWidth: line, lineCap: rounded ? .round : .butt, lineJoin: rounded ? .round : .miter)
        return ZStack {
            switch self {
            case .seek(let back, let seconds):
                SymbolArc(back: back).stroke(style, style: stroke)
                SymbolArrowHead(back: back).fill(style)
                    .overlay { if rounded { SymbolArrowHead(back: back).stroke(style, style: StrokeStyle(lineWidth: line * 0.5, lineJoin: .round)) } }
                Text(verbatim: String(seconds))
                    .font(.system(size: frame.width * (seconds >= 100 ? 0.28 : 0.36), weight: .semibold,
                                  design: rounded ? .rounded : .default))
                    .monospacedDigit()
                    .foregroundStyle(style)
                    .opacity(outlined ? 0.9 : 1)
            case .turn(let back):
                SymbolArc(back: back).stroke(style, style: stroke)
                SymbolArrowHead(back: back).fill(style)
                    .overlay { if rounded { SymbolArrowHead(back: back).stroke(style, style: StrokeStyle(lineWidth: line * 0.5, lineJoin: .round)) } }
            case .wifi(let on):
                WifiShape(rings: 3, dot: false).stroke(style, style: StrokeStyle(lineWidth: line * 0.95, lineCap: rounded ? .round : .butt))
                // The point stroked as the rings are: filled, it showed faint over glass (`.primary`).
                WifiShape(rings: 0, dot: true).stroke(style, lineWidth: WifiShape.dotRadius(in: frame))
                if !on { Slash().stroke(style, style: StrokeStyle(lineWidth: line * 1.1, lineCap: rounded ? .round : .butt)) }
            case .speaker(let waves, let muted):
                SpeakerBody(rounded: rounded).fill(style)
                    .overlay { if rounded { SpeakerBody(rounded: true).stroke(style, style: StrokeStyle(lineWidth: line * 0.4, lineJoin: .round)) } }
                SpeakerWaves(count: muted ? 0 : waves).stroke(style, style: stroke)
                if muted { Slash().stroke(style, style: StrokeStyle(lineWidth: line, lineCap: rounded ? .round : .butt)) }
            case .bluetooth:
                BluetoothLogo().stroke(style, style: StrokeStyle(lineWidth: max(1.2, points * 0.13), lineCap: rounded ? .round : .butt,
                                                                 lineJoin: rounded ? .round : .miter))
            case .airDrop:
                AirDropLogo().stroke(style, style: StrokeStyle(lineWidth: max(1.2, points * 0.11), lineCap: rounded ? .round : .butt))
            }
        }
        .frame(width: frame.width, height: frame.height)
    }
}

/// The open circle: from its arrow at the top round to just short of it.
nonisolated private struct SymbolArc: Shape {
    let back: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.4
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(-90),
                    endAngle: .degrees(back ? -140 : -40), clockwise: !back)
        return path
    }
}

/// The arrow at the top of the circle, pointing the way it turns (left for back).
nonisolated private struct SymbolArrowHead: Shape {
    let back: Bool

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let top = CGPoint(x: rect.midX, y: rect.midY - side * 0.4)
        let length = side * 0.2, half = side * 0.15
        let direction: CGFloat = back ? -1 : 1
        var path = Path()
        path.addLines([CGPoint(x: top.x + direction * length * 0.75, y: top.y),
                       CGPoint(x: top.x - direction * length * 0.25, y: top.y - half),
                       CGPoint(x: top.x - direction * length * 0.25, y: top.y + half)])
        path.closeSubpath()
        return path
    }
}

/// Wi-Fi's rings about a point at the bottom middle (`dot`: the point itself, filled).
nonisolated private struct WifiShape: Shape {
    let rings: Int
    let dot: Bool

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.12)
        let largest = min(rect.width / 2, rect.height * 0.85)
        var path = Path()
        for ring in 0..<rings {
            // Each ring by itself (an arc joins the last point with a line).
            let radius = largest * (0.92 - CGFloat(ring) * 0.3)
            let start = Angle.degrees(-135)
            path.move(to: CGPoint(x: centre.x + radius * cos(start.radians), y: centre.y + radius * sin(start.radians)))
            path.addArc(center: centre, radius: radius, startAngle: start, endAngle: .degrees(-45), clockwise: false)
        }
        if dot, rings == 0 {
            // A circle half as large, stroked as wide as that half (`dotRadius`): the whole point.
            let radius = Self.dotRadius(in: rect.size) / 2
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
        }
        return path
    }

    /// The point's radius in a frame `size` large.
    static func dotRadius(in size: CGSize) -> CGFloat {
        min(size.width / 2, size.height * 0.85) * 0.13
    }
}

/// The Bluetooth logo (the joined runes ᚼ and ᛒ): a stem with two arrowheads on its right and the
/// two crossing strokes on its left, drawn to be stroked.
nonisolated private struct BluetoothLogo: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0, 0.27))
        path.addLine(to: point(1, 0.73))
        path.addLine(to: point(0.5, 1))
        path.addLine(to: point(0.5, 0))
        path.addLine(to: point(1, 0.27))
        path.addLine(to: point(0, 0.73))
        return path
    }
}

/// The AirDrop logo: three concentric rings, open at the bottom, drawn to be stroked.
nonisolated private struct AirDropLogo: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        // Open by 70° around the bottom (90° is straight down in SwiftUI's flipped space).
        let start = Angle.degrees(125)
        for radius in [outer, outer * 0.66, outer * 0.32] {
            // Each ring its own subpath: `addArc` would otherwise join it to the previous one.
            path.move(to: CGPoint(x: center.x + radius * cos(start.radians), y: center.y + radius * sin(start.radians)))
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: .degrees(55), clockwise: false)
        }
        return path
    }
}

/// A stroke from the top left to the bottom right (a switch off, a speaker muted).
nonisolated private struct Slash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.05))
        return path
    }
}

/// The speaker: a small box and its cone, on the left of its frame.
nonisolated private struct SpeakerBody: Shape {
    let rounded: Bool

    func path(in rect: CGRect) -> Path {
        let height = rect.height, left = rect.minX
        let box = CGRect(x: left, y: rect.midY - height * 0.18, width: height * 0.26, height: height * 0.36)
        var path = Path(roundedRect: box, cornerRadius: rounded ? height * 0.05 : 0)
        path.move(to: CGPoint(x: box.maxX - 0.5, y: box.minY))
        path.addLine(to: CGPoint(x: left + height * 0.62, y: rect.midY - height * 0.42))
        path.addLine(to: CGPoint(x: left + height * 0.62, y: rect.midY + height * 0.42))
        path.addLine(to: CGPoint(x: box.maxX - 0.5, y: box.maxY))
        path.closeSubpath()
        return path
    }
}

/// The waves in front of the speaker, `count` of three.
nonisolated private struct SpeakerWaves: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        let height = rect.height
        let centre = CGPoint(x: rect.minX + height * 0.5, y: rect.midY)
        var path = Path()
        for wave in 0..<min(max(count, 0), 3) {
            let radius = height * (0.3 + CGFloat(wave) * 0.19)
            let start = Angle.degrees(-42)
            path.move(to: CGPoint(x: centre.x + radius * cos(start.radians), y: centre.y + radius * sin(start.radians)))
            path.addArc(center: centre, radius: radius, startAngle: .degrees(-42), endAngle: .degrees(42), clockwise: false)
        }
        return path
    }
}

/// A button's symbol by its name, as a header or a list shows it: drawn by hand where the system
/// has none (`DrawnSymbol.isOwn`), else the system's.
struct ButtonSymbolImage: View {
    let symbol: String
    let points: CGFloat

    var body: some View {
        if DrawnSymbol.isOwn(symbol), let drawn = DrawnSymbol(symbol: symbol) {
            drawn.view(points: points, edges: .rounded, style: AnyShapeStyle(.foreground), outlined: false)
        } else {
            Image(systemName: symbol).font(.system(size: points))
        }
    }
}
