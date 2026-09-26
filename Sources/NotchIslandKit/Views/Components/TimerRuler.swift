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
            RestingRulerTrack(minutes: $minutes, range: range, minimum: minimum, isEditable: isEditable,
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
    let onInteraction: (Bool) -> Void

    @State private var scrolled: Int?
    @State private var dragStart: Int?
    @State private var phase: ScrollPhase = .idle

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
                        Tick(minute: minute, isPast: minute > minutes, showsLabel: showsLabels, tint: tint)
                            .frame(width: spacing)
                            .id(minute)
                    }
                }
                .scrollTargetLayout()
                .overlay(alignment: .leading) {
                    if !landmarks.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(landmarks, id: \.self) { minute in
                                Tick(minute: minute, isPast: minute > minutes, showsLabel: showsLabels, tint: tint)
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
    let onInteraction: (Bool) -> Void

    @State private var isHovered = false
    @State private var isInteracting = false

    var body: some View {
        let live = !isEditable || isHovered || isInteracting
        ZStack {
            if live {
                RulerTrack(minutes: $minutes, range: range, minimum: minimum, isEditable: isEditable,
                           showsLabels: showsLabels, tint: tint) { interacting in
                    isInteracting = interacting
                    onInteraction(interacting)
                }
            } else {
                RulerPicture(value: min(max(minutes, max(range.lowerBound, minimum)), range.upperBound),
                             range: range, showsLabels: showsLabels, tint: tint)
            }
        }
        .onHover { isHovered = $0 }
    }
}

/// The resting scale: the same ticks where the scroll view puts them with the value centred, in a
/// plain stack (no scroll view to build and align), with the same fade at both ends.
private struct RulerPicture: View {
    let value: Int
    let range: ClosedRange<Int>
    let showsLabels: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let spacing = TimerRuler.tickSpacing
            let centre = proxy.size.width / 2
            let reach = Int(ceil(centre / spacing)) + 1
            ZStack(alignment: .topLeading) {
                ForEach(max(range.lowerBound, value - reach)...min(range.upperBound, value + reach), id: \.self) { minute in
                    Tick(minute: minute, isPast: minute > value, showsLabel: showsLabels, tint: tint)
                        .frame(width: spacing, height: proxy.size.height)
                        .offset(x: centre + CGFloat(minute - value) * spacing - spacing / 2)
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
