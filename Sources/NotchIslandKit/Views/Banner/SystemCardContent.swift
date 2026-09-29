import AppKit
import SwiftUI

/// macOS's own volume card, line for line (measured from its window's image, macOS 27, in the card's
/// 293 × 64 pt): the output's name top left, a quiet speaker, the bar with the level in white and no
/// knob, seventeen step dots under it, and a loud speaker. Where the island lies on macOS's card,
/// every line falls on its own, so nothing doubles where the fade style's glass lets it through.
struct SystemVolumeCardContent: View {
    let name: String

    @Environment(AppModel.self) private var model

    static let size = CGSize(width: 293, height: 64)
    static let titleLeft: CGFloat = 17.5
    static let titleBaseline: CGFloat = 23.5
    static let titleSize: CGFloat = 11.75
    static let bar = CGRect(x: 31, y: 39, width: 222.5, height: 4)
    static let dots = (count: 17, first: 36.0, last: 248.5, y: 46.9, size: 1.6)
    static let quietSpeaker = CGPoint(x: 21.25, y: 42)
    static let loudSpeaker = CGPoint(x: 268, y: 42.25)
    static let speakerSize: CGFloat = 13
    /// The empty part of the bar and the dots: white this faint over the card (measured grey on grey).
    static let trackOpacity = 0.09
    static let dotOpacity = 0.22

    var body: some View {
        let reading = model.levels.reading(.volume)
        let level = reading.isMuted ? 0 : CGFloat(min(max(reading.value, 0), 1))
        ZStack(alignment: .topLeading) {
            Text(name)
                .font(.system(size: Self.titleSize, weight: .semibold))
                .lineLimit(1)
                .frame(width: Self.size.width - Self.titleLeft * 2, alignment: .leading)
                .position(x: Self.titleLeft - Self.sideBearing + (Self.size.width - Self.titleLeft * 2) / 2,
                          y: LiquidAirPodsContent.center(baseline: Self.titleBaseline, size: Self.titleSize, weight: .semibold))
            Button { model.levels.toggleMute() } label: {
                Image(systemName: reading.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: Self.speakerSize))
            }
            .buttonStyle(.plain)
            .help(reading.isMuted ? "Unmute" : "Mute")
            .position(Self.quietSpeaker)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: Self.speakerSize))
                .position(Self.loudSpeaker)
                .accessibilityHidden(true)
            Capsule()
                .fill(Color.white.opacity(Self.trackOpacity))
                .frame(width: Self.bar.width, height: Self.bar.height)
                .offset(x: Self.bar.minX, y: Self.bar.minY)
            // The level in the theme's colour (white by default, as macOS's).
            Capsule()
                .fill(Color.islandAccent)
                .frame(width: max(Self.bar.height, Self.bar.width * level), height: Self.bar.height)
                .opacity(level > 0 ? 1 : 0)
                .offset(x: Self.bar.minX, y: Self.bar.minY)
            ForEach(0..<Self.dots.count, id: \.self) { index in
                let step = (Self.dots.last - Self.dots.first) / Double(Self.dots.count - 1)
                Circle()
                    .fill(Color.white.opacity(Self.dotOpacity))
                    .frame(width: Self.dots.size, height: Self.dots.size)
                    .position(x: Self.dots.first + step * Double(index), y: Self.dots.y)
            }
            // The bar takes a click or a drag anywhere along it, as macOS's does.
            Color.clear
                .frame(width: Self.bar.width + 8, height: 22)
                .contentShape(.rect)
                .offset(x: Self.bar.minX - 4, y: Self.bar.midY - 11)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.island.isInteracting = true
                        let x = value.location.x - 4
                        model.levels.set(.volume, to: Double(min(max(x / Self.bar.width, 0), 1)))
                    }
                    .onEnded { _ in model.island.isInteracting = false })
                .accessibilityRepresentation {
                    Slider(value: Binding(get: { reading.value }, set: { model.levels.set(.volume, to: $0) })) { Text("Volume") }
                }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    /// The system font's first glyph starts this far in from where its line does.
    static let sideBearing: CGFloat = 0.8
}

/// The volume over macOS's card under the notch: the card's lines, where macOS draws them (centred
/// under the notch, one point below the menu bar's height and `top` more).
struct SystemVolumeCovering: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let notch = model.layout.notch
        SystemVolumeCardContent(name: LiquidCard.outputName())
            .padding(.top, notch.height + 1 + SystemVolumeCard.Kind.volume.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The AirPods over macOS's card under the notch, the same way.
struct SystemAirPodsCovering: View {
    let info: AirPodsInfo

    @Environment(AppModel.self) private var model

    var body: some View {
        let notch = model.layout.notch
        LiquidAirPodsContent(info: info)
            .frame(width: SystemVolumeCard.Kind.airPods.size.width, height: SystemVolumeCard.Kind.airPods.size.height)
            .padding(.top, notch.height + 1 + SystemVolumeCard.Kind.airPods.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
