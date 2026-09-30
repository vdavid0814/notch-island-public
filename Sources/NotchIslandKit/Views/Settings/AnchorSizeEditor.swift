import SwiftUI

/// Settings ▸ Live Activities ▸ Window Anchor: the size every anchored window is given, on a picture
/// of the notch screen — the window hanging from the notch at that size. A size is picked by name
/// in the bar under it; any but Automatic opens a width and a height slider. The picture's sides
/// and bottom edge can be dragged too (the sides together: it stays centred).
struct AnchorSizeEditor: View {
    @Binding var size: AnchorSizePreference
    let screen: AnchorScreen
    /// "Up to the top of the screen": the window drawn from the screen's top on the stage, else under the menu bar.
    var onTop = true
    /// Where the stage shows the app's name and Release.
    var bar: AnchorBarPlacement = .belowWindow

    /// The picture's width; its height follows the screen's.
    static let pictureWidth: CGFloat = 380
    /// About as wide as the name or Release beside the notch, in screen points.
    static let earWidth: CGFloat = 90

    /// While a handle or a slider is dragged: the size it shows, written once when let go.
    @State private var draft: CGSize?
    @State private var isSliding = false

    private var current: CGSize { draft ?? size.size(on: screen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The size on show beside the title, on one line.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                InfoLabel("Size when anchored", "Every window you anchor opens at this size, centred under the notch. The named sizes follow the screen; drag the sliders or the picture's edges for your own.")
                Spacer(minLength: 0)
                Text("\(Int(current.width)) × \(Int(current.height)) pt")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(SettingsPalette.secondary)
                    .contentTransition(.numericText())
                    .fixedSize()
            }
            picture
                .frame(maxWidth: .infinity)
            Picker("Size", selection: choice) {
                ForEach(AnchorSizePreset.allCases) { Text(Self.title($0)).tag($0) }
            }
            .choiceBar()
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            if !size.isAutomatic {
                VStack(spacing: 8) {
                    dimensionSlider("Width", \.width, range: AnchorSizePreference.widths(on: screen))
                    dimensionSlider("Height", \.height, range: AnchorSizePreference.heights(on: screen))
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.content, value: size.isAutomatic)
        .padding(.vertical, 6)
    }

    private var scale: CGFloat { Self.pictureWidth / max(screen.frame.width, 1) }

    private static func title(_ preset: AnchorSizePreset) -> String {
        switch preset {
        case .automatic: String(localized: "Automatic")
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .tall: String(localized: "Tall")
        case .wide: String(localized: "Wide")
        case .custom: String(localized: "Custom")
        }
    }

    /// The bar's pick: a named size, Automatic, or Custom (the size on show, to set by hand).
    private var choice: Binding<AnchorSizePreset> {
        Binding(get: { size.choice }, set: { picked in
            draft = nil
            withAnimation(Motion.content) {
                switch picked {
                case .automatic: size = AnchorSizePreference()
                case .custom:
                    let shown = size.size(on: screen)
                    size = AnchorSizePreference(width: Double(shown.width), height: Double(shown.height))
                default: size = AnchorSizePreference(preset: picked)
                }
            }
        })
    }

    /// A width or height slider: the picture follows while it is dragged, the size is written when let go.
    private func dimensionSlider(_ title: LocalizedStringKey, _ axis: WritableKeyPath<CGSize, CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        // Its title, the slider across the rest, the value: the three close together.
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { Double(current[keyPath: axis]) }, set: { value in
                var next = current
                next[keyPath: axis] = CGFloat(value).rounded()
                guard next != current else { return }
                if isSliding { draft = next } else { write(next) }
            }), in: Double(range.lowerBound)...Double(range.upperBound)) { editing in
                isSliding = editing
                if !editing { commit() }
            }
            .labelsHidden()
            .tint(Color.islandAccent)
            ReservedWidthText("\(Int(current[keyPath: axis])) pt", fitting: ["8888 pt"])
                .foregroundStyle(SettingsPalette.secondary)
        }
    }

    private var picture: some View {
        let scale = scale
        let screenSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        let band = screen.band * scale
        let window = CGSize(width: current.width * scale, height: current.height * scale)
        let stage = CGRect(x: (screenSize.width - window.width) / 2 - AnchorStageLayout.shoulder * scale, y: onTop ? 0 : band,
                           width: window.width + 2 * AnchorStageLayout.shoulder * scale, height: window.height + (onTop ? band : 0))
        return ZStack(alignment: .topLeading) {
            // The desktop, the menu bar and the notch.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.55), Color(red: 0.12, green: 0.12, blue: 0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(.white.opacity(0.12)).frame(height: band)
            // Up to the top: the window from the screen's top on the stage (the island's shoulders, the
            // bar under it). Else the window alone, under the menu bar.
            if onTop {
                IslandShape(bottomRadius: AnchorStageLayout.bottomRadius * scale * 1.6, shoulderRadius: AnchorStageLayout.shoulder * scale * 1.4)
                    .fill(.black)
                    .frame(width: stage.width, height: stage.height)
                    .offset(x: stage.minX)
            }
            windowPicture(window)
                .shadow(color: .black.opacity(onTop ? 0 : 0.35), radius: 4, y: 2)
                .offset(x: stage.minX + AnchorStageLayout.shoulder * scale, y: stage.minY)
            // The notch; with the name and Release beside it, as wide as those.
            let notch = (screen.notch.width + (onTop && bar == .menuBar ? 2 * Self.earWidth : 0)) * scale
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(.black)
                .frame(width: notch, height: band)
                .offset(x: (screenSize.width - notch) / 2)
            handles(stage: stage, band: band)
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)) }
        .accessibilityElement()
        .accessibilityLabel("Anchored window size")
        .accessibilityValue("\(Int(current.width)) by \(Int(current.height)) points")
    }

    /// A window: a title bar with its three lights, and its content.
    private func windowPicture(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 5, height: 5) }
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 12)
            .background(Color(white: 0.24))
            Color(white: 0.17)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 5, style: .continuous))
    }

    /// The sides (together) and the bottom edge.
    private func handles(stage: CGRect, band: CGFloat) -> some View {
        let scale = scale
        let windowBottom = stage.maxY - (onTop ? band : 0)
        return ZStack(alignment: .topLeading) {
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .fill(.white)
                    .frame(width: 5, height: 22)
                    .shadow(radius: 1)
                    .position(x: side < 0 ? stage.minX + AnchorStageLayout.shoulder * scale : stage.maxX - AnchorStageLayout.shoulder * scale,
                              y: (stage.minY + windowBottom) / 2)
                    .gesture(DragGesture().onChanged { value in
                        let width = (size.size(on: screen).width + 2 * side * value.translation.width / scale)
                        draft = CGSize(width: Self.clamp(width, AnchorSizePreference.widthRange, screen.frame.width), height: current.height)
                    }.onEnded { _ in commit() })
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            }
            Capsule()
                .fill(.white)
                .frame(width: 22, height: 5)
                .shadow(radius: 1)
                .position(x: stage.midX, y: windowBottom)
                .gesture(DragGesture().onChanged { value in
                    let height = size.size(on: screen).height + value.translation.height / scale
                    draft = CGSize(width: current.width,
                                   height: Self.clamp(height, AnchorSizePreference.heightRange, screen.frame.height - 2 * screen.band))
                }.onEnded { _ in commit() })
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        }
    }

    private static func clamp(_ value: CGFloat, _ range: ClosedRange<Double>, _ most: CGFloat) -> CGFloat {
        min(max(value, CGFloat(range.lowerBound)), min(CGFloat(range.upperBound), most)).rounded()
    }

    private func commit() {
        guard let draft else { return }
        write(draft)
        self.draft = nil
    }

    /// A size set by hand: Custom from then on.
    private func write(_ value: CGSize) {
        size = AnchorSizePreference(width: Double(value.width), height: Double(value.height))
    }
}
