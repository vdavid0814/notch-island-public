import SwiftUI

/// The island's buttons are the system's own Liquid Glass buttons (`.glass`, `.glassProminent`):
/// native metrics, press feedback, hover and accessibility, sized by the control size like any
/// other macOS button. A circle shows its symbol only (the title stays the accessibility label).
nonisolated enum IslandButtonShape: Sendable {
    case capsule, circle
}

extension View {
    func islandButton(_ shape: IslandButtonShape = .capsule, prominent: Bool = false) -> some View {
        buttonStyle(IslandButtonStyle(shape: shape, prominent: prominent))
            .buttonBorderShape(shape == .circle ? .circle : .capsule)
            .labelStyle(IslandButtonLabelStyle(iconOnly: shape == .circle))
    }
}

/// Glass on the island; the system's bordered buttons in a picture (Settings' gallery: glass there
/// keeps backdrop buffers, ~130 MB for sixteen widgets); a drawing of the glass on Settings' stage.
private struct IslandButtonStyle: PrimitiveButtonStyle {
    let shape: IslandButtonShape
    let prominent: Bool

    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.isWidgetPreview) private var isPreview

    func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role, action: configuration.trigger) { configuration.label }
        if renderMode == .canvas {
            button.buttonStyle(GlassButtonPicture(shape: shape, prominent: prominent))
        } else if isPreview {
            if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
        } else if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass(Glass.regular.interactive()))
        }
    }
}

/// A circle shows the symbol alone; a capsule its symbol and title.
private struct IslandButtonLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: Metrics.Spacing.xSmall) {
                configuration.icon
                configuration.title
            }
        }
    }
}

/// A glass button at rest, drawn with plain shapes: the label in the control size's font and the
/// system button's own padding (measured: every glass and bordered button of one control size takes
/// the same room), on a faint circle or capsule — or the tint, prominent.
struct GlassButtonPicture: ButtonStyle {
    let shape: IslandButtonShape
    var prominent = false

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let (vertical, horizontal, round) = Self.padding(controlSize)
        let fill = prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14))
        configuration.label
            // The system button's own font where the button has none: AppKit's for its size (a
            // picture rendered off screen gets no font from the control size).
            .transformEnvironment(\.font) { font in
                if font == nil { font = .system(size: NSFont.systemFontSize(for: Self.appKitSize(controlSize))) }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.vertical, vertical)
            .padding(.horizontal, shape == .circle ? round : horizontal)
            .background {
                if shape == .circle { Circle().fill(fill) } else { Capsule().fill(fill) }
            }
            .opacity(isEnabled ? 1 : 0.5)
    }

    static func appKitSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }

    /// Around the label: above and below, beside it in a capsule, beside it in a circle.
    static func padding(_ size: ControlSize) -> (CGFloat, CGFloat, CGFloat) {
        switch size {
        case .mini: (1, 8, 1)
        case .small: (3, 10, 3)
        case .large: (6, 14, 6)
        case .extraLarge: (8, 16, 8)
        default: (4, 12, 4)
        }
    }
}

extension View {
    /// Every row of mutually exclusive choices (pages, sizes, backgrounds, categories): the
    /// system's tab bar — a segmented control in the tabs role — with the capsule corners of the
    /// system's buttons.
    ///
    /// Measured again once shown (`SegmentedControlRemeasure`): SwiftUI sized the system's bar to
    /// its segments' own widths while the bar spreads them equally, and it widened on the first
    /// click (every bar in Settings, seen on video).
    ///
    /// `width`: the bar made that wide, its segments spread equally across it (never narrower than
    /// 90 % of its own width).
    func choiceBar(width: CGFloat? = nil) -> some View {
        pickerStyle(.tabs)
            .buttonBorderShape(.capsule)
            .background(SegmentedControlRemeasure(width: width))
    }
}

/// Tells the system's segmented bar next to it to measure itself again once it is in a window.
/// SwiftUI gives the bar the sum of its segments' own widths (81 + 81 + 99 pt); the bar spreads its
/// segments equally and wants three times the widest (297 pt, read from the control), and only
/// after a click did SwiftUI ask it again. Asked here a turn after it appears — outside any layout
/// pass (resizing it inside one stopped the app) — and only when it is short.
///
/// Given a width, it sets the segments' widths so the bar is that wide (down to 90 % of its own
/// width): the bar reports it as its own, and SwiftUI lays it out so.
private struct SegmentedControlRemeasure: NSViewRepresentable {
    var width: CGFloat?

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        guard view.width != width else { return }
        view.width = width
        if view.window != nil { DispatchQueue.main.async { [weak view] in view?.remeasure() } }
    }

    final class Probe: NSView {
        var width: CGFloat?
        /// The segments' widths as the bar measured them before any were set.
        private var natural: CGFloat?
        /// Tries left for a bar not laid out yet (one coming in with an animation has no size at
        /// first, and is not found under the probe).
        private var retries = 5

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.remeasure() }
        }

        /// The segmented controls lying under this probe (the bar it is the background of — or two
        /// stacked bars, one fading over the other, which are both made as wide).
        fileprivate func remeasure() {
            guard window != nil else { return }
            let area = convert(bounds, to: nil)
            func find(_ view: NSView, into found: inout [NSSegmentedControl]) {
                if let control = view as? NSSegmentedControl, control.convert(control.bounds, to: nil).intersects(area) {
                    found.append(control)
                }
                for sub in view.subviews { find(sub, into: &found) }
            }
            // From the nearest common ancestor outwards, not the whole window.
            var ancestor = superview
            var found = false
            defer {
                if retries > 0, !found {
                    retries -= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.remeasure() }
                }
            }
            for _ in 0..<6 {
                guard let current = ancestor else { break }
                var controls: [NSSegmentedControl] = []
                find(current, into: &controls)
                if !controls.isEmpty {
                    found = true
                    for control in controls {
                        if width != nil || natural != nil { spread(control) }
                        if control.frame.width + 0.5 < control.intrinsicContentSize.width {
                            control.invalidateIntrinsicContentSize()
                        }
                    }
                    return
                }
                ancestor = current.superview
            }
        }

        /// The narrowest a bar is made, of its own width.
        static let squeeze: CGFloat = 0.9

        /// The segments spread across `width` (0 each: their own widths again).
        private func spread(_ control: NSSegmentedControl) {
            let count = control.segmentCount
            guard count > 0 else { return }
            if natural == nil {
                // Its own width with no widths set: another probe may have spread it already.
                for index in 0..<count { control.setWidth(0, forSegment: index) }
                natural = control.intrinsicContentSize.width
            }
            // A little narrower than its own width too: the room the bar leaves around each label
            // takes it, rather than the bar hanging past its pane (four labels in the inspector).
            guard let width, let natural, abs(width - natural) > 0.5, width >= natural * Self.squeeze else {
                for index in 0..<count { control.setWidth(0, forSegment: index) }
                control.invalidateIntrinsicContentSize()
                return
            }
            // The borders between the segments are the bar's own: measured once with a width set.
            var each = (width / CGFloat(count)).rounded(.down)
            for index in 0..<count { control.setWidth(each, forSegment: index) }
            each += ((width - control.intrinsicContentSize.width) / CGFloat(count)).rounded(.down)
            for index in 0..<count { control.setWidth(each, forSegment: index) }
            control.invalidateIntrinsicContentSize()
        }
    }
}
