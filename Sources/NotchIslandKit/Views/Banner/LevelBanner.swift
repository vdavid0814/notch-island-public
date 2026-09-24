import SwiftUI

/// Volume / brightness: the level's symbol and percentage flank the notch, the native slider sits
/// below with the range's end symbols, like the system's own sound and display sliders.
struct LevelBanner: View {
    let kind: LevelKind

    @Environment(AppModel.self) private var model

    var body: some View {
        let reading = model.levels.reading(kind)
        BannerLayout(kind: .level(kind)) {
            LevelSymbol(kind: kind, reading: reading)
        } headerTrailing: {
            LevelValue(reading: reading)
        } row: {
            if kind == .volume {
                Button {
                    model.levels.toggleMute()
                } label: {
                    Label(reading.isMuted ? "Unmute" : "Mute", systemImage: reading.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .labelStyle(.iconOnly)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(reading.isMuted ? "Unmute" : "Mute")
            } else {
                Image(systemName: "sun.min.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            LevelSlider(kind: kind)
            Image(systemName: kind == .volume ? "speaker.wave.3.fill" : "sun.max.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }
}

/// The level's symbol, swapping with a replace effect as the value crosses thresholds.
struct LevelSymbol: View {
    let kind: LevelKind
    let reading: LevelReading

    var body: some View {
        let symbol = IslandFormat.levelSymbol(kind, reading: reading)
        Image(systemName: symbol)
            .foregroundStyle(reading.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .contentTransition(.symbolEffect(.replace))
            .animation(Motion.content, value: symbol)
            .accessibilityHidden(true)
    }
}

/// "62%", or "Muted".
struct LevelValue: View {
    let reading: LevelReading

    var body: some View {
        Group {
            if reading.isMuted {
                Text("Muted")
            } else {
                // A cross-fade, not `.numericText`: its rolling digits are drawn blurred and scaled
                // at a new size every frame, and each one lands in CoreGraphics' glyph cache, which
                // never gives them back (measured: about 290 KB more heap per level change).
                Text(IslandFormat.percent(reading.value))
                    .contentTransition(.opacity)
            }
        }
        .foregroundStyle(.secondary)
        .animation(Motion.content, value: IslandFormat.percentValue(reading.value))
    }
}

/// The native slider bound to a level. Dragging marks the island as busy (so it never auto-closes
/// under the pointer) and holds the banner up.
struct LevelSlider: View {
    let kind: LevelKind

    @Environment(AppModel.self) private var model

    var body: some View {
        let reading = model.levels.reading(kind)
        Slider(
            value: Binding(
                get: { model.levels.reading(kind).value },
                set: { model.levels.set(kind, to: $0) }
            ),
            in: 0...1
        ) {
            Text(kind == .volume ? "Volume" : "Brightness")
        } onEditingChanged: { editing in
            model.island.isInteracting = editing
            // Release the hold only if the pointer has also left; hovering keeps it held.
            model.banners.isHeld = editing || model.island.isHovering
        }
        .labelsHidden()
        .disabled(!reading.isAvailable)
    }
}
