import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct ColorMixerTests {
    /// A theme binding over a box the test reads back.
    private final class Box { var theme = IslandTheme() }

    private func binding(_ box: Box) -> Binding<IslandTheme> {
        Binding { box.theme } set: { box.theme = $0 }
    }

    /// The theme's mixer as Settings shows it, and the palette it replaced.
    private func themeMixer(_ theme: IslandTheme) -> some View {
        ColorMixer(theme: .constant(theme))
            .padding(18)
            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
            .frame(width: 520, height: 218)
            .environment(\.colorScheme, .dark)
    }

    private func pixels(_ view: some View, scale: CGFloat) -> [UInt8] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = renderer.cgImage!
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private func differing(_ a: [UInt8], _ b: [UInt8]) -> Int {
        a.count == b.count ? zip(a, b).count { $0 != $1 } : .max
    }

    /// The mixer draws the theme's colours exactly as the palette it replaced did: every pixel of
    /// it equals the palette's drawn just before. (A process's first drawing can differ from later
    /// ones, the palette's alike, so each is compared with its neighbour.)
    @Test(arguments: [1.0, 2.0]) func theThemeMixerDrawsAsThePaletteDid(scale: Double) {
        var theme = IslandTheme()
        theme.preset = .blue
        let palette = PaintPaletteReference(theme: .constant(theme)).frame(width: 520, height: 218).environment(\.colorScheme, .dark)
        let old = pixels(palette, scale: scale), new = pixels(themeMixer(theme), scale: scale)
        let oldAgain = pixels(palette, scale: scale), newAgain = pixels(themeMixer(theme), scale: scale)
        #expect(differing(old, new) == 0)
        #expect(differing(oldAgain, newAgain) == 0)
    }

    /// A basic colour picked in the theme's mixer names the theme's preset and nothing else.
    @Test func aBasicColourPicksOnlyTheThemesPreset() {
        let box = Box()
        box.theme.preset = .custom
        box.theme.first = IslandTheme.RGB(red: 0.2, green: 0.3, blue: 0.4)
        box.theme.mix = 0.7
        let before = box.theme
        let mixer = ColorMixer(theme: binding(box))

        mixer.pick(.blue)
        #expect(box.theme.preset == .blue)
        #expect(box.theme.first == before.first)
        #expect(box.theme.mix == before.mix)
        #expect(box.theme.second == before.second)
        #expect(mixer.isSelected(.blue))
        #expect(!mixer.isSelected(.white))
    }

    /// The ring follows the theme's preset, not its colour: a mixed theme of a basic colour's value
    /// rings nothing.
    @Test func theThemesRingFollowsItsPreset() {
        let box = Box()
        box.theme.preset = .custom
        box.theme.first = IslandTheme.Preset.blue.color!
        box.theme.mix = 0
        let mixer = ColorMixer(theme: binding(box))
        #expect(IslandTheme.Preset.allCases.filter { $0 != .custom }.allSatisfy { !mixer.isSelected($0) })
    }

    /// A colour mixed for the theme is its first one, alone, named after a basic colour when it is one.
    @Test func aMixedColourIsTheThemesFirstAlone() {
        let box = Box()
        box.theme.mix = 0.5
        let mixer = ColorMixer(theme: binding(box))

        mixer.rgb = IslandTheme.RGB(red: 0.2, green: 0.3, blue: 0.4)
        #expect(box.theme.first == IslandTheme.RGB(red: 0.2, green: 0.3, blue: 0.4))
        #expect(box.theme.mix == 0)
        #expect(box.theme.preset == .custom)

        mixer.rgb = IslandTheme.Preset.teal.color!
        #expect(box.theme.preset == .teal)
    }

    /// Elsewhere the mixer is a plain colour: a basic colour picked is its value, ringed by value.
    @Test func aPlainMixerPicksTheColour() {
        var rgb = IslandTheme.RGB(red: 0.2, green: 0.3, blue: 0.4)
        let mixer = ColorMixer(rgb: Binding { rgb } set: { rgb = $0 })
        mixer.pick(.green)
        #expect(rgb == IslandTheme.Preset.green.color)
        #expect(mixer.isSelected(.green))
    }
}

// MARK: - The palette the mixer replaced, as it was drawn (Settings ▸ Theme ▸ Mix, 0.5.1)

private struct PaintPaletteReference: View {
    @Binding var theme: IslandTheme
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var hex = ""
    @State private var appeared = false

    private static let basics = IslandTheme.Preset.allCases.filter { $0 != .custom }
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 10), count: 4)

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Basic colours")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsPalette.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(Array(Self.basics.enumerated()), id: \.element) { index, preset in
                        Button {} label: {
                            ReferenceCircle(color: preset.color?.color ?? .white, isSelected: theme.preset == preset)
                        }
                        .buttonStyle(.plain)
                        .help(preset.title)
                        .accessibilityLabel(preset.title)
                        .scaleEffect(appeared ? 1 : 0.2)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.025 * Double(index)), value: appeared)
                    }
                }
            }
            .frame(width: 4 * 26 + 3 * 10, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ReferenceSpectrum(hue: hue, saturation: saturation)
                        .frame(height: 140)
                    ReferenceBrightness(hue: hue, saturation: saturation, brightness: brightness)
                        .frame(width: 16, height: 140)
                }
                HStack(spacing: 12) {
                    Circle()
                        .fill(theme.color)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                        .frame(width: 30, height: 30)
                    TextField("Hex", text: $hex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12).monospaced())
                        .frame(width: 84)
                    Spacer(minLength: 8)
                    let rgb = theme.rgb
                    ForEach([("R", rgb.red), ("G", rgb.green), ("B", rgb.blue)], id: \.0) { name, value in
                        HStack(spacing: 3) {
                            Text(name).foregroundStyle(SettingsPalette.secondary)
                            Text("\(Int((value * 255).rounded()))").monospacedDigit()
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        .onAppear {
            let rgb = theme.rgb
            let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            hue = Double(color.hueComponent)
            saturation = Double(color.saturationComponent)
            brightness = Double(color.brightnessComponent)
            hex = String(format: "#%02X%02X%02X", Int((rgb.red * 255).rounded()), Int((rgb.green * 255).rounded()), Int((rgb.blue * 255).rounded()))
            appeared = true
        }
    }
}

private struct ReferenceCircle: View {
    let color: Color
    var isSelected = false

    var body: some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            .padding(isSelected ? 3 : 0)
            .overlay { Circle().strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2) }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
    }
}

private struct ReferenceSpectrum: View {
    let hue: Double
    let saturation: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(Color(hue: hue, saturation: saturation, brightness: 1)))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 16, height: 16)
                    .position(x: hue * size.width, y: (1 - saturation) * size.height)
            }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
    }
}

private struct ReferenceBrightness: View {
    let hue: Double
    let saturation: Double
    let brightness: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hue: hue, saturation: saturation, brightness: 1), .black],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(Capsule())
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(Color(hue: hue, saturation: saturation, brightness: brightness)))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: 16, height: 16)
                    .offset(y: (1 - brightness) * (proxy.size.height - 16))
            }
            .contentShape(.rect)
        }
    }
}
