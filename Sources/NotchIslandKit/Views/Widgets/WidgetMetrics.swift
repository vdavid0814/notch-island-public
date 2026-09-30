import Synchronization
import SwiftUI

nonisolated enum WidgetMetrics {
    /// Inside a widget's plate.
    static let padding: CGFloat = 6
    static let cornerRadius: CGFloat = 16
    /// Below this inner height a widget draws a single row, with small controls.
    static let singleRowHeight: CGFloat = 44

    /// Inside the widget: the style's (Customize), else tighter without a plate (nothing to keep
    /// off the edge) and for Control Center's controls, whose button should fill a one-cell widget.
    static func padding(for widget: IslandWidget) -> CGFloat {
        if let padding = widget.style.layout.padding { return CGFloat(padding) }
        return widget.background == .none ? 2 : standardPadding(for: widget.kind)
    }

    /// A kind's padding on its plate.
    static func standardPadding(for kind: IslandWidgetKind) -> CGFloat {
        kind.systemControl != nil ? 4 : padding
    }

    /// One cell wide and tall: drawn as a circle.
    static func isRound(_ widget: IslandWidget) -> Bool { widget.frame.width == 1 && widget.frame.height == 1 }
}

/// Type that grows with the room a widget gives it, times the element's size, within limits — so
/// a label never overflows a small widget and never looks lost in a large one.
nonisolated enum WidgetType {
    static func points(_ room: CGFloat, ratio: CGFloat, min lower: CGFloat, max upper: CGFloat,
                       _ size: ElementSize = .medium) -> CGFloat {
        (min(max(room * ratio, lower), upper) * size.factor).rounded()
    }

    /// An element's size (a type size, or a ring's diameter) where the room may cap it: `design`
    /// is what Medium draws when there is room, `fit` the most the room takes. S, M and L always
    /// differ: with room each is its factor of the design; where the room caps them, Large takes
    /// all of it and Medium and Small a step and two below. (Scaling first and capping after made
    /// Large and Medium the same size — the cap — in most widgets.)
    static func fitted(_ design: CGFloat, fit: CGFloat, _ size: ElementSize, floor lower: CGFloat = 7) -> CGFloat {
        let share: CGFloat = switch size {
        case .small: 0.72
        case .medium: 0.86
        case .large: 1
        }
        // At the floor the steps stay apart too (a little over it rather than all three equal).
        let step: CGFloat = switch size {
        case .small: 0
        case .medium: 0.75
        case .large: 1.5
        }
        let value = min(design * size.factor, max(fit, 0) * share)
        return (max(value, lower + step) * 2).rounded() / 2
    }

    /// The largest type size at which `text` fits `width` on one line (the system font, as the
    /// widgets draw it).
    static func size(fitting text: String, in width: CGFloat, weight: NSFont.Weight = .regular,
                     rounded: Bool = false, monospacedDigits: Bool = false) -> CGFloat {
        guard width.isFinite else { return .greatestFiniteMagnitude }
        guard !text.isEmpty, width > 0 else { return width > 0 ? .greatestFiniteMagnitude : 0 }
        let measured = referenceWidth(Measure(text: text, weight: weight, rounded: rounded, monospacedDigits: monospacedDigits))
        guard measured > 0 else { return .greatestFiniteMagnitude }
        // A hair of slack: SwiftUI's text rounds its width up to whole pixels.
        return referenceSize * width / measured * 0.97
    }

    private static let referenceSize: CGFloat = 100

    /// The text's width at `referenceSize`, remembered while among the last 256 measured: the
    /// timer's readout and the rings' numbers are measured again in every evaluation of their widget.
    private static func referenceWidth(_ measure: Measure) -> CGFloat {
        if let width = widths.withLock({ $0[measure] }) { return width }
        var font = measure.monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: referenceSize, weight: measure.weight)
            : NSFont.systemFont(ofSize: referenceSize, weight: measure.weight)
        if measure.rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: descriptor, size: referenceSize) ?? font
        }
        let width = (measure.text as NSString).size(withAttributes: [.font: font]).width
        widths.withLock { $0[measure] = width }
        return width
    }

    private struct Measure: Hashable {
        var text: String
        var weight: NSFont.Weight
        var rounded: Bool
        var monospacedDigits: Bool
    }

    private static let widths = Mutex(MeasureCache<Measure, CGFloat>())

    /// How wide `text` is at a type size.
    static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight = .semibold) -> CGFloat {
        let fit = Self.size(fitting: text, in: 100, weight: weight, rounded: true, monospacedDigits: true)
        return fit >= .greatestFiniteMagnitude ? 0 : size * 100 / fit
    }

    /// The largest type size whose lines fit `height`.
    static func size(fittingLines lines: CGFloat = 1, in height: CGFloat) -> CGFloat {
        max(0, height) / (lineHeight * max(lines, 1))
    }

    /// The system font's line height per point of type size.
    static let lineHeight: CGFloat = 1.2

    /// A number inside a ring of `diameter` (a battery's or a level's percentage): `ratio` of the
    /// diameter at Medium, never wider than the ring's inside.
    static func ringText(_ text: String, diameter: CGFloat, ratio: CGFloat, _ size: ElementSize,
                         lines: CGFloat = 2) -> CGFloat {
        let inside = max(0, diameter - 2 * max(3, diameter * 0.1) * 1.4)
        let fit = min(Self.size(fitting: text, in: inside, weight: .semibold, rounded: true, monospacedDigits: true),
                      Self.size(fittingLines: lines, in: inside))
        return fitted(diameter * ratio, fit: fit, size, floor: 6)
    }

    /// The control size for a button element.
    static func controlSize(_ base: ControlSize, _ size: ElementSize) -> ControlSize {
        switch size {
        case .small: Metrics.Control.smaller(base)
        case .medium: base
        case .large: Metrics.Control.larger(base)
        }
    }
}
