import CoreGraphics
import Foundation

/// How a text part of a widget (Now Playing's title, its artist) is set, from Customize's
/// inspector. Every field left at its default is the part as the widget sets it on its own.
nonisolated struct TextStyle: Sendable, Codable, Hashable {
    /// In points; nil: the size the widget picks for its room.
    var size: Double?
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStruckThrough = false
    var design: Design = .standard
    /// At most this many lines; nil: the widget's own (one).
    var maxLines: Int?
    /// As many lines as the box's height holds (Auto lines: only the user turns it on or off,
    /// never a resize); `maxLines` is kept for when it is turned off.
    var linesFillBox = false
    var alignment: Alignment = .leading
    /// What happens to text that does not fit.
    var overflow: Overflow = .truncate
    /// With `shrink`: the smallest the letters may get, as a share of their size; nil: half.
    var minimumScale: Double?
    /// With `shrink` in a box of its own: the largest the letters may grow to fill it, in points;
    /// nil: as large as one line of them fits the box.
    var maximumSize: Double?
    /// With `shrink` in a box of its own: the smallest they may shrink to, in points; nil: its
    /// smallest share (`minimumScale`) of its size.
    var minimumSize: Double?
    var color: TextColor = .automatic
    /// A background of its own behind the text; nil: none.
    var background: ElementBackground?
    /// The box the text is set in, when resized in the editor; nil: as wide as the widget gives it,
    /// as tall as its lines.
    var box: BoxSize?

    static let plain = TextStyle()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case size, isBold, isItalic, isUnderlined, isStruckThrough, design, maxLines, linesFillBox, alignment, overflow, minimumScale, maximumSize, minimumSize, color, background, box
    }

    // Every field may be missing (a style stored before it existed): its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Double.self, forKey: .size)
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderlined = try container.decodeIfPresent(Bool.self, forKey: .isUnderlined) ?? false
        isStruckThrough = try container.decodeIfPresent(Bool.self, forKey: .isStruckThrough) ?? false
        design = (try? container.decodeIfPresent(Design.self, forKey: .design)) ?? .standard
        maxLines = try container.decodeIfPresent(Int.self, forKey: .maxLines)
        alignment = (try? container.decodeIfPresent(Alignment.self, forKey: .alignment)) ?? .leading
        overflow = (try? container.decodeIfPresent(Overflow.self, forKey: .overflow)) ?? .truncate
        minimumScale = try? container.decodeIfPresent(Double.self, forKey: .minimumScale)
        maximumSize = (try? container.decodeIfPresent(Double.self, forKey: .maximumSize)).flatMap { $0 }
        minimumSize = (try? container.decodeIfPresent(Double.self, forKey: .minimumSize)).flatMap { $0 }
        color = (try? container.decodeIfPresent(TextColor.self, forKey: .color)) ?? .automatic
        background = try? container.decodeIfPresent(ElementBackground.self, forKey: .background)
        box = try? container.decodeIfPresent(BoxSize.self, forKey: .box)
        // A box resized before its lines could follow it: they do.
        linesFillBox = try container.decodeIfPresent(Bool.self, forKey: .linesFillBox) ?? (box != nil)
    }

    static let sizes = 4.0...48.0
    /// The smallest a text shrinks to on its own (where no smallest is set): smaller sizes are the
    /// user's to set.
    static let automaticLowest = 8.0
    static let lines = 1...6
    static let minimumScales = 0.1...0.9
    static let defaultMinimumScale = 0.5

    var effectiveMinimumScale: Double { minimumScale ?? Self.defaultMinimumScale }

    /// The lines the text may take, at `lineHeight` a line: as many as the box holds with
    /// `linesFillBox`, `maxLines` otherwise.
    func lineCount(lineHeight: CGFloat) -> Int {
        let fixed = maxLines ?? 1
        guard linesFillBox, let box, lineHeight > 0 else { return fixed }
        // Half a point spare: a box resized to exactly its lines holds them.
        return min(max(Int((CGFloat(box.height) + 0.5) / lineHeight), 1), Self.maxFilledLines)
    }

    /// The most lines a box fills: no more than a widget's height of small letters.
    static let maxFilledLines = 20

    nonisolated enum Design: String, Sendable, Codable, CaseIterable, Identifiable {
        case standard, rounded, serif, monospaced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: "Default"
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .monospaced: "Mono"
            }
        }
    }

    nonisolated enum Alignment: String, Sendable, Codable, CaseIterable, Identifiable {
        case leading, center, trailing, justified

        var id: String { rawValue }

        var title: String {
            switch self {
            case .leading: "Left"
            case .center: "Centre"
            case .trailing: "Right"
            case .justified: "Justified"
            }
        }

        var symbol: String {
            switch self {
            case .leading: "text.alignleft"
            case .center: "text.aligncenter"
            case .trailing: "text.alignright"
            case .justified: "text.justify"
            }
        }
    }

    nonisolated enum Overflow: String, Sendable, Codable, CaseIterable, Identifiable {
        /// Smaller letters (down to half), then cut.
        case shrink
        /// Cut, ending in "…".
        case truncate
        /// On as many more lines as it takes.
        case addLines

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shrink: "Shrink"
            case .truncate: "Cut"
            case .addLines: "+ Line"
            }
        }
    }

    nonisolated enum TextColor: Sendable, Codable, Hashable {
        /// The widget's own (the title bright, the artist dimmer).
        case automatic
        case custom(IslandTheme.RGB)
        /// The cover's colour while something plays.
        case artwork
    }

    nonisolated struct BoxSize: Sendable, Codable, Hashable {
        var width: Double
        var height: Double
    }

    /// Kept within what the inspector offers.
    mutating func sanitize() {
        size = size.map { min(max($0, Self.sizes.lowerBound), Self.sizes.upperBound) }
        maxLines = maxLines.map { min(max($0, Self.lines.lowerBound), Self.lines.upperBound) }
        minimumScale = minimumScale.map { min(max($0, Self.minimumScales.lowerBound), Self.minimumScales.upperBound) }
        maximumSize = maximumSize.map { min(max($0, Self.sizes.lowerBound), Self.sizes.upperBound) }
        minimumSize = minimumSize.map { min(max($0, Self.sizes.lowerBound), Self.sizes.upperBound) }
        if let box, !(box.width.isFinite && box.height.isFinite && box.width > 0 && box.height > 0) { self.box = nil }
        background?.sanitize()
    }
}

