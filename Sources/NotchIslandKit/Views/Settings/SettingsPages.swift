import AppKit
import FoundationModels
import SwiftUI

// Settings' pages. Grouped forms of the system's own controls: switches with their explanation
// under the title, sliders and pop-up menus in labelled rows, buttons that open System Settings.

// MARK: - General

/// General and appearance on one page: how the island looks first (surface cards, size), then how
/// it opens, how it behaves, and startup.
struct GeneralSettingsPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DesktopBackdropStyle.key) private var previewWallpaper: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var launchAtLogin = model.launchAtLogin
        Form {
            Section {
                Label("NotchIsland is still in beta. If some gestures don't work, check in About that its permissions are allowed.",
                      systemImage: "exclamationmark.triangle.fill")
                Label("Once they are, quit NotchIsland and open it again from Applications with Spotlight.",
                      systemImage: "arrow.clockwise")
            }
            .font(.callout)
            .foregroundStyle(SettingsPalette.secondary)

            Section {
                SurfacePicker(selection: $preferences.glassStyle)
                    // The thumbnails' corners (10 pt) concentric with the card's.
                    .padding(.vertical, SettingsForm.cardRadius - SettingsForm.inset - 10)
                if model.activity.isLowPowerMode {
                    Label("Low Power Mode is on: the island is drawn plain black to save battery.",
                          systemImage: "leaf.fill")
                        .font(.callout)
                        .foregroundStyle(SettingsPalette.secondary)
                }
            } header: {
                InfoLabel("Appearance", "What the island is made of: Liquid Glass that follows the system, solid black like the hardware island, or black at the notch fading into the glass below it.")
            }

            Section {
                ThemePicker(theme: $preferences.theme)
                    .settingsCornerElement(radius: ThemePicker.swatch / 2)
            } header: {
                InfoLabel("Theme", "The island's colour, where the system's blue was: sliders, selections, active controls and the widgets' glow. A colour of its own, or Mix: two colours of your choice blended.")
            }

            Section {
                PictureChoice(options: IslandScale.allCases, selection: $preferences.scale, title: \.title) { scale in
                    IslandSizePicture(scale: scale)
                }
                .padding(.vertical, SettingsForm.cardRadius - SettingsForm.inset - 10)
            } header: {
                InfoLabel("Size when open", "How large the island opens: the panel, its widgets and its controls. The pill beside the notch always matches the notch.")
            }

            Section("Opening") {
                Toggle(isOn: $preferences.openOnHover) {
                    InfoLabel("Open on hover", "The island opens when the pointer rests on the notch. Off: it opens with a click.")
                }
                LabeledContent {
                    DurationSlider(value: preferences.hoverDelay, range: Preferences.hoverDelayRange) {
                        preferences.hoverDelay = $0
                    }
                } label: {
                    InfoLabel("Hover delay", "How long the pointer has to rest on the notch before the island opens. Shorter opens faster; longer avoids opening it by accident.")
                }
                .disabled(!preferences.openOnHover)
                LabeledContent {
                    DurationSlider(value: preferences.closeDelay, range: Preferences.closeDelayRange) {
                        preferences.closeDelay = $0
                    }
                } label: {
                    InfoLabel("Close delay", "How long the island stays open after the pointer leaves it.")
                }
                LabeledContent {
                    DurationSlider(value: preferences.animationDuration, range: Motion.durationRange) {
                        preferences.animationDuration = $0
                    }
                } label: {
                    InfoLabel("Animation length", "How long the island takes to grow out of the notch and to shrink back into it. The picture shows it at this speed.")
                }
                SettingPictureRow { GrowthPicture(duration: preferences.animationDuration) }
            }

            Section("Behavior") {
                Toggle(isOn: $preferences.hideInFullscreen) {
                    InfoLabel("Hide during full-screen video",
                              preferences.showNowPlaying && preferences.showWebMedia
                              ? "While a video plays in full screen nothing appears by itself. Hovering the notch still opens the island."
                              : "Needs Now Playing and browser playback in Live Activities, which tell the island that a video is playing.")
                }
                .disabled(!preferences.showNowPlaying)
                Toggle(isOn: $preferences.hapticsEnabled) {
                    InfoLabel("Haptic feedback", "A light tap on the trackpad when the island opens, snaps or changes a value.")
                }
            }

            Section("Music Bars") {
                Picker(selection: $preferences.musicBars) {
                    ForEach(MusicBarsStyle.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("On battery", "Follow the Music: the bars move with what is playing — they listen to the Mac's sound (System Audio Recording; macOS shows a purple dot meanwhile). Nothing is recorded or kept. Animation: a set animation, nothing is listened to, the least energy.")
                }
                .choiceBar()
                Picker(selection: $preferences.musicBarsOnPower) {
                    ForEach(MusicBarsStyle.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("On the charger", "The same choice while the Mac is charging (a Mac without a battery always uses this one).")
                }
                .choiceBar()
                Toggle(isOn: $preferences.musicBarsContinuousOnPower) {
                    InfoLabel("Listen more often while charging", "On battery the bars listen 2 seconds in every 8 to save energy. On the charger they listen 0.8 seconds in every 1.8, so they follow the music closely.")
                }
                .disabled(preferences.musicBarsOnPower != .followMusic)
            }

            Section("Startup") {
                Toggle(isOn: $launchAtLogin.isEnabled) {
                    InfoLabel("Open at login", "NotchIsland starts when you log in.")
                }
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { launchAtLogin.openLoginItemsSettings() }
                    } label: {
                        Text("Waiting for approval")
                        Text("Allow NotchIsland in Login Items.")
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.callout).foregroundStyle(SettingsPalette.secondary)
                }
                Toggle(isOn: $preferences.showMenuBarIcon) {
                    InfoLabel("Show in menu bar", "The NotchIsland menu in the menu bar. Hidden, open NotchIsland from Finder or Spotlight to come back here.")
                }
            }

            Section {
                WallpaperRow(selection: $previewWallpaper)
            } header: {
                InfoLabel("Preview Wallpaper", "The desktop behind the island in Settings' pictures and in the widget studio: your own desktop picture, the macOS default wallpaper (dark or light), or a black and white test pattern that shows exactly what the glass lets through.")
            }
        }
    }
}

