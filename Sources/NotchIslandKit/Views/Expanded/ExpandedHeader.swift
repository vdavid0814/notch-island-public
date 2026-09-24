import SwiftUI

/// The expanded island's top band, split around the notch: page picker on the leading side; battery,
/// pin and settings on the trailing side. While a volume or brightness change is being shown, the
/// trailing side becomes a compact level control instead of collapsing the panel into a banner.
struct ExpandedHeader: View {
    let split: NotchSplit
    let height: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        NotchSplitBand(split: split, height: height) {
            PagePicker()
        } trailing: {
            ZStack(alignment: .trailing) {
                if case .level(let kind)? = model.banners.current {
                    LevelCapsule(kind: kind)
                        .transition(.blurReplace)
                } else {
                    HeaderAccessories()
                        .transition(.blurReplace)
                }
            }
            .animation(Motion.content, value: model.banners.current)
        }
        // Header controls are sized by the notch-height band, whatever the island scale.
        .controlSize(Metrics.Control.size(fittingBand: height))
    }
}

/// The pages as an icon-only liquid segment.
private struct PagePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var island = model.island
        IslandLiquidSegment(
            items: ExpandedPage.allCases.map { .init(value: $0, title: $0.title, systemImage: $0.systemImage) },
            selection: $island.page,
            iconOnly: true
        )
        .fixedSize()
    }
}

/// Battery, pin, settings.
private struct HeaderAccessories: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Metrics.Spacing.small) {
            let power = model.power.state
            if power.hasBattery {
                BatteryIndicator(state: power)
                    .padding(.trailing, Metrics.Spacing.xSmall)
            }
            Button {
                model.perform(.assistant)
            } label: {
                Label("Siri", systemImage: "siri")
            }
            .buttonStyle(.islandGlass(.circle))
            .help("Siri")
            let isPinned = model.island.isPinned
            Button {
                model.controller.togglePinned()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.fill" : "pin")
                    .contentTransition(.symbolEffect(.replace))
            }
            // Pinned is a mode, so it reads as an active control, like a CAD toggle that is on.
            .buttonStyle(.islandGlass(.circle, prominent: isPinned))
            .help(isPinned ? "Unpin — close when the pointer leaves" : "Pin — keep open")
            Button {
                model.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.islandGlass(.circle))
            .help("Settings")
        }
    }
}

/// "76%" with the battery symbol; green while charging, red when low, orange in Low Power Mode.
struct BatteryIndicator: View {
    let state: PowerState

    var body: some View {
        HStack(spacing: Metrics.Spacing.xSmall) {
            Text(IslandFormat.percent(Double(state.level) / 100))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Image(systemName: IslandFormat.batterySymbol(level: state.level, charging: state.isCharging))
                .symbolRenderingMode(state.tint == .low ? .monochrome : .hierarchical)
                .foregroundStyle(state.tint.style)
                .imageScale(.large)
        }
        .animation(Motion.content, value: state.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery \(IslandFormat.percent(Double(state.level) / 100))"))
    }
}

/// Symbol + slider, shown in the header while a level banner is current.
private struct LevelCapsule: View {
    let kind: LevelKind

    @Environment(AppModel.self) private var model

    var body: some View {
        let reading = model.levels.reading(kind)
        HStack(spacing: Metrics.Spacing.small) {
            LevelSymbol(kind: kind, reading: reading)
                .frame(width: 18)
            LevelSlider(kind: kind)
                .frame(width: Metrics.Expanded.headerSliderWidth)
            LevelValue(reading: reading)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 32, alignment: .trailing)
        }
    }
}
