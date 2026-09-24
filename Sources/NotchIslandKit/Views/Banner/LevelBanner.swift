import SwiftUI

/// Volume / brightness under the notch: one row with the level's symbol (for volume, the mute
/// button), the native slider and the percentage. Nothing in the ears beside the notch — the symbol
/// and the number sit with the slider they describe.
struct LevelBanner: View {
    let kind: LevelKind

    @Environment(AppModel.self) private var model

    var body: some View {
        let reading = model.levels.reading(kind)
        BannerLayout(kind: .level(kind)) {
            EmptyView()
        } headerTrailing: {
            EmptyView()
        } row: {
            LevelLeadingSymbol(kind: kind, reading: reading)
                .frame(width: 22)
            LevelSlider(kind: kind)
            LevelValue(reading: reading)
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

/// The minimal style (`LevelHUDStyle.pill`): a pill beside the notch like Now Playing's, the
/// level's symbol in the leading ear and a small slider in the trailing one.
struct LevelPill: View {
    let kind: LevelKind

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let split = NotchSplit(
            layout: layout,
            presentation: .banner(.levelPill(kind)),
            outerInset: Metrics.Compact.inset + 4,
            clearance: Metrics.Compact.notchClearance + 4
        )
        let reading = model.levels.reading(kind)
        NotchSplitBand(split: split, height: layout.notch.height) {
            LevelLeadingSymbol(kind: kind, reading: reading)
                .font(.system(size: layout.notch.height * 0.42, weight: .semibold))
        } trailing: {
            LevelSlider(kind: kind)
                .controlSize(.mini)
        }
    }
}

/// Left of a level's slider: for volume the mute button (its symbol follows the level), for
/// brightness the level's symbol.
struct LevelLeadingSymbol: View {
    let kind: LevelKind
    let reading: LevelReading

    @Environment(AppModel.self) private var model

    var body: some View {
        if kind == .volume {
            Button {
                model.levels.toggleMute()
            } label: {
                Label {
                    Text(reading.isMuted ? "Unmute" : "Mute")
                } icon: {
                    LevelSymbol(kind: kind, reading: reading)
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            // As bright as the brightness symbol (a borderless button would grey it).
            .foregroundStyle(reading.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .help(reading.isMuted ? "Unmute" : "Mute")
        } else {
            LevelSymbol(kind: kind, reading: reading)
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
                // Changes in place, unanimated: a cross-fade of every step looked smeared while a key
                // is held, and `.numericText` leaks glyphs (its rolling digits are drawn at a new
                // size every frame and CoreGraphics' glyph cache keeps them: ~290 KB per change).
                Text(IslandFormat.percent(reading.value))
            }
        }
        .foregroundStyle(.secondary)
        .transaction { $0.animation = nil }
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
