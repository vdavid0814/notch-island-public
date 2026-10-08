import Foundation

/// How a widget's playback line (Now Playing's progress) is drawn, from Customize: the colour of
/// the line and of the part played, its ends, the knob at the position, and where the line and the
/// times under it are and how large (placed in the panel under the editor). Each time's type and
/// colour are its text style (`IslandWidget.textStyles` under `.elapsedTime` and `.remainingTime`).
/// Every field left at its default is the line as the widget draws it; none of it moves the parts
/// around the line.
nonisolated struct ProgressLook: Sendable, Codable, Hashable {
    /// The whole line, under the part played.
    var trackColor: TextStyle.TextColor = .automatic
    /// The part played.
    var fillColor: TextStyle.TextColor = .automatic
    var ends: Ends = .round
    var knob: Knob = .base
    /// How far the line is from where the layout puts it, in points.
    var barOffset: ElementOffset = .zero
    /// The line's length, as a share of its own (from its leading end).
    var barLength: Double = 1
    /// The line's thickness, as a share of its own.
    var barThickness: Double = 1
    /// How far each time is from where the layout puts it, in points.
    var elapsedOffset: ElementOffset = .zero
    var remainingOffset: ElementOffset = .zero

    static let plain = ProgressLook()

    static let barLengths = 0.1...1.0
    static let barThicknesses = 0.4...4.0

    /// The parts of the line placed in the panel under the editor.
    nonisolated enum Part: String, Sendable, CaseIterable, Identifiable {
        case bar, elapsed, remaining

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bar: "Line"
            case .elapsed: "Elapsed"
            case .remaining: "Remaining"
            }
        }

        /// The text at this end of `line`: Now Playing's times, the system's name and value.
        func textID(in line: ElementID) -> ElementID? {
            switch (line, self) {
            case (_, .bar): nil
            case (.cpuLoad, .elapsed): .cpuTitle
            case (.cpuLoad, .remaining): .cpuValue
            case (.memoryLoad, .elapsed): .memoryTitle
            case (.memoryLoad, .remaining): .memoryValue
            default: textID
            }
        }

        /// What it is called on `line`.
        func title(in line: ElementID) -> String {
            guard line == .cpuLoad || line == .memoryLoad else { return title }
            return switch self {
            case .bar: title
            case .elapsed: "Name"
            case .remaining: "Value"
            }
        }

        /// The text style a time is set in.
        var textID: ElementID? {
            switch self {
            case .bar: nil
            case .elapsed: .elapsedTime
            case .remaining: .remainingTime
            }
        }
    }

    func offset(of part: Part) -> ElementOffset {
        switch part {
        case .bar: barOffset
        case .elapsed: elapsedOffset
        case .remaining: remainingOffset
        }
    }

    mutating func setOffset(_ offset: ElementOffset, of part: Part) {
        switch part {
        case .bar: barOffset = offset
        case .elapsed: elapsedOffset = offset
        case .remaining: remainingOffset = offset
        }
    }

    /// Kept within what Customize offers.
    mutating func sanitize() {
        barLength = barLength.isFinite ? min(max(barLength, Self.barLengths.lowerBound), Self.barLengths.upperBound) : 1
        barThickness = barThickness.isFinite ? min(max(barThickness, Self.barThicknesses.lowerBound), Self.barThicknesses.upperBound) : 1
        for part in Part.allCases where !offset(of: part).isFinite { setOffset(.zero, of: part) }
    }

    init() {}

    nonisolated enum Ends: String, Sendable, Codable, CaseIterable, Identifiable {
        case round, rounded, sharp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .round: "Round"
            case .rounded: "Rounded"
            case .sharp: "Sharp"
            }
        }

        /// The corner radius of a line `height` thick.
        func radius(height: CGFloat) -> CGFloat {
            switch self {
            case .round: height / 2
            case .rounded: height * 0.22
            case .sharp: 0
            }
        }
    }

    /// What marks the position: the end of the part played alone (Base), or a knob on it.
    nonisolated enum Knob: String, Sendable, Codable, CaseIterable, Identifiable {
        case base, circle, capsule, square

        var id: String { rawValue }

        var title: String {
            switch self {
            case .base: "Base"
            case .circle: "Circle"
            case .capsule: "Capsule"
            case .square: "Square"
            }
        }

        /// Its picture in the inspector's bar.
        var symbol: String {
            switch self {
            case .base: "minus"
            case .circle: "circle.fill"
            case .capsule: "capsule.fill"
            case .square: "square.fill"
            }
        }

        /// Its size on a line `height` thick (nil: none).
        func size(height: CGFloat) -> CGSize? {
            let side = (height * 1.9).rounded()
            switch self {
            case .base: return nil
            case .circle, .square: return CGSize(width: side, height: side)
            case .capsule: return CGSize(width: (side * 1.6).rounded(), height: side)
            }
        }

        /// Its corner radius at `size`.
        func radius(size: CGSize) -> CGFloat {
            switch self {
            case .base, .circle, .capsule: min(size.width, size.height) / 2
            case .square: min(size.width, size.height) * 0.2
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case trackColor, fillColor, ends, knob, barOffset, barLength, barThickness, elapsedOffset, remainingOffset
    }

    // Every field may be missing or unknown (stored before it existed, or by a later version): its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackColor = (try? container.decodeIfPresent(TextStyle.TextColor.self, forKey: .trackColor)).flatMap { $0 } ?? .automatic
        fillColor = (try? container.decodeIfPresent(TextStyle.TextColor.self, forKey: .fillColor)).flatMap { $0 } ?? .automatic
        ends = (try? container.decodeIfPresent(Ends.self, forKey: .ends)).flatMap { $0 } ?? .round
        knob = (try? container.decodeIfPresent(Knob.self, forKey: .knob)).flatMap { $0 } ?? .base
        barOffset = (try? container.decodeIfPresent(ElementOffset.self, forKey: .barOffset)).flatMap { $0 } ?? .zero
        barLength = (try? container.decodeIfPresent(Double.self, forKey: .barLength)).flatMap { $0 } ?? 1
        barThickness = (try? container.decodeIfPresent(Double.self, forKey: .barThickness)).flatMap { $0 } ?? 1
        elapsedOffset = (try? container.decodeIfPresent(ElementOffset.self, forKey: .elapsedOffset)).flatMap { $0 } ?? .zero
        remainingOffset = (try? container.decodeIfPresent(ElementOffset.self, forKey: .remainingOffset)).flatMap { $0 } ?? .zero
    }
}
