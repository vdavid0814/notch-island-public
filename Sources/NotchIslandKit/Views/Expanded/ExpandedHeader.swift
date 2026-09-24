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
                if let kind = model.banners.current?.levelKind {
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

/// The pages as the system's tab picker, symbols only (the titles are the tooltips and the
/// accessibility labels).
private struct PagePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var island = model.island
        Picker("Page", selection: $island.page) {
            ForEach(ExpandedPage.allCases, id: \.self) { page in
                Label(page.title, systemImage: page.systemImage)
                    .labelStyle(.iconOnly)
                    .controlHelp(page.title)
                    .tag(page)
            }
        }
        // The system's tab bar (a segmented control in the tabs role): a glass capsule whose
        // selection slides between the pages.
        .choiceBar()
        .labelsHidden()
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
            .islandButton(.circle)
            .controlHelp("Siri")
            let isPinned = model.island.isPinned
            Button {
                model.controller.togglePinned()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.fill" : "pin")
                    .contentTransition(.symbolEffect(.replace))
            }
            // Pinned is a mode, so it reads as an active control, like a CAD toggle that is on.
            .islandButton(.circle, prominent: isPinned)
            .controlHelp(isPinned ? "Unpin — close when the pointer leaves" : "Pin — keep open")
            Button {
                model.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .islandButton(.circle)
            .controlHelp("Settings")
        }
    }
}

/// The battery with its percentage inside, like the Mac's menu bar: white (also while charging),
/// yellow in Low Power Mode, red below 20 %.
struct BatteryIndicator: View {
    let state: PowerState

    var body: some View {
        // Smaller than the menu bar's, so it sits level with the symbols in the header buttons beside it.
        BatteryGlyph(level: state.level, isCharging: state.isCharging, tint: state.tint, height: 9)
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

extension EnvironmentValues {
    /// Off where the header is only a picture (Settings' widget stage).
    @Entry var showsControlHelp = true
}

extension View {
    /// `help(_:)`, unless the environment turns tooltips off.
    func controlHelp(_ text: String) -> some View {
        modifier(ControlHelp(text: text))
    }
}

private struct ControlHelp: ViewModifier {
    let text: String
    @Environment(\.showsControlHelp) private var showsHelp

    func body(content: Content) -> some View {
        content.help(showsHelp ? text : "")
    }
}
