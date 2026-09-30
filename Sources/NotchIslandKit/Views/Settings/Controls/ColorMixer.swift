import AppKit
import SwiftUI

/// The colours mixed lately (newest first), offered again in every mixer. Kept per user, a few.
@MainActor enum RecentColors {
    static let limit = 8
    private static let key = "recentColors"

    static var all: [IslandTheme.RGB] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(IslandTheme.RGB.init(hex:))
    }

    /// `rgb` first; a basic colour is not kept (it has its own circle).
    static func add(_ rgb: IslandTheme.RGB) {
        guard !IslandTheme.Preset.allCases.contains(where: { $0.color == rgb }) else { return }
        let hex = rgb.hex
        let kept = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != hex }
        UserDefaults.standard.set(Array(([hex] + kept).prefix(limit)), forKey: key)
    }
}

extension IslandTheme.RGB {
    /// `#RRGGBB`.
    var hex: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// The colour mixer: the basic colours and the ones mixed lately as circles, and any colour from
/// the spectrum (hue across, saturation down), its brightness beside it, the result with its hex
/// code and RGB values.
struct ColorMixer: View {
    @Binding var rgb: IslandTheme.RGB
    /// Where the owner names a basic colour (the theme's preset): a pick sets only it, and it is
    /// what the ring follows. Without it a pick is its colour, ringed while the colour is its.
    private let preset: Binding<IslandTheme.Preset>?
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var hex = ""
    @State private var appeared = false
    /// Read once, as the mixer opens: a colour mixed now joins them when it closes.
    @State private var recents = RecentColors.all

    /// The theme's own colours.
    private static let basics = IslandTheme.Preset.allCases.filter { $0 != .custom }
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 10), count: 4)

    init(rgb: Binding<IslandTheme.RGB>) {
        _rgb = rgb
        preset = nil
    }

    /// The theme's colour: a basic colour picked is its preset; one mixed is its first colour,
    /// alone (named after a basic colour when it is one).
    init(theme: Binding<IslandTheme>) {
        _rgb = Binding { theme.wrappedValue.rgb } set: { rgb in
            theme.wrappedValue.first = rgb
            theme.wrappedValue.mix = 0
            theme.wrappedValue.preset = Self.basics.first { $0.color == rgb } ?? .custom
        }
        preset = theme.preset
    }

    func isSelected(_ basic: IslandTheme.Preset) -> Bool {
        if let preset { preset.wrappedValue == basic } else { basic.color == rgb }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Basic colours")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsPalette.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(Array(Self.basics.enumerated()), id: \.element) { index, preset in
                        Button { pick(preset) } label: {
                            ColorCircle(color: preset.color?.color ?? .white, isSelected: isSelected(preset))
                        }
                        .buttonStyle(.plain)
                        .help(preset.title)
                        .accessibilityLabel(preset.title)
                        .scaleEffect(appeared ? 1 : 0.2)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.025 * Double(index)), value: appeared)
                    }
                }
                if !recents.isEmpty {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsPalette.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(recents, id: \.hex) { recent in
                            Button { pickRecent(recent) } label: {
                                ColorCircle(color: recent.color, isSelected: preset == nil && recent == rgb)
                            }
                            .buttonStyle(.plain)
                            .help(recent.hex)
                            .accessibilityLabel("Recent colour \(recent.hex)")
                        }
                    }
                }
            }
            .frame(width: 4 * 26 + 3 * 10, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SpectrumField(hue: $hue, saturation: $saturation, onChange: apply)
                        .frame(height: 140)
                    BrightnessBar(hue: hue, saturation: saturation, brightness: $brightness, onChange: apply)
                        .frame(width: 16, height: 140)
                }
                HStack(spacing: 12) {
                    Circle()
                        .fill(rgb.color)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                        .frame(width: 30, height: 30)
                    TextField("Hex", text: $hex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12).monospaced())
                        .frame(width: 84)
                        .onSubmit(applyHex)
                    Spacer(minLength: 8)
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
        .onAppear {
            load(rgb)
            appeared = true
        }
        // What was mixed here is offered again next time.
        .onDisappear { if preset.map({ $0.wrappedValue == .custom }) ?? true { RecentColors.add(rgb) } }
    }

    /// A colour mixed before, as it was.
    func pickRecent(_ recent: IslandTheme.RGB) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { rgb = recent }
        load(recent)
    }

    /// A basic colour, as it is.
    func pick(_ basic: IslandTheme.Preset) {
        guard let color = basic.color else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let preset { preset.wrappedValue = basic } else { rgb = color }
        }
        load(color)
    }

    /// The spectrum's colour becomes the colour.
    private func apply() {
        let color = IslandTheme.RGB(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
        rgb = color
        hex = color.hex
    }

    private func applyHex() {
        guard let typed = IslandTheme.RGB(hex: hex) else {
            hex = rgb.hex
            return
        }
        load(typed)
        apply()
    }

    private func load(_ rgb: IslandTheme.RGB) {
        let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        hue = Double(color.hueComponent)
        saturation = Double(color.saturationComponent)
        brightness = Double(color.brightnessComponent)
        hex = rgb.hex
    }
}

