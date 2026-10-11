import SwiftUI

/// A horizontal ruler of one unit (minutes, or hours or seconds) under a fixed centre marker, like
/// the iPhone's Dynamic Island timer: scroll it (trackpad or wheel) or drag it (mouse) to set it.
///
/// It is a real scroll view (`RulerScrollView`), so the trackpad gets native momentum and the ruler
/// settles on a whole minute. Minutes up to the selection are drawn in full orange, the rest
/// dimmed, and the ruler fades out towards both ends.
struct TimerRuler: View {
    /// The selected value; the ruler never settles below `minimum`.
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...120
    var minimum = 1
    var unit: TimerUnit = .minutes
    /// A click on the marker (or the unit's name beside it) moves on to the next unit (nil: none).
    var nextUnit: (() -> Void)?
    /// The unit's name beside the marker, as its text style sets it (nil: the marker alone).
    var unitName: RulerUnitName?
    /// While a timer runs the ruler shows the remaining minutes and cannot be moved.
    var isEditable = true
    var showsLabels = true
    var tint: Color = Self.tint
    /// The ticks' ends (`RulerLook.ends`).
    var ends: ButtonLook.Corners = .round
    /// Called when the user starts or ends moving it (keeps the island open meanwhile).
    var onInteraction: (Bool) -> Void = { _ in }
    /// The centre marker's size; short rulers (the smallest island sizes) use a smaller one so the
    /// ticks keep their height.
    var markerSize: CGFloat = 9
    /// The pointer is over what the ruler is in (its widget): the scroll view is ready before the
    /// fingers reach the ruler. A two-finger scroll begun on the resting picture was not the scroll
    /// view's (it takes a gesture from its start): the first swipe did nothing.
    var isAwake = false

    nonisolated static let tickSpacing: CGFloat = 8
    static let tint = Color.orange

    init(
        minutes: Binding<Int>,
        range: ClosedRange<Int> = 0...120,
        minimum: Int = 1,
        unit: TimerUnit = .minutes,
        nextUnit: (() -> Void)? = nil,
        unitName: RulerUnitName? = nil,
        isEditable: Bool = true,
        showsLabels: Bool = true,
        tint: Color = Self.tint,
        ends: ButtonLook.Corners = .round,
        onInteraction: @escaping (Bool) -> Void = { _ in },
        markerSize: CGFloat = 9,
        isAwake: Bool = false
    ) {
        _minutes = minutes
        self.range = range
        self.minimum = minimum
        self.unit = unit
        self.nextUnit = nextUnit
        self.unitName = unitName
        self.isEditable = isEditable
        self.showsLabels = showsLabels
        self.tint = tint
        self.ends = ends
        self.onInteraction = onInteraction
        self.markerSize = markerSize
        self.isAwake = isAwake
    }

    var body: some View {
        VStack(spacing: markerSize < 9 ? 1 : 2) {
            // A new scale per unit, at once (one fading in left the ruler blank a moment, its
            // numbers out of step with the time's), while the marker below stays put.
            RestingRulerTrack(minutes: $minutes, range: range, minimum: minimum, isEditable: isEditable,
                              showsLabels: showsLabels, tint: tint, ends: ends, isAwake: isAwake, onInteraction: onInteraction)
                // … and per range of it: minutes run to 59 with Set hours on and to 120 without, and
                // the scale is made anew when that changes, never the longer one kept.
                .id("\(unit)-\(range.lowerBound)-\(range.upperBound)")
                .transition(.identity)
                // The scale alone: the unit's name under it keeps what it draws below its line
                // (an underline) and where it is moved.
                .clipped()
            marker
        }
        .modifier(RulerAccessibility(minutes: $minutes, unit: unit, isEditable: isEditable,
                                     lowest: max(range.lowerBound, minimum), highest: range.upperBound))
    }

