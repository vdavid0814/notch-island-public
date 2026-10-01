import AppKit
import Synchronization

/// The largest type that fits a room, and the height a text frame of a type size takes.
nonisolated enum TextFit {
    /// The range the engine fits type in (a size set by the user may be larger: `TextStyle.pointRange`).
    static let minimumPoints = CGFloat(TextStyle.pointRange.lowerBound)
    static let maximumPoints: CGFloat = 96
    /// Sizes are set in quarter points.
    static let step: CGFloat = 0.25

    /// The largest size, in quarter points, at which every sample fits `room` in `lines` lines; nil
    /// when not even the smallest does. Estimated from the widths at 100 pt, then checked at the
    /// size itself and stepped down until it fits: SF's optical sizes are not exactly in proportion.
    /// Wrapped, a line break swallows its space, so up to `lines - 1` spaces take no room; a step or
    /// two above the estimate is still tried, for tracking on those spaces.
    static func maxPoints(samples: [String], spec: TypeSpec, room: CGSize, lines: Int = 1, scale: CGFloat) -> CGFloat? {
        guard room.width > 0, room.height > 0 else { return nil }
        let lines = max(lines, 1)
        var estimate = room.height / (CGFloat(lines) * WidgetTypography.lineHeightPerPoint(spec))
        var untracked = spec.at(WidgetTypography.reference)
        untracked.tracking = 0
        let space = lines > 1 ? WidgetTypography.referenceWidth(" ", untracked) : 0
        for text in samples where !text.isEmpty {
            let plain = WidgetTypography.referenceWidth(text, untracked)
            guard plain > 0 else { continue }
            // Tracking is in points whatever the size: what it adds at 100 pt it adds at any size.
            let tracking = WidgetTypography.referenceWidth(text, spec.at(WidgetTypography.reference)) - plain
            let swallowed = CGFloat(min(lines - 1, text.count { $0 == " " })) * space
            estimate = min(estimate, (room.width * CGFloat(lines) - tracking) * WidgetTypography.reference / max(plain - swallowed, 1))
        }
        let start = min((estimate / step).rounded(.down) * step, maximumPoints)
        var points = start
        while points >= minimumPoints {
            if fits(samples, spec.at(points), room: room, lines: lines, scale: scale) {
                for above in [points + 2 * step, points + step] where above > start && above <= maximumPoints
                    && fits(samples, spec.at(above), room: room, lines: lines, scale: scale) {
                    return above
                }
                return points
            }
            points -= step
        }
        return nil
    }

    static func fits(_ samples: [String], _ spec: TypeSpec, room: CGSize, lines: Int = 1, scale: CGFloat) -> Bool {
        guard CGFloat(max(lines, 1)) * WidgetTypography.lineHeight(spec) <= room.height else { return false }
        return samples.allSatisfy { text in
            lines <= 1 ? WidgetTypography.width(text, spec, scale: scale) <= room.width
                : WidgetTypography.lineCount(text, spec, width: room.width - 1 / scale) <= lines
        }
    }

    /// The height of a text frame of `lines` lines at `points`: whole lines as SwiftUI lays them
    /// out (`WidgetTypography.lineHeight`, rounded up to the point), so text in the frame is never cut.
    static func frameHeight(points: CGFloat, lines: Int = 1, spec: TypeSpec) -> CGFloat {
        CGFloat(max(lines, 1)) * WidgetTypography.lineHeight(spec.at(points))
    }

    /// The largest size, in quarter points, whose frame is no taller than `height`; 0 when none is.
    ///
    /// Lines are whole points, so several sizes share a frame height and this returns the largest of
    /// them: a size set before comes back no smaller, and the same only when it was the largest.
    /// `LayoutConversion.unlock` therefore stores each text's measured size as its fixed size
    /// wherever this gives back another, and sizes from the frame only where it gives back the same.
    static func points(forFrameHeight height: CGFloat, lines: Int = 1, spec: TypeSpec) -> CGFloat {
        let lines = max(lines, 1)
        // Each metric rounds up, so a frame is never shorter than in proportion: this is the most.
        var points = (height / (CGFloat(lines) * WidgetTypography.lineHeightPerPoint(spec)) / step).rounded(.down) * step
        while points > 0, frameHeight(points: points, lines: lines, spec: spec) > height { points -= step }
        return max(points, 0)
    }
}

/// The same for SF Symbols, drawn in their own configuration.
nonisolated enum SymbolFit {
    /// The symbol's size at `points`, rounded up to the pixel; zero for a name the system lacks.
    static func size(_ name: String, points: CGFloat, weight: FontWeightChoice, scale: CGFloat) -> CGSize {
        let size = measured(name, points: points, weight: weight)
        return CGSize(width: (size.width * scale).rounded(.up) / scale, height: (size.height * scale).rounded(.up) / scale)
    }

    /// The largest size, in quarter points, at which the symbol fits `room`; nil when not even the
    /// smallest does, or the system has no such symbol.
    static func maxPoints(_ name: String, weight: FontWeightChoice, room: CGSize, scale: CGFloat) -> CGFloat? {
        let reference = WidgetTypography.reference
        let unit = measured(name, points: reference, weight: weight)
        guard unit.width > 0, unit.height > 0, room.width > 0, room.height > 0 else { return nil }
        let estimate = min(room.width / unit.width, room.height / unit.height) * reference
        var points = min((estimate / TextFit.step).rounded(.down) * TextFit.step, TextFit.maximumPoints)
        while points >= TextFit.minimumPoints {
            let size = size(name, points: points, weight: weight, scale: scale)
            if size.width <= room.width, size.height <= room.height { return points }
            points -= TextFit.step
        }
        return nil
    }

    private static func measured(_ name: String, points: CGFloat, weight: FontWeightChoice) -> CGSize {
        let key = Key(name: name, points: points, weight: weight)
        if let size = cache.withLock({ $0[key] }) { return size }
        let configuration = NSImage.SymbolConfiguration(pointSize: points, weight: weight.nsWeight)
        let size = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.size ?? .zero
        cache.withLock { $0[key] = size }
        return size
    }

    private struct Key: Hashable {
        var name: String
        var points: CGFloat
        var weight: FontWeightChoice
    }

    private static let cache = Mutex(MeasureCache<Key, CGSize>())
}