/// A colour as a plain circle; the chosen one ringed.
private struct ColorCircle: View {
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

/// Hue across, saturation from full at the top to grey at the bottom; a ring marks the colour.
private struct SpectrumField: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let onChange: () -> Void

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
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                hue = min(max(value.location.x / size.width, 0), 0.9999)
                saturation = 1 - min(max(value.location.y / size.height, 0), 1)
                onChange()
            })
        }
        .accessibilityLabel("Colour spectrum")
    }
}

/// The colour's brightness, from full at the top to black.
private struct BrightnessBar: View {
    let hue: Double
    let saturation: Double
    @Binding var brightness: Double
    let onChange: () -> Void

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
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                brightness = 1 - min(max(value.location.y / proxy.size.height, 0), 1)
                onChange()
            })
        }
        .accessibilityLabel("Brightness")
    }
}

// MARK: - Colour well

/// A style colour as a swatch; a click opens its choices — the element's own colour, the widget's
/// accent, the artwork's, the theme's — and the mixer for one of its own.
struct ColorWell: View {
    @Binding var color: StyleColor
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Circle()
                .fill(color.swatch)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { ColorWellPanel(color: $color) }
    }
}

/// A colour well's popover: where the colour comes from, and the mixer for one of its own. The
/// choices' bar is the small one: at its regular size it was wider than the popover.
struct ColorWellPanel: View {
    @Binding var color: StyleColor

    private enum Choice: Hashable, CaseIterable, Identifiable {
        case automatic, accent, artwork, theme, custom

        var id: Self { self }

        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .accent: "Accent"
            case .artwork: "Artwork"
            case .theme: "Theme"
            case .custom: "Custom"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Colour", selection: choice) {
                ForEach(Choice.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .choiceBar()
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .frame(maxWidth: .infinity)
            ColorMixer(rgb: mixed)
        }
        .padding(18)
        .frame(width: 440)
    }

    /// nil for a colour the well does not offer (a named tint, a value's scale): nothing marked.
    private var choice: Binding<Choice?> {
        Binding {
            switch color {
            case .automatic: .automatic
            case .accent: .accent
            case .artwork: .artwork
            case .theme: .theme
            case .rgb: .custom
            case .semantic, .named, .valueScale: nil
            }
        } set: { choice in
            switch choice {
            case .automatic: color = .automatic
            case .accent: color = .accent
            case .artwork: color = .artwork
            case .theme: color = .theme
            case .custom: color = .rgb(mixed.wrappedValue, alpha: alpha)
            case nil: break
            }
        }
    }

    /// The mixer's colour: the well's own, or the theme's to start from.
    private var mixed: Binding<IslandTheme.RGB> {
        Binding {
            if case .rgb(let rgb, _) = color { rgb } else { IslandThemeStore.shared.theme.rgb }
        } set: { rgb in
            color = .rgb(rgb, alpha: alpha)
        }
    }

    private var alpha: Double {
        if case .rgb(_, let alpha) = color { alpha } else { 1 }
    }
}

private extension StyleColor {
    /// How the colour well draws it, outside any widget: the accent and the theme as the theme's
    /// colour, automatic as a colour wheel.
    var swatch: AnyShapeStyle {
        switch self {
        case .automatic:
            AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
        case .accent, .theme: AnyShapeStyle(Color.islandAccent)
        case .artwork: AnyShapeStyle(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
        case .semantic(let semantic):
            switch semantic {
            case .primary: AnyShapeStyle(.primary)
            case .secondary: AnyShapeStyle(.secondary)
            case .tertiary: AnyShapeStyle(.tertiary)
            case .positive: AnyShapeStyle(Color.green)
            case .warning: AnyShapeStyle(Color.orange)
            case .critical: AnyShapeStyle(Color.red)
            }
        case .named(let tint):
            tint.color.map { AnyShapeStyle($0) } ?? StyleColor.automatic.swatch
        case .rgb(let rgb, let alpha): AnyShapeStyle(rgb.color.opacity(alpha))
        case .valueScale(let scale):
            AnyShapeStyle(LinearGradient(colors: scale == .rising ? [.red, .green] : [.green, .red],
                                         startPoint: .leading, endPoint: .trailing))
        }
    }
}
