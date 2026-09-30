import AppKit
import Observation
import SwiftUI

/// The island's colour (Settings ▸ General ▸ Theme): what the system's blue was — sliders, the
/// selected tile, the active glass, the widgets' glow. White by default (asked for); one of the
/// paints, or two of them mixed. Only those places change: the system's controls and glass keep
/// their own look (a tint over the whole window coloured every glass button, v0.4.8 build).
nonisolated struct IslandTheme: Codable, Equatable, Sendable {
    nonisolated enum Preset: String, Codable, CaseIterable, Identifiable, Sendable {
        case white, blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, graphite, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .white: "White"
            case .blue: "Blue"
            case .indigo: "Indigo"
            case .purple: "Purple"
            case .pink: "Pink"
            case .red: "Red"
            case .orange: "Orange"
            case .yellow: "Yellow"
            case .green: "Green"
            case .mint: "Mint"
            case .teal: "Teal"
            case .graphite: "Graphite"
            case .custom: "Mix"
            }
        }

        /// The system's own colours, so each looks right in the dark island.
        var color: RGB? {
            switch self {
            case .white: RGB(red: 1, green: 1, blue: 1)
            case .blue: RGB(NSColor.systemBlue)
            case .indigo: RGB(NSColor.systemIndigo)
            case .purple: RGB(NSColor.systemPurple)
            case .pink: RGB(NSColor.systemPink)
            case .red: RGB(NSColor.systemRed)
            case .orange: RGB(NSColor.systemOrange)
            case .yellow: RGB(NSColor.systemYellow)
            case .green: RGB(NSColor.systemGreen)
            case .mint: RGB(NSColor.systemMint)
            case .teal: RGB(NSColor.systemTeal)
            case .graphite: RGB(red: 0.56, green: 0.57, blue: 0.6)
            case .custom: nil
            }
        }
    }

    /// A colour as sRGB components, so it can be stored.
    nonisolated struct RGB: Codable, Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ color: NSColor) {
            let srgb = color.usingColorSpace(.sRGB) ?? color
            self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
        }

        init(_ color: Color) {
            self.init(NSColor(color))
        }

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

        /// `t` of the way to `other`, in linear light (a mix of red and blue is a clear purple, not
        /// the muddy one plain sRGB averaging gives).
        func mixed(with other: RGB, by t: Double) -> RGB {
            // The ends exactly (the round trip through linear light is a hair off).
            if t <= 0 { return self }
            if t >= 1 { return other }
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            func gamma(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
            func mix(_ a: Double, _ b: Double) -> Double { gamma(linear(a) + (linear(b) - linear(a)) * t) }
            return RGB(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
        }
    }

    var preset: Preset = .white
    /// The Mix: two colours and how far from the first towards the second.
    var first = RGB(red: 1, green: 1, blue: 1)
    var second = RGB(NSColor.systemBlue)
    var mix: Double = 0.5

    static let `default` = IslandTheme()

    var rgb: RGB { preset.color ?? first.mixed(with: second, by: min(max(mix, 0), 1)) }
    var color: Color { rgb.color }
}

/// The theme in force, where every view can read it (and redraws when it changes). Preferences
/// writes it; it starts from the stored value so it is right before `Preferences` exists.
@MainActor @Observable final class IslandThemeStore {
    static let shared = IslandThemeStore()
    var theme: IslandTheme

    init(defaults: UserDefaults = .standard) {
        theme = defaults.data(forKey: Preferences.Key.theme).flatMap { try? JSONDecoder().decode(IslandTheme.self, from: $0) } ?? .default
    }
}

extension Color {
    /// The island's accent: the theme's colour (in place of the system's `accentColor`).
    @MainActor static var islandAccent: Color { IslandThemeStore.shared.theme.color }
}
