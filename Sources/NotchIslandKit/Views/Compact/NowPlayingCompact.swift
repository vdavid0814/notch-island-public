import SwiftUI

/// Artwork in the leading ear, the equalizer in the trailing one — each in a square of the same
/// size at the same inset, so the pill reads as symmetric around the notch.
struct NowPlayingCompact: View {
    let split: NotchSplit
    let height: CGFloat
    let glyphSide: CGFloat

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// On the charger, or a Mac without a battery.
    private var onCharger: Bool {
        !model.power.state.hasBattery || model.power.state.isPluggedIn
    }

    var body: some View {
        let media = model.media
        NotchSplitBand(split: split, height: height) {
            ArtworkView(
                image: media.artwork,
                bundleIdentifier: media.item?.bundleIdentifier,
                minimumRadius: Metrics.Compact.artworkMinimumRadius
            )
            .frame(width: glyphSide, height: glyphSide)
        } trailing: {
            // Still bars under Reduce Motion or when the system asks for less work (Low Power Mode,
            // thermal pressure): the bars are decoration, the artwork already says "playing".
            EqualizerView(
                isAnimating: media.isPlaying && !reduceMotion && !model.activity.prefersReducedWork,
                onBattery: model.power.state.hasBattery && !model.power.state.isPluggedIn,
                // The cover's square: at full level a bar is as tall as the artwork opposite.
                size: CGSize(width: glyphSide, height: glyphSide),
                barWidth: glyphSide * Metrics.Compact.equalizerBarShare,
                tint: media.artworkColor,
                palette: media.artworkPalette,
                // Settings ▸ General ▸ Music Bars: one choice on battery, one on the charger.
                listensToAudio: (onCharger ? model.preferences.musicBarsOnPower : model.preferences.musicBars) == .followMusic,
                continuous: model.preferences.musicBarsContinuousOnPower && onCharger
            )
                .frame(width: glyphSide, height: glyphSide)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        guard let item = model.media.item else { return Text("Now Playing") }
        return model.media.isPlaying
            ? Text("Playing \(item.title) by \(item.artist)")
            : Text("Paused: \(item.title) by \(item.artist)")
    }
}
