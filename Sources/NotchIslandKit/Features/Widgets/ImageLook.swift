import Foundation

/// How a widget's picture (Now Playing's artwork) is sized, from Customize: whether resizing it keeps
/// its proportions, and whether it is as large as it was sized, grown to the widget's edges, or over
/// all of the widget. Left at its defaults it is the picture as before: stretched as it is resized.
nonisolated struct ImageLook: Sendable, Codable, Hashable {
    /// Resized, it grows or shrinks as a whole and is never stretched out of shape.
    var keepsShape = false
    var fit: Fit = .own
    /// How strongly it is drawn, 0…1.
    var opacity: Double = 1

    static let plain = ImageLook()

    nonisolated enum Fit: String, Sendable, Codable, CaseIterable, Identifiable {
        /// As large as it was sized in the editor (or as the layout makes it).
        case own
        /// Grown, in its shape, until it reaches the widget's edges.
        case edges
        /// Grown, in its shape, over all of the widget, cut to its outline.
        case fill

        var id: String { rawValue }

        var title: String {
            switch self {
            case .own: String(localized: "Own Size")
            case .edges: String(localized: "To Edges")
            case .fill: String(localized: "Fill")
            }
        }
    }

    init(keepsShape: Bool = false, fit: Fit = .own, opacity: Double = 1) {
        self.keepsShape = keepsShape
        self.fit = fit
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case keepsShape, fit, opacity
    }

    // A field missing or not understood (a later version's) is its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keepsShape = (try? container.decodeIfPresent(Bool.self, forKey: .keepsShape)).flatMap { $0 } ?? false
        fit = (try? container.decodeIfPresent(Fit.self, forKey: .fit)).flatMap { $0 } ?? .own
        opacity = (try? container.decodeIfPresent(Double.self, forKey: .opacity)).flatMap { $0 } ?? 1
        sanitize()
    }

    /// Its opacity within 0…1 (fully drawn where it is not a number).
    mutating func sanitize() {
        opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
    }
}
