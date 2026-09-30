import SwiftUI

/// The expanded island's top band, split around the notch, as the user arranged it
/// (`HeaderLayout`; by default the page picker on the leading side; battery, Siri, pin and settings
/// on the trailing side). While a volume or brightness change is being shown, the trailing side
/// becomes a compact level control instead of collapsing the panel into a banner.
struct ExpandedHeader: View {
    let split: NotchSplit
    let height: CGFloat

    @Environment(AppModel.self) private var model
    /// Hidden (kept for the next open): a level banner is the island's own then, not the header's.
    @Environment(\.isIslandPanelHidden) private var isHidden

    var body: some View {
        NotchSplitBand(split: split, height: height) {
            HeaderEar(side: .leading, room: split.earWidth)
        } trailing: {
            ZStack(alignment: .trailing) {
                if !isHidden, let kind = model.banners.current?.levelKind {
                    LevelCapsule(kind: kind)
                        .transition(.blurReplace)
                } else {
                    HeaderEar(side: .trailing, room: split.earWidth)
                        .transition(.blurReplace)
                }
            }
            .animation(Motion.content, value: isHidden ? nil : model.banners.current)
        }
        // Header controls are sized by the notch-height band, whatever the island scale.
        .controlSize(Metrics.Control.size(fittingBand: height))
    }
}

/// One side of the bar: the user's items that exist now and fit beside the notch (`HeaderFit`), in
/// their order, and a "⋯" menu at the notch's end for the rest.
struct HeaderEar: View {
    let side: HeaderSide
    /// The ear's width beside the notch.
    let room: CGFloat

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        let fit = Self.fit(model: model, side: side, room: room, size: controlSize)
        HStack(spacing: HeaderFit.spacing) {
            if side == .trailing, fit.hasOverflow { HeaderOverflowMenu(items: fit.overflow) }
            ForEach(fit.shown) { item in
                HeaderItemView(item: item, pages: fit.pages)
            }
            if side == .leading, fit.hasOverflow { HeaderOverflowMenu(items: fit.overflow) }
        }
    }

    /// What the side shows on this Mac now: its items that exist (no battery on a desktop Mac, Now
    /// Playing only while something plays…), fitted into `room`.
    /// `layout`: another arrangement than the stored one (the editor's, while a chip is dragged);
    /// `items`: the side's items given outright (the arrangement without the dragged one).
    static func fit(model: AppModel, side: HeaderSide, room: CGFloat, size: ControlSize, layout: HeaderLayout? = nil,
                    items: [HeaderItem]? = nil) -> HeaderFit {
        let header = layout ?? model.preferences.header
        let items = (items ?? header.items(on: side)).filter { exists($0, model: model) }
        return HeaderFit(items: items, side: side, room: room, size: size, pages: header.pages(among: model.availablePages)) { pages in
            pickerWidth(pages: pages, size: size)
        }
    }

    /// The page picker's width with these pages: as measured, or the estimate until it has been shown.
    static func pickerWidth(pages: [ExpandedPage], size: ControlSize) -> CGFloat {
        PagePicker.width(pages: pages, size: size)
    }

    static func exists(_ item: HeaderItem, model: AppModel) -> Bool {
        switch item {
        case .battery: model.power.state.hasBattery
        case .nowPlaying: model.media.item != nil
        case .anchorWindow: model.isWindowAnchored
        case .pages, .siri, .pin, .settings, .clock, .toggle, .screenshot, .lock: true
        }
    }
}

/// One item of the bar.
struct HeaderItemView: View {
    let item: HeaderItem
    /// The pages the picker shows.
    let pages: [ExpandedPage]

    @Environment(AppModel.self) private var model

