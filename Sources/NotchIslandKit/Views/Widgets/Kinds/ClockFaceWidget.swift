import SwiftUI

/// The clock face, the base of a dial: twelve ticks, the hour and minute hands and, switched on,
/// the seconds hand, here or in the city set in Customize. The caption (the city, or the user's
/// own) goes under the dial where the widget is tall enough, beside it where it is wide. Shapes
/// only, drawn once a minute (once a second with the seconds hand), only while shown.
///
/// The dial is moved and sized in Customize as a part of its own (its look comes later), the
/// caption as a text (`WidgetLabel`).
struct ClockFaceWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.timeZone) private var here

    static func zone(_ config: WidgetConfig, here: TimeZone) -> TimeZone {
        config.timeZone.flatMap(TimeZone.init(identifier:)) ?? here
    }

    /// The user's caption, else the city's name.
    static func caption(_ config: WidgetConfig, here: TimeZone) -> String {
        config.label ?? WorldClockWidget.city(zone(config, here: here))
    }

    static func captionPoints(inner: CGSize) -> CGFloat {
        WidgetMetrics.points(min(inner.width, inner.height), ratio: 0.12, min: 9, max: 13)
    }

    /// Where the caption goes: under the dial (tall), beside it (wide), or nowhere.
    nonisolated enum CaptionPlace: Equatable {
        case under, beside, none
    }

    static func captionPlace(_ widget: IslandWidget, inner: CGSize) -> CaptionPlace {
        guard widget.shows(.label) else { return .none }
        if inner.height >= 70, inner.width < inner.height * 1.8 { return .under }
        if inner.width >= inner.height * 1.8 { return .beside }
        return .none
    }

    /// The dial's diameter, with the caption's room taken out.
    static func diameter(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        let caption = (captionPoints(inner: inner) * 1.3).rounded(.up) + 2
        return switch captionPlace(widget, inner: inner) {
        case .under: max(min(inner.width, inner.height - caption), 8)
        case .beside: max(min(inner.height, inner.width * 0.5), 8)
        case .none: max(min(inner.width, inner.height), 8)
        }
    }

    var body: some View {
        let seconds = widget.shows(.secondsHand)
        Group {
            if let fixedDate {
                content(fixedDate)
            } else if seconds {
                PanelTimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { content($0.date) }
            } else {
                PanelTimelineView(.everyMinute) { content($0.date) }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Clock"))
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let diameter = Self.diameter(widget, inner: size)
        let zone = Self.zone(widget.config, here: here)
        let face = ClockFaceButton(date: date, zone: zone, showsSeconds: widget.shows(.secondsHand), diameter: diameter,
                                   look: widget.buttonLook(of: .face))
            .frame(width: diameter, height: diameter)
            .movableElement(.face, of: widget)
        let points = Self.captionPoints(inner: size)
        let text = Self.caption(widget.config, here: here)
        let caption = WidgetLabel(id: .label, text: text, widget: widget, size: points, weight: .medium, isSecondary: true) {
            Text(text)
                .font(.system(size: points, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .movableElement(.label, of: widget)
        switch Self.captionPlace(widget, inner: size) {
        case .under:
            VStack(spacing: 2) {
                face
                caption
            }
        case .beside:
            HStack(spacing: 8) {
                face
                caption
                Spacer(minLength: 0)
            }
        case .none:
            face
        }
    }
}

/// The dial as a button (`ButtonLook`, set in Customize as every button is): unstyled, the dial as
/// the widget draws it; restyled, on the shape its look makes — Solid or Liquid Glass, its shape,
/// corners, fill and size — the dial being its symbol: as large and as far from the middle as the
/// symbol is set, its hands in the symbol's colour, with sharp ends where its edges are sharp.
struct ClockFaceButton: View {
    let date: Date
    let zone: TimeZone
    let showsSeconds: Bool
    let diameter: CGFloat
    let look: ButtonLook

    @Environment(\.widgetLayerPass) private var layerPass
    @Environment(AppModel.self) private var model

    /// Its symbol's size, as a restyled button's is worked out: its shape as large as the dial;
    /// without a shape, the dial's own.
    static func points(diameter: CGFloat, look: ButtonLook) -> CGFloat {
        look.material.hasShape ? (diameter / 1.35).rounded() : diameter
    }

    /// The dial's diameter on a button of `points`: as large as a symbol of those points is drawn
    /// (`WidgetButtonLabel.iconScale`), so it fills the box Customize's Symbol panel shows.
    static func dial(look: ButtonLook, points: CGFloat) -> CGFloat {
        max(points * CGFloat(WidgetButtonLabel.iconScale(of: look, symbol: "clock")), 4)
    }

    var body: some View {
        if look == .plain {
            ClockDial(date: date, zone: zone, showsSeconds: showsSeconds, diameter: diameter)
        } else {
            let shaped = look.material.hasShape
            let points = Self.points(diameter: diameter, look: look)
            let shape = shaped ? WidgetButtonLabel.size(of: look, points: points) : CGSize(width: diameter, height: diameter)
            // On a shape, the dial inside it (its face is the shape); alone, as large as it was.
            let dial = Self.dial(look: look, points: points)
            ZStack {
                if shaped, layerPass == .all || (layerPass == .underlay) == ButtonLook.isGlass(look) {
                    LookSurface(material: look.material, fill: look.fill, fillColor: look.fillColor,
                                shape: WidgetButtonLabel.shape(of: look, size: shape))
                        .frame(width: shape.width, height: shape.height)
                }
                ClockDial(date: date, zone: zone, showsSeconds: showsSeconds, diameter: dial, hands: hands,
                          drawsFace: !shaped, cap: look.iconEdges == .sharp ? .butt : .round)
                    .offset(x: look.iconOffset.x * shape.width, y: look.iconOffset.y * shape.height)
                    .opacity(layerPass == .underlay ? 0 : 1)
            }
            .frame(width: diameter, height: diameter)
        }
    }

    /// The hands in the symbol's colour: white, a colour, the cover's, or a faint grey outline.
    private var hands: AnyShapeStyle {
        switch look.iconFill {
        case .automatic: AnyShapeStyle(.primary)
        case .colour: AnyShapeStyle((look.iconColor ?? model.preferences.theme.rgb).color)
        case .none: AnyShapeStyle(WidgetButtonLabel.outline)
        case .artwork: AnyShapeStyle(model.media.artworkColor.map { Color($0) } ?? .islandAccent)
        }
    }
}

/// The dial at `date` in `zone`: the hands where they point then.
struct ClockDial: View {
    let date: Date
    let zone: TimeZone
    let showsSeconds: Bool
    let diameter: CGFloat
    /// The hands' colour (the ticks in it, fainter).
    var hands = AnyShapeStyle(.primary)
    /// Its own faint face behind the hands (none on a button's shape).
    var drawsFace = true
    /// The hands' and ticks' ends.
    var cap: CGLineCap = .round

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        let _ = calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(parts.second ?? 0), minutes = Double(parts.minute ?? 0) + (showsSeconds ? seconds / 60 : 0)
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        let stroke = max(diameter * 0.045, 1.5)
        ZStack {
            if drawsFace { Circle().fill(.white.opacity(0.06)) }
            ClockTicks()
                .stroke(hands.opacity(0.45), style: StrokeStyle(lineWidth: max(diameter * 0.02, 1), lineCap: cap))
            ClockHand(length: 0.5)
                .stroke(hands, style: StrokeStyle(lineWidth: stroke * 1.25, lineCap: cap))
                .rotationEffect(.degrees(hours * 30))
            ClockHand(length: 0.78)
                .stroke(hands, style: StrokeStyle(lineWidth: stroke, lineCap: cap))
                .rotationEffect(.degrees(minutes * 6))
            if showsSeconds {
                ClockHand(length: 0.84)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: max(stroke * 0.45, 1), lineCap: cap))
                    .rotationEffect(.degrees(seconds * 6))
            }
            Circle()
                .fill(showsSeconds ? AnyShapeStyle(Color.orange) : hands)
                .frame(width: stroke * 2, height: stroke * 2)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// From the centre towards twelve, `length` of the radius.
private nonisolated struct ClockHand: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - rect.height / 2 * length))
        return path
    }
}

/// Twelve ticks, the quarters longer.
private nonisolated struct ClockTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        for tick in 0..<12 {
            let angle = Double(tick) * .pi / 6
            let inner = radius * (tick % 3 == 0 ? 0.8 : 0.88), outer = radius * 0.94
            path.move(to: CGPoint(x: rect.midX + sin(angle) * inner, y: rect.midY - cos(angle) * inner))
            path.addLine(to: CGPoint(x: rect.midX + sin(angle) * outer, y: rect.midY - cos(angle) * outer))
        }
        return path
    }
}