/// A background behind one part of a widget.
nonisolated struct ElementBackground: Sendable, Codable, Hashable {
    var kind: Kind = .plate
    /// The Colour background's colour; nil: the theme's.
    var color: IslandTheme.RGB?
    /// 0…1; nil: the kind's own (`WidgetBackground.defaultOpacity`).
    var opacity: Double?
    var corners: Corners = .rounded

    nonisolated enum Kind: String, Sendable, Codable, CaseIterable, Identifiable {
        case plate, colour, artwork

        var id: String { rawValue }

        var title: String {
            switch self {
            case .plate: "Plate"
            case .colour: "Colour"
            case .artwork: "Artwork"
            }
        }

        var defaultOpacity: Double { self == .plate ? 0.4 : 0.5 }
    }

    nonisolated enum Corners: String, Sendable, Codable, CaseIterable, Identifiable {
        case rounded, capsule, square

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rounded: "Rounded"
            case .capsule: "Capsule"
            case .square: "Square"
            }
        }
    }

    var effectiveOpacity: Double { opacity ?? kind.defaultOpacity }

    /// The room around the text inside the background, on each side.
    var insets: CGSize { CGSize(width: corners == .capsule ? 8 : 5, height: 3) }

    /// The corner radius it has of its own, at `height`.
    func radius(height: CGFloat) -> CGFloat {
        switch corners {
        case .rounded: min(6, height / 2)
        case .capsule: height / 2
        case .square: 0
        }
    }

    mutating func sanitize() {
        opacity = opacity.map { min(max($0, 0), 1) }
    }
}
