import SwiftUI

/// A horizontal ruler of one unit (minutes, or hours or seconds) under a fixed centre marker, like
/// the iPhone's Dynamic Island timer: scroll it (trackpad or wheel) or drag it (mouse) to set it.
///
/// It is a real scroll view, so the trackpad gets native momentum and the ruler settles on a whole
/// minute (`viewAligned`). Minutes up to the selection are drawn in full orange, the rest dimmed,
/// and the ruler fades out towards both ends.
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
                .id(unit)
                .transition(.identity)
                // The scale alone: the unit's name under it keeps what it draws below its line
                // (an underline) and where it is moved.
                .clipped()
            marker
        }
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

    private func clamp(_ value: Int) -> Int {
        min(max(value, max(range.lowerBound, minimum)), range.upperBound)
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

/// The scrolling scale of one unit. It starts on its value: set on appear it first drew at 0 and
/// then jumped there.
///
/// The value is read from the scroll offset (a tick per `tickSpacing`) while the user scrolls,
/// not from the scroll position's id: that id lagged and jumped during a fast swipe (a lazy stack
/// reports whichever of its views it has laid out), and the ruler then pushed the scroll back
/// while the finger was still on it — the value stuck for a few ticks and so did the haptics.
/// Values below `minimum` are drawn as landmarks beside the scale, not as scroll targets, so the
/// ruler ends there with the system's own rubber band instead of being scrolled back.
private struct RulerTrack: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let minimum: Int
    let isEditable: Bool
    let showsLabels: Bool
    let tint: Color
    let ends: ButtonLook.Corners
    let onInteraction: (Bool) -> Void

    @State private var scrolled: Int?
    @State private var dragStart: Int?
    @State private var phase: ScrollPhase = .idle

    init(minutes: Binding<Int>, range: ClosedRange<Int>, minimum: Int, isEditable: Bool, showsLabels: Bool,
         tint: Color, ends: ButtonLook.Corners, onInteraction: @escaping (Bool) -> Void) {
        _minutes = minutes
        self.range = range
        self.minimum = minimum
        self.isEditable = isEditable
        self.showsLabels = showsLabels
        self.tint = tint
        self.ends = ends
        self.onInteraction = onInteraction
        _scrolled = State(initialValue: minutes.wrappedValue)
    }

    /// The first value the ruler can settle on. A ruler that only shows a value (a running
    /// countdown) reaches 0.
    private var first: Int { isEditable ? min(max(range.lowerBound, minimum), range.upperBound) : range.lowerBound }

    /// The user's own finger or momentum is moving the ruler (not an animation of ours).
    private var isUserScrolling: Bool {
        phase == .tracking || phase == .interacting || phase == .decelerating
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = TimerRuler.tickSpacing
            let margin = max(0, proxy.size.width / 2 - spacing / 2)
            let landmarks = Array(range.lowerBound..<first)
            ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(first...range.upperBound, id: \.self) { minute in
                        Tick(minute: minute, isPast: minute > minutes, showsLabel: showsLabels, tint: tint, ends: ends)
                            .frame(width: spacing)
                            .id(minute)
                    }
                }
                .scrollTargetLayout()
                .overlay(alignment: .leading) {
                    if !landmarks.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(landmarks, id: \.self) { minute in
                                Tick(minute: minute, isPast: minute > minutes, showsLabel: showsLabels, tint: tint, ends: ends)
                                    .frame(width: spacing)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: -CGFloat(landmarks.count) * spacing)
                    }
                }
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollPosition(id: $scrolled, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.never)
            .scrollDisabled(!isEditable)
            .onScrollPhaseChange { _, new in
                phase = new
                onInteraction(new != .idle)
                // Settled: the tick under the marker is the value.
                if new == .idle, let scrolled { commit(scrolled) }
            }
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int(((geometry.contentOffset.x + geometry.contentInsets.leading) / spacing).rounded())
            } action: { _, index in
                if isUserScrolling {
                    commit(first + index)
                } else if phase == .idle, dragStart == nil, first + index != target {
                    // At rest off its value (the layout moved the content): back onto it at once.
                    reader.scrollTo(target, anchor: .center)
                }
            }
            // The mouse has no scroll gesture of its own: a drag moves the ruler a minute per tick.
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard isEditable else { return }
                        if dragStart == nil {
                            dragStart = minutes
                            onInteraction(true)
                        }
                        let offset = Int((value.translation.width / spacing).rounded())
                        let target = clamp((dragStart ?? minutes) - offset)
                        if target != scrolled { scrolled = target }
                        commit(target)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onInteraction(false)
                    }
            )
            // On its value from the first frame, and again while the island grows around it: the
            // scroll view drops its initial position when its width changes (it then sat on the
            // first tick under a readout saying 9:00, and the first swipe started from there).
            .onAppear { align(reader) }
            .onChange(of: proxy.size.width) { align(reader) }
            }
        }
        .mask {
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
        .onChange(of: minutes) { _, new in
            // Set from elsewhere (a unit switch, a reset, the running countdown): scroll there. Not
            // while the user moves the ruler — that is where the value came from.
            guard !isUserScrolling, dragStart == nil else { return }
            let target = isEditable ? clamp(new) : min(max(new, range.lowerBound), range.upperBound)
            if scrolled != target { withAnimation(Motion.content) { scrolled = target } }
        }
    }

    /// Where the ruler rests: on the value.
    private var target: Int { isEditable ? clamp(minutes) : min(max(minutes, range.lowerBound), range.upperBound) }

    private func align(_ reader: ScrollViewProxy) {
        guard !isUserScrolling, dragStart == nil else { return }
        let target = target
        reader.scrollTo(target, anchor: .center)
        scrolled = target
    }

    private func commit(_ value: Int) {
        guard isEditable else { return }
        let value = clamp(value)
        if value != minutes { minutes = value }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, first), range.upperBound)
    }
}