    /// The triangle exactly at the centre, over the selected tick; the unit's name beside it
    /// (changing in place), tappable to move on to the next unit.
    private var marker: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: unitName == nil ? markerSize : markerSize * 0.78))
            .foregroundStyle(tint)
            .overlay(alignment: .leading) {
                if let unitName {
                    unitName.label(unit.shortTitle, size: markerSize, tint: tint)
                        .transaction { $0.animation = nil }
                        .offset(x: markerSize * 1.1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { nextUnit?() }
            .help(nextUnit == nil ? "" : "Next unit")
            .accessibilityHidden(nextUnit == nil)
    }

}

/// The ruler to assistive apps: one element, its value read here and not in the ruler's body (it
/// changes at every tick of a swipe, and the body then built the scale and the marker again).
private struct RulerAccessibility: ViewModifier {
    @Binding var minutes: Int
    let unit: TimerUnit
    let isEditable: Bool
    let lowest: Int
    let highest: Int

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Timer length")
            .accessibilityValue("\(minutes) \(unit.accessibilityTitle)")
            .accessibilityAdjustableAction { direction in
                guard isEditable else { return }
                switch direction {
                case .increment: minutes = clamp(minutes + 1)
                case .decrement: minutes = clamp(minutes - 1)
                @unknown default: break
                }
            }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, lowest), highest)
    }
}

/// The unit's name beside the ruler's marker ("min", "sec", "hr") as its text style sets it: its
/// type (rounded where the style leaves the typeface at Default), its colour (the ruler's where
/// Automatic), its box (a width and height of its own, the letters shrunk to fit), and moved by
/// `offset`. With `reportsFrame` it tells Customize's panel where it is drawn (`RulerUnitFrameKey`).
struct RulerUnitName: Equatable {
    var style: TextStyle = .plain
    var offset: ElementOffset = .zero
    /// The colour where the style's is Automatic; nil: the ruler's.
    var color: Color?
    var reportsFrame = false

    /// Its own size beside a marker `markerSize` large.
    static func points(markerSize: CGFloat) -> CGFloat { markerSize }

    /// Medium: Bold makes it bold.
    static let weight = NSFont.Weight.medium

    func label(_ text: String, size: CGFloat, tint: Color) -> some View {
        var style = style
        if style.design == .standard { style.design = .rounded }
        let font = style.font(size: Self.points(markerSize: size), weight: Self.weight)
        let fill: Color = switch style.color {
        case .custom(let rgb): rgb.color
        default: color ?? tint
        }
        return Group {
            if let box = style.box {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(width: CGFloat(box.width), height: CGFloat(box.height), alignment: style.alignment.frameAlignment)
            } else {
                Text(text).fixedSize()
            }
        }
        .font(Font(font))
        .underline(style.isUnderlined)
        .strikethrough(style.isStruckThrough)
        .foregroundStyle(fill)
        .background {
            if reportsFrame {
                GeometryReader { proxy in
                    Color.clear.preference(key: RulerUnitFrameKey.self, value: proxy.frame(in: .named(RulerUnitFrameKey.space)))
                }
            }
        }
        .offset(x: offset.x, y: offset.y)
    }
}

/// Where the unit's name is drawn, in `space` (Customize's panel for the ruler).
struct RulerUnitFrameKey: PreferenceKey {
    static let space = "rulerParts"

    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// A tick of the scale: a capsule under a label line (a number on every fifth minute), a minute
/// that is not a fifth shorter at both ends. Drawn by `RulerPicture` at rest and by
/// `RulerScaleView` while the ruler is live, both from these.
enum Tick {
    static let labelFont = Font.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()
    /// The label line's height (10-pt rounded semibold), so unlabelled ticks line up.
    nonisolated static let labelHeight = ceil(NSFont.systemFont(ofSize: 10, weight: .semibold).boundingRectForFont.height)
    nonisolated static let width: CGFloat = 2.5
    /// Above and below a minute that is not a fifth: shorter than the labelled ones.
    nonisolated static let minorInset: CGFloat = 3
    /// Between the label line and the ticks.
    nonisolated static let labelGap: CGFloat = 3
}

/// A fifth minute's number over its tick.
private struct TickLabel: View {
    let minute: Int
    let isPast: Bool
    let tint: Color

    var body: some View {
        Text("\(minute)")
            .font(Tick.labelFont)
            .foregroundStyle(tint.opacity(isPast ? 0.4 : 0.9))
            .fixedSize()
    }
}

/// The scale as a picture until the pointer comes over it (or it moves), then the scroll view
/// (`RulerScale`). At rest the two draw the same pixels; a running countdown, which moves on
/// every minute, keeps the scroll view. (The picture is from when the scroll view was SwiftUI's:
/// that one was over half of the timer widget's cost on every opening of the island.)
private struct RestingRulerTrack: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let minimum: Int
    let isEditable: Bool
    let showsLabels: Bool
    let tint: Color
    let ends: ButtonLook.Corners
    let isAwake: Bool
    let onInteraction: (Bool) -> Void