/// The surface styles as picture cards, like System Settings' Appearance: each shows the island
/// drawn in that style over a desktop.
/// The theme: the colour in use, and Mix, which opens the paint palette.
private struct ThemePicker: View {
    @Binding var theme: IslandTheme
    @State private var isMixing = false

    /// The colour's circle, the row's tallest part: the card is rounded concentric with it.
    static let swatch: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(theme.color)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                    .frame(width: Self.swatch, height: Self.swatch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.preset == .custom ? "Mixed" : theme.preset.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("The island's sliders, selections and glow")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsPalette.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { isMixing.toggle() }
                } label: {
                    Label(isMixing ? "Done" : "Mix", systemImage: isMixing ? "checkmark" : "paintpalette.fill")
                }
                // As far in from the side as the row's height puts it from the top: its capsule
                // concentric with the card's corner too.
                .padding(.trailing, (Self.swatch - 2 * SettingsForm.controlRadius) / 2)
            }
            .frame(minHeight: Self.swatch)
            if isMixing {
                ColorMixer(theme: $theme)
                    .padding(18)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.15, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.3, anchor: .topTrailing).combined(with: .opacity)))
            }
        }
    }
}

private struct SurfacePicker: View {
    @Binding var selection: IslandGlassStyle

    var body: some View {
        HStack(spacing: 14) {
            ForEach(IslandGlassStyle.allCases) { style in
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = style }
                } label: {
                    VStack(spacing: 7) {
                        SurfaceThumbnail(style: style)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selection == style ? Color.islandAccent : .white.opacity(0.12),
                                                  lineWidth: selection == style ? 3 : 1)
                            }
                        Text(style.title)
                            .font(.system(size: 12, weight: selection == style ? .semibold : .regular))
                            .foregroundStyle(selection == style ? .primary : SettingsPalette.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == style ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SurfaceThumbnail: View {
    let style: IslandGlassStyle

    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    var body: some View {
        let shape = IslandShape(bottomRadius: 13, shoulderRadius: 4)
        ZStack(alignment: .top) {
            DesktopBackdrop(style: backdrop, detail: .miniature)
            PreviewMenuBar(height: 12, notchWidth: 104, darkText: backdrop.prefersDarkMenuBar,
                           backing: backdrop.menuBarBacking)
            if style.hasGlassSurface {
                // What the glass lets through: the same desktop, blurred, inside the island.
                DesktopBackdrop(style: backdrop, detail: .miniature)
                    .blur(radius: 4)
                    .mask(alignment: .top) { shape.frame(width: 104, height: 40) }
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.85)).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(.white.opacity(0.8)).frame(width: 34, height: 3)
                    Capsule().fill(.white.opacity(0.45)).frame(width: 24, height: 3)
                }
                Spacer(minLength: 0)
                Circle().fill(.white.opacity(0.85)).frame(width: 9, height: 9)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .frame(width: 104, height: 40, alignment: .top)
            .islandSurfaceShade(style, solidDepth: 12, in: shape)
            // A drawn stand-in for the glass: three live glass surfaces here kept ~130 MB of
            // graphics memory while General was open (measured), for a picture this small.
            .background { ThumbnailGlass(style: style, shape: shape) }
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                    .fill(.black)
                    .frame(width: 34, height: 12)
            }
        }
        .frame(width: 150, height: 94)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
    }
}