    var body: some View {
        switch item {
        case .pages:
            PagePicker(pages: pages)
        case .battery:
            // Drawn as it always was; pressed, it only dims.
            Button {
                HeaderItemView.perform(.battery, model: model)
            } label: {
                // Clickable a little beyond the glyph, as tall as the buttons beside it.
                BatteryIndicator(state: model.power.state)
                    .padding(Metrics.Spacing.xSmall)
                    .contentShape(.rect)
                    .padding(-Metrics.Spacing.xSmall)
            }
            .buttonStyle(.plain)
            .controlHelp("Battery")
            .padding(.trailing, Metrics.Spacing.xSmall)
        case .siri:
            circle("Siri", "siri", help: "Siri")
        case .pin:
            let isPinned = model.island.isPinned
            Button {
                HeaderItemView.perform(.pin, model: model)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.fill" : "pin")
                    .contentTransition(.symbolEffect(.replace))
            }
            // Pinned is a mode, so it reads as an active control, like a CAD toggle that is on.
            .islandButton(.circle, prominent: isPinned)
            .controlHelp(isPinned ? "Unpin — close when the pointer leaves" : "Pin — keep open")
        case .settings:
            circle("Settings", "gearshape", help: "Settings")
        case .clock:
            HeaderClock()
        case .nowPlaying:
            HeaderNowPlaying()
        case .toggle(let toggle):
            HeaderSwitch(control: toggle.control)
        case .anchorWindow:
            circle("Release Window", "rectangle.topthird.inset.filled", help: "Release the window held under the notch")
        case .screenshot:
            circle("Screenshot", "camera.viewfinder", help: "Screenshot")
        case .lock:
            circle("Lock Screen", "lock.fill", help: "Lock Screen")
        }
    }

    private func circle(_ title: LocalizedStringKey, _ symbol: String, help: String) -> some View {
        Button {
            HeaderItemView.perform(item, model: model)
        } label: {
            Label(title, systemImage: symbol)
        }
        .islandButton(.circle)
        .controlHelp(help)
    }

    /// What a click on the item does (in the bar and in the "⋯" menu alike).
    static func perform(_ item: HeaderItem, model: AppModel) {
        switch item {
        case .pages, .clock: break
        case .battery: model.controller.expand(page: .battery, userInitiated: true)
        case .siri: model.perform(.assistant)
        case .pin: model.controller.togglePinned()
        case .settings: model.showSettings()
        case .nowPlaying: model.media.send(.togglePlayPause)
        case .toggle(let toggle):
            // Its state now, not the one last read: nothing reads it while only the menu shows it.
            let control = toggle.control
            model.controls.set(control, to: control.isAction ? true : !model.controls.liveState(of: control))
        case .anchorWindow: model.releaseAnchoredWindow()
        case .screenshot: model.controls.set(.screenshot, to: true)
        case .lock: model.controls.set(.lockScreen, to: true)
        }
    }
}

/// The items that found no room beside the notch, as a menu.
private struct HeaderOverflowMenu: View {
    let items: [HeaderItem]

    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(items) { item in
                switch item {
                case .clock:
                    Text(Date.now, format: HeaderClock.format)
                case .battery:
                    Button("Battery — \(model.power.state.level) %", systemImage: item.systemImage) {
                        HeaderItemView.perform(item, model: model)
                    }
                case .pin:
                    Button(model.island.isPinned ? "Unpin" : "Keep Open", systemImage: model.island.isPinned ? "pin.fill" : "pin") {
                        HeaderItemView.perform(item, model: model)
                    }
                case .nowPlaying:
                    Button(model.media.isPlaying ? "Pause" : "Play", systemImage: model.media.isPlaying ? "pause.fill" : "play.fill") {
                        HeaderItemView.perform(item, model: model)
                    }
                default:
                    Button(item.title, systemImage: item.systemImage) { HeaderItemView.perform(item, model: model) }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        .islandButton(.circle)
        .fixedSize()
        .controlHelp("More")
    }
}

/// The time, in the bar's type: a new minute redraws it, and nothing does while the panel is hidden.
private struct HeaderClock: View {
    @Environment(\.controlSize) private var controlSize