    @State private var isHovered = false
    @State private var isInteracting = false

    var body: some View {
        let live = !isEditable || isHovered || isInteracting || isAwake
        ZStack {
            if live {
                LiveRulerTrack(minutes: $minutes, range: range, minimum: minimum, isEditable: isEditable,
                               showsLabels: showsLabels, tint: tint, ends: ends) { interacting in
                    isInteracting = interacting
                    onInteraction(interacting)
                }
            } else {
                RulerPicture(value: min(max(minutes, max(range.lowerBound, minimum)), range.upperBound),
                             range: range, showsLabels: showsLabels, tint: tint, ends: ends)
            }
        }
        .onHover { isHovered = $0 }
    }
}

/// The live scale (`RulerScale`) on its value. A view of its own: it alone reads the value while
/// the ruler moves (the views around it are not built again at every tick).
private struct LiveRulerTrack: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let minimum: Int
    let isEditable: Bool
    let showsLabels: Bool
    let tint: Color
    let ends: ButtonLook.Corners
    let onInteraction: (Bool) -> Void

    var body: some View {
        RulerScale(value: minutes, range: range,
                   first: isEditable ? min(max(range.lowerBound, minimum), range.upperBound) : range.lowerBound,
                   isEditable: isEditable, showsLabels: showsLabels, tint: tint, ends: ends) { value in
            if value != minutes { minutes = value }
        } onInteraction: { interacting in
            onInteraction(interacting)
        }
        .mask { RulerFade() }
    }
}

/// The resting scale: the same ticks where the scroll view puts them with the value centred, with
/// the same fade at both ends — no scroll view to build and align: each tick is its bare capsule
/// and only the fifth minutes' numbers are drawn. About a third of the timer widget's cost on
/// every opening of the panel (measured).
struct RulerPicture: View {
    let value: Int
    let range: ClosedRange<Int>
    let showsLabels: Bool
    let tint: Color
    var ends: ButtonLook.Corners = .round

    var body: some View {
        GeometryReader { proxy in
            let spacing = TimerRuler.tickSpacing
            let centre = proxy.size.width / 2
            let reach = Int(ceil(centre / spacing)) + 1
            let minutes = max(range.lowerBound, value - reach)...min(range.upperBound, value + reach)
            let columns = TickColumns(value: value, centre: centre, showsLabels: showsLabels)
            ZStack(alignment: .topLeading) {
                ForEach(minutes, id: \.self) { minute in
                    let rect = columns.capsule(minute, height: proxy.size.height)
                    RoundedRectangle(cornerRadius: ends.radius(height: Tick.width), style: .continuous)
                        .fill(tint.opacity(minute > value ? 0.35 : 1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                if showsLabels {
                    ForEach(minutes.filter { $0 % 5 == 0 }, id: \.self) { minute in
                        TickLabel(minute: minute, isPast: minute > value, tint: tint)
                            .frame(width: spacing, height: Tick.labelHeight)
                            .offset(x: columns.left(minute))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .mask {
            RulerFade()
        }
        .allowsHitTesting(true)
        .contentShape(.rect)
    }
}

/// A minute's column and its capsule in the resting scale: centred in its column, under the label
/// line, a minute that is not a fifth inset at both ends. Left unrounded: SwiftUI puts the capsule
/// on whole pixels (`RulerScaleView` does the same for its layers).
private nonisolated struct TickColumns {
    let value: Int
    let centre: CGFloat
    let showsLabels: Bool

    /// The left edge of a minute's column.
    func left(_ minute: Int) -> CGFloat {
        centre + CGFloat(minute - value) * TimerRuler.tickSpacing - TimerRuler.tickSpacing / 2
    }

    /// A minute's capsule in a scale `height` tall.
    func capsule(_ minute: Int, height: CGFloat) -> CGRect {
        let top = showsLabels ? Tick.labelHeight + Tick.labelGap : 0
        let inset = minute % 5 == 0 ? 0 : Tick.minorInset
        return CGRect(x: left(minute) + (TimerRuler.tickSpacing - Tick.width) / 2, y: top + inset,
                      width: Tick.width, height: max(0, height - top - 2 * inset))
    }
}

/// The scale fades out towards both ends.
private struct RulerFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
