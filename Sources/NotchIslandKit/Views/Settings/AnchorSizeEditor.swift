import SwiftUI

/// Settings ▸ Live Activities ▸ Window Anchor: the size every anchored window is given, picked by
/// name beside the title, on a picture of the notch screen with the window hanging from the notch.
struct AnchorSizeEditor: View {
    @Binding var size: AnchorSizePreference
    let screen: AnchorScreen
    /// The live copy is in use: the window drawn on its stage, else under the menu bar.
    var onTop = true
    /// Dragged up by the tab at its top.
    var isRaised = false

    /// The picture's width; its height follows the screen's.
    static let pictureWidth: CGFloat = 380
    /// About as wide as the name or Release beside the notch, in screen points.
    static let earWidth: CGFloat = 90

    private var current: CGSize { size.size(on: screen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: SettingsForm.titleGap) {
                InfoLabel("Size when anchored", "Every window you anchor opens at this size, centred under the notch. The sizes follow the screen.")
                Spacer(minLength: 0)
                Picker("Size", selection: choice) {
                    ForEach(AnchorSizePreset.named) { Text(Self.title($0)).tag($0) }
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
            }
            picture
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
    }

    private var scale: CGFloat { Self.pictureWidth / max(screen.frame.width, 1) }

    private static func title(_ preset: AnchorSizePreset) -> String {
        switch preset {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .tall: String(localized: "Tall")
        case .wide: String(localized: "Wide")
        case .automatic, .custom: ""
        }
    }

    /// The bar's pick: nothing shows as picked while a size saved earlier (Automatic, by hand) is in use.
    private var choice: Binding<AnchorSizePreset> {
        Binding(get: { size.choice }, set: { picked in
            withAnimation(Motion.content) { size = AnchorSizePreference(preset: picked) }
        })
    }

    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    private var picture: some View {
        let scale = scale
        let screenSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        let band = screen.band * scale
        let window = CGSize(width: current.width * scale, height: current.height * scale)
        // As `AnchorStageLayout`: raised, a slim bar under the window and the picture as high as it
        // allows; else the picture where the window is and the band above it black.
        let barHeight = onTop && isRaised ? AnchorStageLayout.barHeight * scale : 0
        let top = onTop ? max(0, band - barHeight) : band
        let stage = CGRect(x: (screenSize.width - window.width) / 2 - AnchorStageLayout.shoulder * scale, y: onTop ? 0 : band,
                           width: window.width + 2 * AnchorStageLayout.shoulder * scale,
                           height: onTop ? top + window.height + barHeight : window.height)
        return ZStack(alignment: .topLeading) {
            // The desktop, the menu bar and the notch.
            // The preview wallpaper, as in Settings' other pictures.
            DesktopBackdrop(style: backdrop, detail: .miniature)
                .frame(width: screenSize.width, height: screenSize.height)
            PreviewMenuBar(height: band, notchWidth: stage.width, darkText: backdrop.prefersDarkMenuBar, backing: backdrop.menuBarBacking)
                .frame(width: screenSize.width)
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
                .offset(x: stage.minX + AnchorStageLayout.shoulder * scale, y: top)
            // The notch; with the name and Release beside it, as wide as those.
            let notch = (screen.notch.width + (onTop ? 2 * Self.earWidth : 0)) * scale
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(.black)
                .frame(width: notch, height: band)
                .offset(x: (screenSize.width - notch) / 2)
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
}