/// How long a notice stays up, 0.5–10 s in half seconds.
private struct NoticeDuration: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: Binding(get: { value }, set: { new in
                    let snapped = (new * 2).rounded() / 2
                    if snapped != value { value = snapped }
                }), in: Preferences.noticeDurationRange)
                .labelsHidden()
                .tint(Color.islandAccent)
                .frame(minWidth: 160, maxWidth: 240)
                ReservedWidthText(Self.format(value), fitting: [Self.format(Preferences.noticeDurationRange.lowerBound),
                                                                Self.format(Preferences.noticeDurationRange.upperBound)])
                    .foregroundStyle(SettingsPalette.secondary)
            }
        } label: {
            InfoLabel(title, "How long the notice stays in the island before it goes (it stays while the pointer is on it).")
        }
    }

    static func format(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
    }
}

/// A number chosen with the system's stepper, its value beside it.
private struct RowsStepper: View {
    let title: String
    let detail: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                // The stepper stays put while the number beside it changes length.
                ReservedWidthText(label(value), fitting: [label(range.lowerBound), label(range.upperBound)])
                    .foregroundStyle(SettingsPalette.secondary)
                Stepper(title, value: $value, in: range).labelsHidden()
            }
        } label: {
            InfoLabel(title, detail)
        }
    }

    private func label(_ count: Int) -> String {
        unit.isEmpty ? "\(count)" : "\(count) \(unit)"
    }
}

/// The look of the island's surface in a thumbnail without live glass: black for Black, else
/// a smoked, faintly lit pane with the glass's bright rim.
private struct ThumbnailGlass<S: Shape>: View {
    let style: IslandGlassStyle
    let shape: S

    var body: some View {
        if style.hasGlassSurface {
            // Liquid Glass is smoked; the fade's glass is clear.
            shape.fill(.black.opacity(style == .fade ? 0.1 : 0.42))
                .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)],
                                                     startPoint: .top, endPoint: .bottom)) }
                .overlay { shape.stroke(.white.opacity(style == .liquidGlass ? 0.35 : 0.12), lineWidth: 0.75) }
        } else {
            shape.fill(.black)
        }
    }
}

/// A slider with its value in milliseconds beside it, snapped to 10 ms (a slow drag does not
/// rewrite the same default dozens of times).
struct DurationSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let set: (Double) -> Void

    var body: some View {
        HStack {
            Slider(value: Binding(get: { value }, set: { new in
                let snapped = (new * 100).rounded() / 100
                if snapped != value { set(snapped) }
            }), in: range)
            .labelsHidden()
            .tint(Color.islandAccent)
            .frame(minWidth: 160, maxWidth: 240)
            ReservedWidthText(SettingsFormat.hoverDelay(value),
                              fitting: [SettingsFormat.hoverDelay(range.lowerBound), SettingsFormat.hoverDelay(range.upperBound)])
                .foregroundStyle(SettingsPalette.secondary)
        }
    }
}

/// A value beside a slider or a stepper, as wide as the widest it can read: sized by the text on
/// show, "1,500 ms" pushed the slider shorter than "120 ms" did, so the slider changed length
/// under the pointer while it was being dragged.
struct ReservedWidthText: View {
    let text: String
    let fitting: [String]

