import Foundation

/// Key-press stepping on the same grid macOS uses for its volume and brightness keys:
/// 16 steps, or 64 with Shift+Option (the system's quarter-step modifier).
nonisolated enum LevelStepper {
    static let step: Double = 1.0 / 16.0
    static let fineStep: Double = 1.0 / 64.0

    /// Fraction of a grid unit within which a value counts as already sitting on a grid line.
    /// Levels round-trip through Float32 and device dB tables, so 5/16 can read back as 0.312499…;
    /// without this slack the next press would move by a sliver instead of a whole step.
    static let snapTolerance: Double = 0.05

    /// The next grid line above/below `value`, clamped to 0...1. Off-grid values (set by a slider)
    /// snap to the neighbouring line, like the system does.
    static func stepped(_ value: Double, up: Bool, fine: Bool) -> Double {
        let unit = fine ? fineStep : step
        let position = clamped(value) / unit
        let target = up
            ? (position + snapTolerance).rounded(.down) + 1
            : (position - snapTolerance).rounded(.up) - 1
        return clamped(target * unit)
    }

    /// Clamps to 0...1; NaN (a failed read converted to Double) becomes 0.
    static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, 0), 1)
    }
}
