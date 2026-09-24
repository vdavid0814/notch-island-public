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
    /// Under the marker: the unit's name, as a button that moves on to the next unit (nil: the
    /// plain marker).
    var nextUnit: (() -> Void)?
    /// While a timer runs the ruler shows the remaining minutes and cannot be moved.
    var isEditable = true
    var showsLabels = true
    var tint: Color = Self.tint
    /// Called when the user starts or ends moving it (keeps the island open meanwhile).
    var onInteraction: (Bool) -> Void = { _ in }
    /// The centre marker's size; short rulers (the smallest island sizes) use a smaller one so the
    /// ticks keep their height.
    var markerSize: CGFloat = 9

    static let tickSpacing: CGFloat = 8
    static let tint = Color.orange

    init(
        minutes: Binding<Int>,
        range: ClosedRange<Int> = 0...120,
        minimum: Int = 1,
        unit: TimerUnit = .minutes,
        nextUnit: (() -> Void)? = nil,
        isEditable: Bool = true,
        showsLabels: Bool = true,
        tint: Color = Self.tint,
        onInteraction: @escaping (Bool) -> Void = { _ in },
        markerSize: CGFloat = 9
    ) {
        _minutes = minutes
        self.range = range
        self.minimum = minimum
        self.unit = unit
        self.nextUnit = nextUnit
        self.isEditable = isEditable
        self.showsLabels = showsLabels
        self.tint = tint
        self.onInteraction = onInteraction
        self.markerSize = markerSize
    }

    var body: some View {
        VStack(spacing: markerSize < 9 ? 1 : 2) {
            // A new scale per unit: it cross-fades in on its own value while the marker below
            // stays put (the whole ruler used to swap, so two markers slid across each other).
            RulerTrack(minutes: $minutes, range: range, minimum: minimum, isEditable: isEditable,
                       showsLabels: showsLabels, tint: tint, onInteraction: onInteraction)
                .id(unit)
                // The old scale goes at once and the new one fades in: two scales cross-fading
                // showed a double row of ticks.
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .identity
                ))
            marker
        }
        .clipped()
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
            .font(.system(size: nextUnit == nil ? markerSize : markerSize * 0.78))
            .foregroundStyle(tint)
            .overlay(alignment: .leading) {
                if nextUnit != nil {
                    Text(unit.shortTitle)
                        .font(.system(size: markerSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .fixedSize()
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

/// The scrolling scale of one unit. It starts on its value: set on appear it first drew at 0 and
/// then jumped there.
private struct RulerTrack: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let minimum: Int
    let isEditable: Bool
    let showsLabels: Bool
    let tint: Color
    let onInteraction: (Bool) -> Void

    @State private var scrolled: Int?
    @State private var dragStart: Int?

    init(minutes: Binding<Int>, range: ClosedRange<Int>, minimum: Int, isEditable: Bool, showsLabels: Bool,
         tint: Color, onInteraction: @escaping (Bool) -> Void) {
        _minutes = minutes
        self.range = range
        self.minimum = minimum
        self.isEditable = isEditable
        self.showsLabels = showsLabels
        self.tint = tint
        self.onInteraction = onInteraction
        _scrolled = State(initialValue: minutes.wrappedValue)
    }

    var body: some View {
        GeometryReader { proxy in
            let margin = max(0, proxy.size.width / 2 - TimerRuler.tickSpacing / 2)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(range, id: \.self) { minute in
                        Tick(minute: minute, isPast: minute > minutes, showsLabel: showsLabels, tint: tint)
                            .frame(width: TimerRuler.tickSpacing)
                            .id(minute)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollPosition(id: $scrolled, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.never)
            .scrollDisabled(!isEditable)
            .onScrollPhaseChange { _, phase in
                onInteraction(phase != .idle)
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
                        let offset = Int((value.translation.width / TimerRuler.tickSpacing).rounded())
                        let target = clamp((dragStart ?? minutes) - offset)
                        if target != scrolled { scrolled = target }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onInteraction(false)
                    }
            )
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
            if scrolled != new { withAnimation(Motion.content) { scrolled = new } }
        }
        .onChange(of: scrolled) { _, new in
            guard let new, isEditable else { return }
            let value = clamp(new)
            if value != new {
                // 0 is on the ruler as a landmark only.
                withAnimation(Motion.content) { scrolled = value }
            }
            if value != minutes { minutes = value }
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, max(range.lowerBound, minimum)), range.upperBound)
    }
}

private struct Tick: View {
    let minute: Int
    let isPast: Bool
    let showsLabel: Bool
    let tint: Color

    static let labelFont = Font.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()
    /// The label line's height (10-pt rounded semibold), so unlabelled ticks line up.
    static let labelHeight = ceil(NSFont.systemFont(ofSize: 10, weight: .semibold).boundingRectForFont.height)

    var body: some View {
        let major = minute % 5 == 0
        let style = tint.opacity(isPast ? 0.35 : 1)
        VStack(spacing: 3) {
            if showsLabel {
                // Text only on the labelled minutes: an empty label is still a text to resolve and
                // lay out, and the ruler has dozens on screen, all updated on every frame of the
                // island's growth.
                Group {
                    if major {
                        Text("\(minute)")
                            .font(Self.labelFont)
                            .foregroundStyle(tint.opacity(isPast ? 0.4 : 0.9))
                            .fixedSize()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: TimerRuler.tickSpacing, height: Self.labelHeight)
            }
            Capsule()
                .fill(style)
                .frame(width: 2.5)
                .frame(maxHeight: .infinity)
                .padding(.vertical, major ? 0 : 3)
        }
    }
}
