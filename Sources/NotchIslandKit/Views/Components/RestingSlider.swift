import SwiftUI

/// A system slider that is only a real `Slider` while the pointer is on it.
///
/// Measured: every native `Slider` on the island has SwiftUI start its own Metal renderer (the
/// Liquid Glass knob) — ~40 MB of graphics memory for as long as the slider is on screen, and
/// again each time one appears (every volume key press). At rest the knob is a flat capsule, so
/// until the pointer comes over the slider a picture of it is drawn instead (`SliderPicture`,
/// matched to the native one pixel for pixel), and the real control takes its place the moment it
/// could be used. The picture still answers a click or drag of its own, in case hover is missed.
struct RestingSlider: View {
    let value: Double
    let isEnabled: Bool
    let label: Text
    let set: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false
    @State private var isEditing = false

    var body: some View {
        // Only the regular size is drawn as a picture; the others stay native.
        let isLive = isHovered || isEditing || controlSize != .regular
        ZStack {
            if isLive {
                Slider(value: Binding(get: { value }, set: set), in: 0...1) {
                    label
                } onEditingChanged: { editing in
                    isEditing = editing
                    onEditingChanged(editing)
                }
                .labelsHidden()
            } else {
                SliderPicture(value: value, set: set, onEditingChanged: { editing in
                    isEditing = editing
                    onEditingChanged(editing)
                })
                .accessibilityRepresentation {
                    Slider(value: Binding(get: { value }, set: set), in: 0...1) { label }
                }
            }
        }
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

/// The macOS 27 slider at rest, drawn with plain shapes: a 6 pt track in the accent colour up to
/// the knob, a 20 × 16 pt knob travelling within the track (its centre stops half a knob in from
/// each end), in a frame as tall as the native control's.
private struct SliderPicture: View {
    let value: Double
    let set: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    static let trackHeight: CGFloat = 6
    static let knob = CGSize(width: 20, height: 16)
    static let height: CGFloat = 20
    /// Measured on the island's dark surface: knob 225/255, the empty track 37/255 over 6/255
    /// black, the filled part the accent a shade lighter (71, 147, 250 for blue).
    static let knobColor = Color(white: 0.86)
    static let trackColor = Color.white.opacity(0.082)
    static var fillColor: Color { Color.islandAccent.mix(with: .white, by: 0.02) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let travel = max(width - Self.knob.width, 0)
            let fraction = CGFloat(min(max(value, 0), 1))
            let centre = Self.knob.width / 2 + travel * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(Self.trackColor)
                    .frame(height: Self.trackHeight)
                Capsule().fill(Self.fillColor)
                    .frame(width: max(centre, Self.trackHeight), height: Self.trackHeight)
                Capsule().fill(Self.knobColor)
                    .frame(width: Self.knob.width, height: Self.knob.height)
                    .offset(x: centre - Self.knob.width / 2)
            }
            .frame(width: width, height: proxy.size.height)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                set(Double(min(max((drag.location.x - Self.knob.width / 2) / max(travel, 1), 0), 1)))
            }.onEnded { _ in
                isDragging = false
                onEditingChanged(false)
            })
        }
        .frame(height: Self.height)
    }
}
