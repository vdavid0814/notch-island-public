import SwiftUI

/// A horizontal ruler of minutes under a fixed centre marker, like the iPhone's Dynamic Island
/// timer: scroll it (trackpad or wheel) or drag it (mouse) to set the length.
///
/// It is a real scroll view, so the trackpad gets native momentum and the ruler settles on a whole
/// minute (`viewAligned`). Minutes up to the selection are drawn in full orange, the rest dimmed,
/// and the ruler fades out towards both ends.
struct TimerRuler: View {
    /// The selected minute; the ruler never settles below 1.
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...120
    /// While a timer runs the ruler shows the remaining minutes and cannot be moved.
    var isEditable = true
    var showsLabels = true
    /// Called when the user starts or ends moving it (keeps the island open meanwhile).
    var onInteraction: (Bool) -> Void = { _ in }

    static let tickSpacing: CGFloat = 8
    static let tint = Color.orange

    @State private var scrolled: Int?
    @State private var dragStart: Int?

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let margin = max(0, proxy.size.width / 2 - Self.tickSpacing / 2)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(range, id: \.self) { minute in
                            Tick(minute: minute, isPast: minute > minutes, showsLabel: showsLabels)
                                .frame(width: Self.tickSpacing)
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
                            let offset = Int((value.translation.width / Self.tickSpacing).rounded())
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
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 9))
                .foregroundStyle(Self.tint)
                .accessibilityHidden(true)
        }
        .onAppear { scrolled = minutes }
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
        .accessibilityElement()
        .accessibilityLabel("Timer length")
        .accessibilityValue("\(minutes) minutes")
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
        min(max(value, max(range.lowerBound, 1)), range.upperBound)
    }
}

private struct Tick: View {
    let minute: Int
    let isPast: Bool
    let showsLabel: Bool

    static let labelFont = Font.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()
    /// The label line's height (10-pt rounded semibold), so unlabelled ticks line up.
    static let labelHeight = ceil(NSFont.systemFont(ofSize: 10, weight: .semibold).boundingRectForFont.height)

    var body: some View {
        let major = minute % 5 == 0
        let style = TimerRuler.tint.opacity(isPast ? 0.35 : 1)
        VStack(spacing: 3) {
            if showsLabel {
                // Text only on the labelled minutes: an empty label is still a text to resolve and
                // lay out, and the ruler has dozens on screen, all updated on every frame of the
                // island's growth.
                Group {
                    if major {
                        Text("\(minute)")
                            .font(Self.labelFont)
                            .foregroundStyle(TimerRuler.tint.opacity(isPast ? 0.4 : 0.9))
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