private struct Tick: View {
    let minute: Int
    let isPast: Bool
    let showsLabel: Bool
    let tint: Color
    let ends: ButtonLook.Corners

    static let labelFont = Font.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()
    /// The label line's height (10-pt rounded semibold), so unlabelled ticks line up.
    nonisolated static let labelHeight = ceil(NSFont.systemFont(ofSize: 10, weight: .semibold).boundingRectForFont.height)

    var body: some View {
        let major = minute % 5 == 0
        let style = tint.opacity(isPast ? 0.35 : 1)
        VStack(spacing: Self.labelGap) {
            if showsLabel {
                // Text only on the labelled minutes: an empty label is still a text to resolve and
                // lay out, and the ruler has dozens on screen, all updated on every frame of the
                // island's growth.
                Group {
                    if major {
                        TickLabel(minute: minute, isPast: isPast, tint: tint)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: TimerRuler.tickSpacing, height: Self.labelHeight)
            }
            RoundedRectangle(cornerRadius: ends.radius(height: Self.width), style: .continuous)
                .fill(style)
                .frame(width: Self.width)
                .frame(maxHeight: .infinity)
                .padding(.vertical, major ? 0 : Self.minorInset)
        }
    }

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

/// The scale as a picture until the pointer comes over it (or it moves): the real scroll view —
/// a platform scroll view with dozens of ticks, aligned to its value as it appears — was over half
/// of the timer widget's cost on every opening of the island (measured). At rest the two draw the
/// same pixels; a running countdown, which glides every second, keeps the scroll view.
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
                RulerTrack(minutes: $minutes, range: range, minimum: minimum, isEditable: isEditable,
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

/// The resting scale: the same ticks where the scroll view puts them with the value centred, with
/// the same fade at both ends — no scroll view to build and align, and no `Tick` stack per minute:
/// each tick is its bare capsule and only the fifth minutes' numbers are drawn, each placed where
/// its `Tick` lays it out (`restingRulerDrawsItsTicksAsTheirViewsDo`). About a third of the timer
/// widget's cost on every opening of the panel (measured).
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
        .allowsHitTesting(true)
        .contentShape(.rect)
    }
}

/// Where the resting scale's `Tick` stacks put a minute's column and its capsule: centred in its
/// column, under the label line, a minute that is not a fifth inset at both ends. Left unrounded:
/// SwiftUI puts the capsule on whole pixels where it put the stack's.
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
