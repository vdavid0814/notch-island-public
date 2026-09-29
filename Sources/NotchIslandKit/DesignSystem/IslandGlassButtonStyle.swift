import SwiftUI

/// The island's buttons are the system's own Liquid Glass buttons (`.glass`, `.glassProminent`):
/// native metrics, press feedback, hover and accessibility, sized by the control size like any
/// other macOS button. A circle shows its symbol only (the title stays the accessibility label).
nonisolated enum IslandButtonShape: Sendable {
    case capsule, circle
}

extension View {
    func islandButton(_ shape: IslandButtonShape = .capsule, prominent: Bool = false) -> some View {
        modifier(IslandButtonModifier(shape: shape, prominent: prominent))
    }

    /// The timer's one action (Start, Pause, Done): prominent glass in the timer's colour, like the
    /// iPhone's orange "Start Timer"; a circle with the symbol when there is no room for the title.
    func timerAction(iconOnly: Bool, tint: Color) -> some View {
        islandButton(iconOnly ? .circle : .capsule, prominent: true)
            .tint(tint)
    }
}

private struct IslandButtonModifier: ViewModifier {
    let shape: IslandButtonShape
    let prominent: Bool

    /// A widget drawn as a picture (Settings' gallery): each glass button there would keep its own
    /// backdrop buffers (sixteen widgets of them cost ~130 MB of graphics memory, measured), so the
    /// pictures use the system's plain bordered buttons in the same shape.
    @Environment(\.isWidgetPreview) private var isPreview

    func body(content: Content) -> some View {
        Group {
            if isPreview {
                if prominent {
                    content.buttonStyle(.borderedProminent)
                } else {
                    content.buttonStyle(.bordered)
                }
            } else if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        }
        .buttonBorderShape(shape == .circle ? .circle : .capsule)
        .labelStyle(IslandButtonLabelStyle(iconOnly: shape == .circle))
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

extension View {
    /// Every row of mutually exclusive choices (pages, sizes, backgrounds, categories): the
    /// system's tab bar — a segmented control in the tabs role — with the capsule corners of the
    /// system's buttons.
    ///
    /// Measured again once shown (`SegmentedControlRemeasure`): SwiftUI sized the system's bar to
    /// its segments' own widths while the bar spreads them equally, and it widened on the first
    /// click (every bar in Settings, seen on video).
    func choiceBar() -> some View {
        pickerStyle(.tabs)
            .buttonBorderShape(.capsule)
            .background(SegmentedControlRemeasure())
    }
}


/// Tells the system's segmented bar next to it to measure itself again once it is in a window.
/// SwiftUI gives the bar the sum of its segments' own widths (81 + 81 + 99 pt); the bar spreads its
/// segments equally and wants three times the widest (297 pt, read from the control), and only
/// after a click did SwiftUI ask it again. Asked here a turn after it appears — outside any layout
/// pass (resizing it inside one stopped the app) — and only when it is short.
private struct SegmentedControlRemeasure: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.remeasure() }
        }

        /// The segmented control lying under this probe (the bar it is the background of).
        private func remeasure() {
            guard window != nil else { return }
            let area = convert(bounds, to: nil)
            func find(_ view: NSView) -> NSSegmentedControl? {
                if let control = view as? NSSegmentedControl, control.convert(control.bounds, to: nil).intersects(area) {
                    return control
                }
                for sub in view.subviews { if let found = find(sub) { return found } }
                return nil
            }
            // From the nearest common ancestor outwards, not the whole window.
            var ancestor = superview
            for _ in 0..<6 {
                guard let current = ancestor else { break }
                if let control = find(current) {
                    if control.frame.width + 0.5 < control.intrinsicContentSize.width {
                        control.invalidateIntrinsicContentSize()
                    }
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
