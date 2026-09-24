import SwiftUI

/// A segmented switcher in the CAD app's liquid style (`CadLiquidSegment`): a capsule track of
/// island glass with a clear glass thumb that glides to the selected segment and can be dragged.
///
/// Layering follows the CAD app's final arrangement: the thumb sits *under* the labels. A lens on
/// top of the text would refract the very glyphs it marks; underneath, it only bends the track and
/// the backdrop around them.
///
/// The height comes from the control size (`Metrics.Control`), like the island's buttons.
struct IslandLiquidSegment<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var systemImage: String?
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value
    /// Symbols only; the title remains the tooltip and the accessibility label.
    var iconOnly = false

    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var geometry = SegmentGeometry()
    /// Thumb centre while dragging past the tap threshold; nil otherwise.
    @State private var dragCentre: CGFloat?
    /// Where the thumb was grabbed relative to its centre, so it moves with the pointer instead of
    /// jumping under it. Zero when the drag starts off the thumb.
    @State private var grabOffset: CGFloat = 0

    var body: some View {
        let inset = Metrics.Control.segmentInset(controlSize)
        ZStack(alignment: .topLeading) {
            thumb
            labels(height: Metrics.Control.height(controlSize) - 2 * inset)
        }
        .coordinateSpace(.named(segmentSpace))
        .contentShape(.capsule)
        .highPriorityGesture(drag)
        .padding(inset)
        .islandGlass(in: .capsule)
        // While dragging, the thumb sits exactly on the pointer; any animation would make it lag.
        .animation(dragCentre == nil ? glide : nil, value: thumbFrame)
        .animation(glide, value: selection)
        .accessibilityElement(children: .contain)
    }

    // MARK: Parts

    private var thumb: some View {
        let frame = thumbFrame
        let lift = dragCentre != nil && !reduceMotion
        return Color.clear
            .frame(width: frame.width, height: frame.height)
            .islandGlass(IslandGlass.thumb, in: .capsule)
            .scaleEffect(
                x: lift ? Metrics.Control.liftScale.width : 1,
                y: lift ? Metrics.Control.liftScale.height : 1
            )
            // The swell animates even though the position follows the pointer unanimated.
            .animation(glide, value: lift)
            .offset(x: frame.minX, y: frame.minY)
            // Nothing to show until the segments have been measured.
            .opacity(geometry.frames.isEmpty ? 0 : 1)
            .allowsHitTesting(false)
    }

    private func labels(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    label(for: item, height: height)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(iconOnly ? item.title : "")
                .accessibilityLabel(Text(item.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(segmentSpace))
                } action: { frame in
                    // The first measurement places the thumb; it must not grow in from zero.
                    var transaction = Transaction()
                    transaction.disablesAnimations = geometry.frames[index] == nil
                    withTransaction(transaction) { geometry.frames[index] = frame }
                }
            }
        }
    }

    @ViewBuilder private func label(for item: Item, height: CGFloat) -> some View {
        if iconOnly, let symbol = item.systemImage {
            Image(systemName: symbol)
                .font(Metrics.Control.font(controlSize))
                .frame(width: (height * Metrics.Control.iconSegmentAspect).rounded(), height: height)
        } else {
            Text(item.title)
                .font(Metrics.Control.font(controlSize))
                .lineLimit(1)
                .padding(.horizontal, Metrics.Control.horizontalPadding(controlSize))
                .frame(height: height)
        }
    }

    // MARK: Geometry

    private var selectedIndex: Int { items.firstIndex { $0.value == selection } ?? 0 }

    private var thumbFrame: CGRect { geometry.thumbFrame(selected: selectedIndex, dragCentre: dragCentre) }

    private var glide: Animation? { reduceMotion ? nil : IslandGlass.glide }

    // MARK: Gesture

    /// Tap: the thumb glides to the tapped segment on release. Drag: past the threshold the thumb
    /// follows the pointer, and on release lands where the flick was heading.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(segmentSpace))
            .onChanged { value in
                guard abs(value.translation.width) > Metrics.Control.dragThreshold || dragCentre != nil else { return }
                if dragCentre == nil {
                    let resting = geometry.frames[selectedIndex] ?? .zero
                    let onThumb = (resting.minX...resting.maxX).contains(value.startLocation.x)
                    grabOffset = onThumb ? value.startLocation.x - resting.midX : 0
                }
                dragCentre = value.location.x - grabOffset
            }
            .onEnded { value in
                let landing = dragCentre == nil ? value.location.x : value.predictedEndLocation.x - grabOffset
                dragCentre = nil
                grabOffset = 0
                if let target = geometry.nearestIndex(to: landing), items.indices.contains(target) {
                    selection = items[target].value
                }
            }
    }
}

/// Where the thumb goes, kept apart from the view so the drag maths is testable.
///
/// Segments are sized by their own labels, so each one reports its frame (in the switcher's
/// coordinate space) and the thumb takes its place and size from those frames.
nonisolated struct SegmentGeometry: Equatable {
    var frames: [Int: CGRect] = [:]

    /// At rest: the selected segment. While dragging: the selected segment's size, centred on the
    /// pointer and rubber-banded at the ends. The size deliberately does not follow the segment under
    /// the pointer mid-drag — without animation that would snap; the new size arrives with the glide.
    func thumbFrame(selected: Int, dragCentre: CGFloat?) -> CGRect {
        let resting = frames[selected] ?? .zero
        guard let dragCentre else { return resting }
        let centre = rubberBand(dragCentre, width: resting.width)
        return CGRect(x: centre - resting.width / 2, y: resting.minY, width: resting.width, height: resting.height)
    }

    /// 1:1 inside the track; past either end the overshoot approaches `rubberLimit` asymptotically
    /// (the curve iOS uses for list overscroll), so the thumb never hits a dead stop under the pointer.
    func rubberBand(_ x: CGFloat, width: CGFloat) -> CGFloat {
        guard let first = frames.values.map(\.minX).min(), let last = frames.values.map(\.maxX).max() else { return x }
        let low = first + width / 2, high = last - width / 2
        guard high > low else { return x }
        let limit = Metrics.Control.rubberLimit
        if x < low { return low - limit * (1 - limit / ((low - x) + limit)) }
        if x > high { return high + limit * (1 - limit / ((x - high) + limit)) }
        return x
    }

    /// The segment whose centre is closest to `x`; nil before anything has been measured.
    func nearestIndex(to x: CGFloat) -> Int? {
        frames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }
}

/// The switcher's own coordinate space: segment frames, thumb offset and drag locations all live
/// in it. Nested switchers each resolve it to their own nearest ancestor.
private nonisolated let segmentSpace = "island.segment"