    /// Hours and minutes as the Mac shows them, without AM or PM: never wider than "88:88".
    static let format = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()

    var body: some View {
        PanelTimelineView(.everyMinute) { context in
            Text(context.date, format: Self.format)
                .font(Metrics.Control.font(controlSize))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: HeaderFit.clock(controlSize))
        .accessibilityLabel("Time")
    }
}

/// What is playing: its cover (a click opens its widget's page) and play/pause.
private struct HeaderNowPlaying: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        let side = HeaderFit.cover(controlSize)
        HStack(spacing: 4) {
            Button {
                model.controller.expand(page: .home, userInitiated: true)
            } label: {
                ArtworkView(image: model.media.artwork, bundleIdentifier: model.media.item?.bundleIdentifier, minimumRadius: 4)
                    .frame(width: side, height: side)
                    .containerShape(.rect(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .controlHelp(model.media.item?.title ?? "Now Playing")
            let isPlaying = model.media.isPlaying
            Button {
                HeaderItemView.perform(.nowPlaying, model: model)
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .islandButton(.circle)
            .controlHelp(isPlaying ? "Pause" : "Play")
        }
    }
}

/// A switch of the system (Wi-Fi, Bluetooth, Dark Mode) or an action (Focus): read while it is
/// shown — never in a picture of the bar (reading Bluetooth asks for its permission) — and lit
/// while on.
private struct HeaderSwitch: View {
    let control: SystemControl

    @Environment(AppModel.self) private var model
    @Environment(\.isHeaderPicture) private var isPicture

    var body: some View {
        let isOn = !control.isAction && model.controls.isOn(control)
        Button {
            model.controls.set(control, to: control.isAction ? true : !isOn)
        } label: {
            Label(control.title, systemImage: control.symbol(on: isOn || control.isAction))
                .contentTransition(.symbolEffect(.replace))
        }
        .islandButton(.circle, prominent: isOn)
        .controlHelp(control.title)
        .whileShown {
            if !isPicture, !control.isAction { model.controls.startObserving(control) }
        } stop: {
            if !isPicture, !control.isAction { model.controls.stopObserving(control) }
        }
    }
}

/// The given pages as the system's tab picker, symbols only (the titles are the tooltips and the
/// accessibility labels).
private struct PagePicker: View {
    let pages: [ExpandedPage]

    @Environment(AppModel.self) private var model
    @Environment(\.controlSize) private var controlSize

    /// The bar's drawn width per pages and control size. Once it is known, whether it fits is
    /// arithmetic (`HeaderFit`): a `ViewThatFits` measured the system's bar again on every open.
    /// Observed: the system's bar measures itself wider a turn after it appears
    /// (`SegmentedControlRemeasure`), and what is laid out by its width (the stage's chip and its
    /// ring, the other items) follows.
    @MainActor @Observable fileprivate final class Widths {
        var values: [WidthKey: CGFloat] = [:]
    }
    private static let widths = Widths()
    fileprivate struct WidthKey: Hashable { let pages: [ExpandedPage], size: ControlSize }

    /// The picker's width with these pages: as measured, or the estimate until it has been shown.
    static func width(pages: [ExpandedPage], size: ControlSize) -> CGFloat {
        widths.values[WidthKey(pages: pages, size: size)] ?? HeaderFit.pickerEstimate(pages: pages, size: size)
    }

    var body: some View {
        let island = model.island
        let key = WidthKey(pages: pages, size: controlSize)
        // A page shown without its segment (the battery's, left out where it would reach under the
        // notch, or a page the user hid): no segment is selected.
        Picker("Page", selection: Binding { model.panelPage } set: { island.page = $0 }) {
            ForEach(pages, id: \.self) { page in
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // Written only when it changes: every reader lays out again.
            if Self.widths.values[key] != width { Self.widths.values[key] = width }
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
    /// The bar as a picture (Settings' stage): nothing in it reads the system.
    @Entry var isHeaderPicture = false
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