    init(_ text: String, fitting: [String]) {
        self.text = text
        self.fitting = fitting
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(Array(fitting.enumerated()), id: \.offset) { _, sample in
                Text(sample).hidden()
            }
            Text(text)
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Activities

struct ActivitiesSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section("Now Playing") {
                SettingPictureRow { NowPlayingPicture() }
                Toggle(isOn: $preferences.showNowPlaying) {
                    InfoLabel("Show what's playing", "The cover beside the notch and moving level bars while something plays, with the playback controls when the island opens.")
                }
                Toggle(isOn: $preferences.showWebMedia) {
                    InfoLabel("Browser and video playback", "YouTube and other videos in Safari and other browsers, and video apps like QuickTime or IINA. Read only while one of them is open, to save battery; Music and Spotify always report on their own.")
                }
                .disabled(!preferences.showNowPlaying)
            }

            Section("AirPods") {
                SettingPictureRow { AirPodsPicture() }
                Toggle(isOn: $preferences.showAirPods) {
                    InfoLabel("Show AirPods connecting", "When AirPods (or other Bluetooth headphones) connect: their picture, name and the batteries of each earbud and the case.")
                }
                Picker(selection: $preferences.airPodsSystemCard) {
                    ForEach(AirPodsSystemCard.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("With macOS's own card", "macOS shows its own AirPods card when they connect, and an app cannot turn it off. Cover It: the island's card comes at once, above it, and hides it. After It: the island's waits until macOS's has gone. Don't Show: only macOS's.")
                }
                .choiceBar()
                .disabled(!preferences.showAirPods)
                Toggle(isOn: $preferences.liquidAirPods) {
                    InfoLabel("Flow out to macOS's card", "Where macOS puts its card away from the notch (on the desktop, beside a tiled window), the island's card runs out of the notch like a liquid, lies exactly on macOS's and runs back when it goes.")
                }
                .disabled(!preferences.showAirPods || preferences.airPodsSystemCard != .cover)
                NoticeDuration(title: "Shown for", value: $preferences.airPodsDuration)
                    .disabled(!preferences.showAirPods)
            }

            Section("Volume and Brightness") {
                Toggle(isOn: $preferences.showLevelHUD) {
                    InfoLabel("Show volume and brightness changes", "Changing the volume or the brightness shows it in the island.")
                }
                PictureChoice(options: LevelHUDStyle.allCases, selection: $preferences.levelStyle, title: \.title) { style in
                    LevelStylePicture(style: style)
                }
                .padding(.vertical, SettingsForm.cardRadius - SettingsForm.inset - 10)
                .disabled(!preferences.showLevelHUD)
                .opacity(preferences.showLevelHUD ? 1 : 0.5)
                NoticeDuration(title: "Shown for", value: $preferences.levelDuration)
                    .disabled(!preferences.showLevelHUD)
                Toggle(isOn: $preferences.liquidVolume) {
                    InfoLabel("Flow out to macOS's volume card", "An AirPods swipe (or anything else no key tap sees) brings macOS's own volume card up. Away from the notch (on the desktop, beside a tiled window) the island runs out to it like a liquid, lies exactly on it with its own slider, and runs back when it goes.")
                }
                .disabled(!preferences.showLevelHUD)
                Toggle(isOn: $preferences.replaceSystemHUD) {
                    InfoLabel("Replace the system HUD", "Handles the volume and brightness keys so only the island appears, not the system's own overlay. Needs Accessibility.")
                }
                .disabled(!preferences.showLevelHUD)
                if preferences.showLevelHUD, preferences.replaceSystemHUD, !model.permissions.accessibilityTrusted {
                    LabeledContent {
                        Button("Open System Settings…") { model.permissions.promptOrOpenAccessibilitySettings() }
                    } label: {
                        StatusLabel(title: "Accessibility access needed", tone: .attention)
                    }
                }
            }

            // Desktop Macs have no battery, so there is nothing to alert about.
            if model.power.state.hasBattery {
                Section("Battery") {
                    SettingPictureRow { PowerPicture() }
                    Toggle(isOn: $preferences.showPowerAlerts) {
                        InfoLabel("Power alerts", "Charger connected or removed, fully charged, and low battery at 20, 10 and 5 %.")
                    }
                    NoticeDuration(title: "Shown for", value: $preferences.powerDuration)
                        .disabled(!preferences.showPowerAlerts)
                }
            }

            if model.power.hasBattery {
                BatteryPageSection(settings: $preferences.battery)
            }

            Section("Shelf and Timer") {
                Toggle(isOn: $preferences.shelfEnabled) {
                    InfoLabel("Shelf", "Drag files onto the notch to keep them at hand, then drag them out or AirDrop them.")
                }
                Toggle(isOn: $preferences.timerSound) {
                    InfoLabel("Play a sound when a timer ends", "The timer's alert sound plays with the notice in the island.")
                }
            }
        }
    }
}

/// The battery page's chart (the header's battery opens the page): its style, range, colours and
/// what it marks. The chart's context menu sets the style and range too.
private struct BatteryPageSection: View {
    @Binding var settings: BatteryDisplaySettings

    var body: some View {
        Section {
            Picker(selection: $settings.style) {
                ForEach(BatteryChartStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                InfoLabel("Chart", "Bars: the level at the end of each quarter hour, as the iPhone shows it. Area and Line: every reading.")
            }
            .choiceBar()
            Picker(selection: $settings.range) {
                ForEach(BatteryChartRange.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                InfoLabel("Shows", "Today from midnight, or the last 24 or 48 hours (in half hours).")
            }
            .choiceBar()
            LabeledContent {
                HStack(spacing: 12) {
                    ColorWell(color: $settings.normalColor).help("On battery")
                    ColorWell(color: $settings.chargingColor).help("Charging")
                    ColorWell(color: $settings.lowColor).help("Below 20 %")
                }
            } label: {
                InfoLabel("Colours", "On battery, while charging, and below 20 % on battery. Automatic: white, green and red.")
            }
            Toggle(isOn: $settings.showsGaps) {
                InfoLabel("Mark gaps", "Hatching where nothing is known: the Mac asleep, or NotchIsland not running.")
            }
            Toggle(isOn: $settings.shadesDisplayOff) {
                InfoLabel("Shade display off", "A faint band where the displays were off.")
            }
            Toggle(isOn: $settings.showsCaptions) {
                InfoLabel("Captions", "When the battery was last charged, over the chart, and the percentages beside it.")
            }
        } header: {
            InfoLabel("Battery Page", "Click the battery at the top of the open island: the level, how long it lasts, the battery's health and the day's charge.")
        }
    }
}

// MARK: - Spotlight (the assistant, called Siri in the code)

struct SiriSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        let siri = preferences.siri
        let intelligence = Self.intelligenceStatus
        let intelligenceAvailable = if case .available = SystemLanguageModel.default.availability { true } else { false }
        Form {
            Section {
                Toggle(isOn: $preferences.commandSpaceOpensSiri) {
                    InfoLabel("Open Spotlight with \(siri.shortcut.title)", "Spotlight opens in the notch instead of the system's search window. Needs Accessibility, which lets NotchIsland see the shortcut before the system does.")
                }
                Picker(selection: $preferences.siri.shortcut) {
                    ForEach(SiriShortcut.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Shortcut", "The keys that open Spotlight: Space with Command, Option or Control. ⌘Space replaces the system's search; the others leave it where it is.")
                }
                .choiceBar()
                .disabled(!preferences.commandSpaceOpensSiri)
                Toggle(isOn: $preferences.siri.shortcutCloses) {
                    InfoLabel("Shortcut again closes Spotlight", "Like the system's search: the same keys close Spotlight. Off, they only open it and Esc closes it.")
                }
                .disabled(!preferences.commandSpaceOpensSiri)
                Toggle(isOn: $preferences.siri.swipeOpens) {
                    InfoLabel("Swipe down on the notch", "With the pointer on the notch, a light two-finger swipe down on the trackpad (or the mouse wheel turned down) opens Spotlight.")
                }
                Toggle(isOn: $preferences.siri.hoverRevealsSuggestions) {
                    InfoLabel("Show suggestions on hover", "With the pointer over Spotlight, Applications, Files and Actions come down under the field. Off, only ↓ brings them.")
                }
                LabeledContent("Open Spotlight now") {
                    Button("Open") {
                        model.controller.closeSettings()
                        model.perform(.assistant)
                    }
                }
            } header: {
                Text("Opening")
            }

            Section {
                Picker(selection: $preferences.siri.panelSize) {
                    ForEach(SiriPanelSize.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Width", "How wide Spotlight's window grows out of the notch. The island's own size (General) scales it too.")
                }
                .choiceBar()
                RowsStepper(title: "List height", detail: "How many results — and how much of an answer — show before the list scrolls.",
                            value: $preferences.siri.listRows, range: SiriSettings.listRowsRange, unit: "rows")
            } header: {
                Text("Window")
            }

            Section("App Gallery") {
                Picker(selection: $preferences.siri.gallerySort) {
                    ForEach(SiriGallerySort.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Order", "The apps in the gallery (⌘1): the ones you used last first, or alphabetically.")
                }
                .choiceBar()
                RowsStepper(title: "Columns", detail: "Apps in a row. The gallery's window widens with them.",
                            value: $preferences.siri.galleryColumns, range: SiriSettings.galleryColumnsRange, unit: "apps")
                RowsStepper(title: "Rows", detail: "Rows of apps shown before the gallery scrolls: the gallery's height.",
                            value: $preferences.siri.galleryRows, range: SiriSettings.galleryRowsRange, unit: "rows")
            }

            Section {
                LabeledContent {
                    DurationSlider(value: siri.searchDelay, range: SiriSettings.searchDelayRange) {
                        preferences.siri.searchDelay = $0
                    }
                } label: {
                    InfoLabel("Search after typing", "How long Spotlight waits after a key before it searches. 0 ms searches on every key; a longer wait searches once you pause, which is lighter on the Mac.")
                }
                Picker(selection: $preferences.siri.matching) {
                    ForEach(SiriMatching.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Matching", Self.matchingDetail(siri.matching))
                }
                .choiceBar()
                RowsStepper(title: "Results of each kind", detail: "How many apps and how many files a search lists. Commands, System Settings panes, windows and emoji: up to two of each.",
                            value: $preferences.siri.resultsPerKind, range: SiriSettings.resultsRange, unit: "")
            } header: {
                Text("Search")
            }

            Section {
                Toggle(isOn: $preferences.siri.showsApplications) {
                    InfoLabel("Applications  ⌘1", "Apps in search results, and the app gallery.")
                }
                Toggle(isOn: $preferences.siri.showsFiles) {
                    InfoLabel("Files  ⌘2", "Documents in search results, and your recent files.")
                }
                Toggle(isOn: $preferences.siri.showsActions) {
                    InfoLabel("Actions  ⌘3", "The island's actions and your shortcuts in search results.")
                }
                Toggle(isOn: $preferences.siri.showsClipboard) {
                    InfoLabel("Clipboard  ⌘4", "The last 50 texts you copied, kept on this Mac; Return pastes one where you were typing. Copies that password managers mark as secret are never kept. Off, nothing is watched.")
                }
                Toggle(isOn: $preferences.siri.showsSystem) {
                    InfoLabel("System  ⌘5", "The island's commands (\u{201C}timer 10\u{201D} starts one), Control Center's switches with their state, Lock, Sleep, Restart, Empty Trash and System Settings' panes, found by name. Restart, Shut Down and Log Out ask first; Empty Trash asks for a second Return.")
                }
                Toggle(isOn: $preferences.siri.showsWindows) {
                    InfoLabel("Windows  ⌘6", "Your open apps and their windows: Return switches to one, ⌘H hides its app, ⌘Q quits it. Read only while Spotlight lists them; window names need Accessibility.")
                }
                Toggle(isOn: $preferences.siri.showsEmoji) {
                    InfoLabel("Emoji  ⌘7", "Emoji by name (\u{201C}thumbs up\u{201D}, \u{201C}fire\u{201D}): Return pastes one where you were typing, ⌘C copies it.")
                }
            } header: {
                InfoLabel("Suggestions", "What Spotlight lists and searches. A suggestion that is off does not open with its shortcut either.")
            }

            Section {
                ForEach(SiriFolder.allCases) { folder in
                    Toggle(isOn: Binding(
                        get: { preferences.siri.folders.contains(folder) },
                        set: { on in
                            if on { preferences.siri.folders.insert(folder) } else { preferences.siri.folders.remove(folder) }
                        }
                    )) {
                        Label(folder.title, systemImage: folder.systemImage)
                    }
                }
                Picker(selection: $preferences.siri.recentDays) {
                    ForEach(SiriSettings.recentDayChoices, id: \.self) { days in
                        Text(days == 7 ? "Last Week" : days == 30 ? "Last Month" : "Last 3 Months").tag(days)
                    }
                } label: {
                    InfoLabel("Recent files", "How far back the Files suggestion (⌘2) lists the files you used.")
                }
                .choiceBar()
            } header: {
                InfoLabel("Files", "The folders Spotlight searches for files. macOS asks for access to each of them the first time.")
            }
            .disabled(!siri.showsFiles)

            Section("Actions") {
                Toggle(isOn: $preferences.siri.includesIslandActions) {
                    InfoLabel("Island actions", "Play, Pause, Next, Timer, Stopwatch, Shelf and Settings, found by name.")
                }
                Toggle(isOn: $preferences.siri.includesShortcuts) {
                    InfoLabel("Your shortcuts", "Every shortcut from the Shortcuts app, found by name and run in the background.")
                }
            }
            .disabled(!siri.showsActions)

            Section("Answers") {
                LabeledContent {
                    StatusLabel(title: intelligence.title, tone: intelligence.tone)
                } label: {
                    InfoLabel("Apple Intelligence", intelligence.detail)
                }
                Toggle(isOn: $preferences.siri.usesIntelligence) {
                    InfoLabel("Answer with Apple Intelligence", "Questions are answered right in the notch, on this Mac. Off, they go to the web or ChatGPT.")
                }
                .disabled(!intelligenceAvailable)
                Picker(selection: $preferences.siri.answerLength) {
                    ForEach(SiriAnswerLength.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Answer length", "Brief: a few sentences. Detailed: a fuller answer, in paragraphs or a list where it helps.")
                }
                .choiceBar()
                .disabled(!intelligenceAvailable || !siri.usesIntelligence)
                Picker(selection: $preferences.siri.searchEngine) {
                    ForEach(SiriSearchEngine.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Search the web with", "Where \u{201C}Search the Web\u{201D} opens your question.")
                }
                Toggle(isOn: $preferences.siri.offersChatGPT) {
                    InfoLabel("Offer ChatGPT", "An \u{201C}Ask ChatGPT\u{201D} row that opens your question at chatgpt.com.")
                }
            }
        }
        .onChange(of: preferences.siri.shortcut) { _, shortcut in
            model.siriShortcutChanged(shortcut)
        }
    }

    private static func matchingDetail(_ matching: SiriMatching) -> String {
        switch matching {
        case .wordStart: "A word of the name starts with what you type: “saf” finds Safari."
        case .anywhere: "Anywhere in the name: “far” finds Safari."
        case .fuzzy: "The letters in order, gaps allowed: “sfr” finds Safari. Forgives typos and shorthand."
        }
    }

    private static var intelligenceStatus: SettingsFormat.Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            SettingsFormat.Status(title: "Available", detail: "Questions are answered on this Mac, privately. Return asks when you type a question.", tone: .ok)
        case .unavailable(let reason):
            SettingsFormat.Status(title: "Unavailable",
                                  detail: "Questions go to ChatGPT or the web instead (\(String(describing: reason))).",
                                  tone: .neutral)
        }
    }
}

// MARK: - About

/// The app, what it may access (and why), and its data.
/// The newest version: looked up when About opens, downloaded into Downloads and opened with a
/// click; the user drags it onto Applications (`AppUpdater`).
private struct UpdateSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updater = model.updater
        Section {
            switch updater.state {
            case .idle, .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for a new version…").foregroundStyle(SettingsPalette.secondary)
                }
            case .upToDate:
                LabeledContent {
                    Button("Check Again") { Task { await updater.check() } }
                } label: {
                    Label("NotchIsland \(updater.current) is the newest version", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            case .available(let release):
                LabeledContent {
                    Button("Download Update") { Task { await updater.download(release) } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(release.version) is available").font(.headline)
                        Text("You have \(updater.current).").foregroundStyle(SettingsPalette.secondary)
                    }
                }
                if !release.notes.isEmpty {
                    DisclosureGroup("What's New") {
                        Text(Self.notes(release.notes))
                            .font(.callout)
                            .foregroundStyle(SettingsPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            case .downloading(let release):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading version \(release.version)…").foregroundStyle(SettingsPalette.secondary)
                }
            case .ready(let release, let file):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Version \(release.version) is downloaded and open in Finder.").font(.headline)
                    Text("1. Quit NotchIsland.\n2. In the Finder window, drag NotchIsland onto Applications and choose Replace.\n3. Open NotchIsland from Applications.")
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    Spacer()
                    Button("Quit NotchIsland") { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                LabeledContent {
                    Button("Try Again") { Task { await updater.check() } }
                } label: {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("The update is downloaded from NotchIsland's GitHub releases into your Downloads folder. macOS checks it as any download.")
        }
        .task { if updater.state == .idle { await updater.check() } }
    }

    /// The release notes, Markdown as far as a text view shows it (bold, links), headings as bold
    /// lines; at most the first 40 lines.
    static func notes(_ markdown: String) -> AttributedString {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).prefix(40).map { line -> String in
            line.hasPrefix("## ") ? "**\(line.dropFirst(3))**" : String(line)
        }
        let text = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct AboutSettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingClear = false

    static let markSide: CGFloat = 72

    /// Privacy & Security ▸ Automation, where Music/Spotify access is granted or revoked.
    private static let automationSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    var body: some View {
        let count = model.shelf.items.count
        let trusted = model.permissions.accessibilityTrusted
        let media = SettingsFormat.mediaStatus(model.media.status, enabled: model.preferences.showNowPlaying)
        let keys = SettingsFormat.interceptionStatus(model.levels.interception)
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    AppMark(side: Self.markSide)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NotchIsland").font(.system(size: 20, weight: .bold))
                        Text(SettingsFormat.version(Bundle.main.infoDictionary))
                            .foregroundStyle(SettingsPalette.secondary)
                        Text("The notch as a Liquid Glass island: what's playing, timers, volume and brightness, charging, Spotlight, Control Center's switches and a shelf for files.")
                            .font(.callout)
                            .foregroundStyle(SettingsPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .settingsCornerElement(radius: AppMark.cornerRadius(side: Self.markSide))
            }

            UpdateSection()

            FeedbackSection()

            Section {
                PermissionRow(title: "Accessibility", detail: "⌘Space for Spotlight, and replacing the volume and brightness HUD.",
                              systemImage: "accessibility", tint: .blue,
                              status: trusted ? "Allowed" : "Not allowed", tone: trusted ? .ok : .attention) {
                    if !trusted {
                        Button("Allow…") { model.permissions.promptOrOpenAccessibilitySettings() }
                    }
                }
                PermissionRow(title: "Now Playing", detail: media.detail,
                              systemImage: "play.circle.fill", tint: .pink, status: media.title, tone: media.tone) {
                    if case .on(_, .some) = model.media.status, model.preferences.showNowPlaying {
                        Link("Automation…", destination: Self.automationSettingsURL)
                    }
                }
                PermissionRow(title: "Volume and Brightness Keys", detail: keys.detail,
                              systemImage: "keyboard.fill", tint: .gray, status: keys.title, tone: keys.tone) {}
                PermissionRow(title: "Bluetooth", detail: "Only the Bluetooth widget reads it, to show and switch Bluetooth.",
                              systemImage: "wave.3.right", tint: .blue, status: "Asked when first used", tone: .neutral) {}
            } header: {
                Text("Permissions")
            } footer: {
                Text("NotchIsland works without any of these; each one turns on the feature it names.")
            }

            DiagnosticsSection()

            Section("Shelf") {
                LabeledContent("Items on the Shelf") {
                    Text(count.formatted()).foregroundStyle(SettingsPalette.secondary)
                }
                LabeledContent("Remove every item") {
                    Button("Clear Shelf…", role: .destructive) { isConfirmingClear = true }
                        .disabled(count == 0)
                        .popover(isPresented: $isConfirmingClear, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Clear the Shelf?").font(.headline)
                                Text("All items are removed from the Shelf. The files themselves are not touched.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Spacer()
                                    Button("Cancel") { isConfirmingClear = false }
                                        .keyboardShortcut(.cancelAction)
                                    Button("Clear Shelf", role: .destructive) {
                                        model.shelf.clear()
                                        isConfirmingClear = false
                                    }
                                    .keyboardShortcut(.defaultAction)
                                }
                            }
                            .padding()
                            .frame(width: 280)
                        }
                }
            }
        }
    }
}

/// A permission: its tile, what it is for, its status, and the button that fixes it.
private struct PermissionRow<Action: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let status: String
    let tone: SettingsFormat.Tone
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 12) {
            SettingsTile(systemImage: systemImage, tint: tint, side: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action
            StatusLabel(title: status, tone: tone)
                .font(.callout)
                .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared

/// A status word with a meaningful system colour on the symbol only; the text stays primary.
struct StatusLabel: View {
    let title: String
    let tone: SettingsFormat.Tone

    var body: some View {
        Label {
            Text(title)
        } icon: {
            switch tone {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .neutral: Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
        }
    }
}
