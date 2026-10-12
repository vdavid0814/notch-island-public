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
                SurfacePicker(selection: $preferences.glassStyle, scale: preferences.scale, desktop: previewWallpaper)
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
                // Each size photographed in the style in use; drawn where there are no photographs.
                let style = preferences.glassStyle
                let photographed = IslandPhoto.image(desktop: previewWallpaper, style: style, scale: preferences.scale) != nil
                PictureChoice(options: IslandScale.allCases, selection: $preferences.scale, title: \.title,
                              filling: photographed ? IslandPhoto.size : MiniMetrics.sizePicture) { scale in
                    if let photo = IslandPhoto.image(desktop: previewWallpaper, style: style, scale: scale) {
                        IslandPhoto(image: photo)
                    } else {
                        IslandSizePicture(scale: scale)
                    }
                }
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
                InfoLabel("Preview Wallpaper", "The desktop behind the island in Settings' pictures and in the widget studio: the macOS default wallpaper (dark or light), or a black and white test pattern that shows exactly what the glass lets through.")
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
    /// The island's size in use: each style is shown at it.
    let scale: IslandScale
    /// The preview wallpaper: the style is shown over it.
    let desktop: DesktopBackdropStyle

    var body: some View {
        // The three share the card's whole width, as far from one another as from its edges:
        // their corners concentric with the card's.
        HStack(alignment: .top, spacing: SettingsForm.inset) {
            ForEach(IslandGlassStyle.allCases) { style in
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = style }
                } label: {
                    VStack(spacing: 7) {
                        Group {
                            // The island photographed in this style; drawn where there is no photograph.
                            if let photo = IslandPhoto.image(desktop: desktop, style: style, scale: scale) {
                                FittedPicture(drawn: IslandPhoto.size) { IslandPhoto(image: photo) }
                            } else {
                                FittedPicture(drawn: SurfaceThumbnail.size) { SurfaceThumbnail(style: style) }
                            }
                        }
                            .overlay {
                                RoundedRectangle(cornerRadius: SettingsForm.pictureRadius, style: .continuous)
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
    }
}

/// The open island in one surface style over a desktop, with its widgets: glass the desktop shows
/// through, solid black, or black that clears into glass towards its foot.
private struct SurfaceThumbnail: View {
    let style: IslandGlassStyle

    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle
    /// As the other pictures (`MiniDesktop`): drawn `k` times as large as its numbers say.
    @Environment(\.settingsPictureScale) private var k
    @Environment(\.settingsPictureRadius) private var radius

    // As drawn.
    static let size = CGSize(width: 150, height: 80)
    private static let island = CGSize(width: 108, height: 40)
    private static let menuBar: CGFloat = MiniMetrics.menuBar

    var body: some View {
        let shape = IslandShape(bottomRadius: MiniMetrics.islandRadius * k, shoulderRadius: 3 * k)
        let inset = MiniMetrics.widgetInset
        let size = MiniMetrics.size(Self.size.width, Self.size.height, scale: k)
        let island = MiniMetrics.size(Self.island.width, Self.island.height, scale: k)
        ZStack(alignment: .top) {
            // The miniature (960 px) fills a picture up to 480 pt wide at 2×.
            DesktopBackdrop(style: backdrop, detail: size.width <= 480 ? .miniature : .full)
            PreviewMenuBar(height: Self.menuBar * k, notchWidth: island.width, darkText: backdrop.prefersDarkMenuBar,
                           backing: backdrop.menuBarBacking)
            if style.hasGlassSurface {
                // What the glass lets through: the same desktop, blurred, inside the island.
                DesktopBackdrop(style: backdrop, detail: .miniature)
                    .blur(radius: 5 * k)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .top) { shape.frame(width: island.width, height: island.height) }
            }
            // As far from the island's sides and foot as from each other, their corners concentric
            // with the island's.
            MiniWidgets(width: Self.island.width - 2 * inset, height: Self.island.height - Self.menuBar - 2 * inset)
                .padding(.top, (Self.menuBar + inset) * k)
                .frame(width: island.width, height: island.height, alignment: .top)
                // A drawn stand-in for the glass: three live glass surfaces here kept ~130 MB of
                // graphics memory while General was open (measured), for a picture this small.
                .background { ThumbnailSurface(style: style, shape: shape, scale: k) }
                // The island floats over the desktop like the real one, with its soft shadow.
                .shadow(color: .black.opacity(0.35), radius: 3 * k, y: 1.5 * k)
            // The camera housing: whatever the island shows, the notch itself stays black.
            UnevenRoundedRectangle(bottomLeadingRadius: 3 * k, bottomTrailingRadius: 3 * k, style: .continuous)
                .fill(.black)
                .frame(width: MiniMetrics.notchWidth * k, height: Self.menuBar * k)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The island's surface in a thumbnail, without live glass.
///
/// - Liquid Glass: a clear pane the (blurred) desktop shows through, with the glass's bright rim
///   all round.
/// - Black: solid, no rim.
/// - Fade: black down to about two thirds of the island, as the island wears it, clearing into
///   clear glass towards its foot, where alone the rim shows. (The island's own shade,
///   `islandSurfaceShade`, keeps its 12 pt soft edge at any size: in a picture a sixth the island's
///   size that edge was most of the island, and Fade read as a darker Liquid Glass.)
private struct ThumbnailSurface<S: Shape>: View {
    let style: IslandGlassStyle
    let shape: S
    let scale: CGFloat

    var body: some View {
        switch style {
        case .black:
            shape.fill(.black)
        case .liquidGlass:
            shape.fill(.black.opacity(0.08))
                .overlay { shape.fill(.white.opacity(0.05)) }
                .overlay { shape.stroke(.white.opacity(0.45), lineWidth: 0.6 * scale) }
        case .fade:
            shape.fill(.black.opacity(0.08))
                .overlay { shape.fill(.white.opacity(0.05)) }
                .overlay {
                    shape.stroke(.white.opacity(0.45), lineWidth: 0.6 * scale)
                        .mask { LinearGradient(stops: Self.rim, startPoint: .top, endPoint: .bottom) }
                }
                .overlay { shape.fill(LinearGradient(stops: Self.shade, startPoint: .top, endPoint: .bottom)) }
        }
    }

    /// The fade's black: whole to about two thirds of the way down, then easing out to clear at
    /// the foot (smoothstep, in steps small enough that none shows).
    private static var shade: [Gradient.Stop] {
        let start = 0.6
        return [Gradient.Stop(color: .black, location: 0)] + (0...8).map { index in
            let t = Double(index) / 8
            return Gradient.Stop(color: .black.opacity(1 - t * t * (3 - 2 * t)), location: start + (1 - start) * t)
        }
    }

    /// The rim only where the glass is clear.
    private static var rim: [Gradient.Stop] {
        [Gradient.Stop(color: .clear, location: 0.62), Gradient.Stop(color: .black, location: 1)]
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

    /// The stage is told at once, while a window is up.
    private var anchorBar: Binding<AnchorBarPlacement> {
        Binding(get: { model.preferences.anchorBar }, set: { placement in
            model.preferences.anchorBar = placement
            model.anchorMirror.setBar(placement)
        })
    }

    /// Turning the live copy on is what asks for Screen Recording.
    private var anchorMirror: Binding<Bool> {
        Binding(get: { model.preferences.anchorMirror }, set: { on in
            model.preferences.anchorMirror = on
            if on { model.anchorMirror.requestAccess() }
        })
    }

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section("Now Playing") {
                SettingPictureRow { ActivityPicture(activity: .nowPlaying) { NowPlayingPicture() } }
                Toggle(isOn: $preferences.showNowPlaying) {
                    InfoLabel("Show what's playing", "The cover beside the notch and moving level bars while something plays, with the playback controls when the island opens.")
                }
                Toggle(isOn: $preferences.showWebMedia) {
                    InfoLabel("Browser and video playback", "YouTube and other videos in Safari and other browsers, and video apps like QuickTime or IINA. Read only while one of them is open, to save battery; Music and Spotify always report on their own.")
                }
                .disabled(!preferences.showNowPlaying)
            }

            Section("AirPods") {
                SettingPictureRow { ActivityPicture(activity: .airPods) { AirPodsPicture() } }
                Toggle(isOn: $preferences.showAirPods) {
                    InfoLabel("Show AirPods connecting", "When AirPods (or other Bluetooth headphones) connect: their picture, name and the batteries of each earbud and the case.")
                }
            }

            Section("Volume and Brightness") {
                Toggle(isOn: $preferences.showLevelHUD) {
                    InfoLabel("Show volume and brightness changes", "Changing the volume or the brightness shows it in the island.")
                }
                PictureChoice(options: LevelHUDStyle.allCases, selection: $preferences.levelStyle, title: \.title) { style in
                    ActivityPicture(activity: style == .banner ? .volumeBanner : .volumePill) { LevelStylePicture(style: style) }
                }
                .padding(.vertical, SettingsForm.cardRadius - SettingsForm.inset - 10)
                .disabled(!preferences.showLevelHUD)
                .opacity(preferences.showLevelHUD ? 1 : 0.5)
                NoticeDuration(title: "Shown for", value: $preferences.levelDuration)
                    .disabled(!preferences.showLevelHUD)
                if preferences.showLevelHUD, !model.permissions.accessibilityTrusted {
                    LabeledContent {
                        Button("Open System Settings…") { model.permissions.promptOrOpenAccessibilitySettings() }
                    } label: {
                        StatusLabel(title: "Accessibility access needed", tone: .attention)
                    }
                }
            }

            // Desktop Macs have no battery, so there is nothing to alert about. (Read on its own:
            // the whole power state changed at every percent and redrew this page, kept unseen.)
            if model.power.hasBattery {
                Section("Battery") {
                    SettingPictureRow { ActivityPicture(activity: .power) { PowerPicture() } }
                    Toggle(isOn: $preferences.showPowerAlerts) {
                        InfoLabel("Power alerts", "Charger connected or removed, fully charged, and low battery at 20, 10 and 5 %.")
                    }
                    NoticeDuration(title: "Shown for", value: $preferences.powerDuration)
                        .disabled(!preferences.showPowerAlerts)
                }
            }

            Section("Shelf and Timer") {
                Toggle(isOn: $preferences.shelfEnabled) {
                    InfoLabel("Shelf", "Drag files onto the notch to keep them at hand, then drag them out or AirDrop them.")
                }
                Toggle(isOn: $preferences.timerSound) {
                    InfoLabel("Play a sound when a timer ends", "The timer's alert sound plays with the notice in the island.")
                }
            }

            Section("Window Anchor") {
                Toggle(isOn: $preferences.anchorEnabled) {
                    InfoLabel("Anchor a window under the notch", "Holds another app's window centred under the notch: moved, it goes back; resized, it stays centred at its new size; dragged well away, zoomed or closed, it is let go. From the menu bar item, Spotlight (\u{201C}Anchor Front Window\u{201D}) or by dragging. Needs Accessibility.")
                }
                Toggle(isOn: $preferences.anchorByDrag) {
                    InfoLabel("Drag a window to the notch", "While you drag a window by its title bar, letting it go just under the notch anchors it. The island shows where it will land.")
                }
                .disabled(!preferences.anchorEnabled)
                Toggle(isOn: anchorMirror) {
                    InfoLabel("Up to the top of the screen", "The window reaches the screen's top edge, in line with the menu bar and the notch, on a stage that grows out of the notch. macOS keeps other apps' windows under the menu bar, so what you see there is a live copy, and your clicks, scrolls and typing go through to the real window behind it. Needs Screen Recording (macOS shows its screen-sharing indicator meanwhile). Off: the window itself, right under the menu bar.")
                }
                .disabled(!preferences.anchorEnabled)
                Picker(selection: anchorBar) {
                    Text("Beside the Notch").tag(AnchorBarPlacement.menuBar)
                    Text("Under the Window").tag(AnchorBarPlacement.belowWindow)
                } label: {
                    InfoLabel("App name and Release", "Where the anchored app's name and the Release button sit while the window is up at the top. Beside the notch: in the menu bar's band on both sides of the notch (past what is playing, when that shows there), the window right under it and nothing below. Under the window: a slim bar under it, the window up to the screen's top.")
                }
                .choiceBar()
                .fixedSize()
                .disabled(!preferences.anchorEnabled || !preferences.anchorMirror)
                AnchorSizeEditor(size: $preferences.anchorSize, screen: model.anchorScreenForSettings, onTop: preferences.anchorMirror,
                                 bar: preferences.anchorBar)
                    .disabled(!preferences.anchorEnabled)
                    .opacity(preferences.anchorEnabled ? 1 : 0.5)
                if preferences.anchorEnabled, !model.permissions.accessibilityTrusted {
                    LabeledContent {
                        Button("Open System Settings…") { model.permissions.promptOrOpenAccessibilitySettings() }
                    } label: {
                        StatusLabel(title: "Accessibility access needed", tone: .attention)
                    }
                }
                if preferences.anchorEnabled, preferences.anchorMirror, !model.anchorMirror.isAllowed {
                    LabeledContent {
                        Button("Open System Settings…") { AnchorMirror.openSettings() }
                    } label: {
                        StatusLabel(title: "Screen Recording access needed", tone: .attention)
                    }
                }
            }
        }
    }
}

// MARK: - Spotlight (the assistant, called Siri in the code)

/// The switch that puts NotchIsland's Spotlight in place of macOS's, said plainly beside it: which
/// one the keys open now, and that switching it off brings macOS's back.
private struct SpotlightChoiceLabel: View {
    let isOn: Bool
    let shortcut: SiriShortcut

    private var replaces: Bool { shortcut == .commandSpace }

    private var title: String {
        replaces ? "Replace macOS Spotlight" : "Open Spotlight with \(shortcut.title)"
    }

    private var summary: String {
        switch (isOn, replaces) {
        case (true, true):
            "On: \(shortcut.title) opens NotchIsland's Spotlight in the notch instead of macOS's. Switch it off to have \(shortcut.title) open macOS's Spotlight again."
        case (false, true):
            "Off: \(shortcut.title) opens macOS's own Spotlight. Switch it on to open NotchIsland's Spotlight in the notch instead."
        case (true, false):
            "On: \(shortcut.title) opens NotchIsland's Spotlight in the notch; ⌘ Space still opens macOS's. Switch it off to leave only macOS's."
        case (false, false):
            "Off: only macOS's Spotlight, on ⌘ Space. Switch it on to open NotchIsland's Spotlight with \(shortcut.title)."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            InfoLabel(title, "Needs Accessibility and Input Monitoring, which let NotchIsland see the shortcut before the system does (About ▸ Permissions).")
                .font(.headline)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

struct SiriSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        let siri = preferences.siri
        let intelligence = Self.intelligenceStatus
        let intelligenceAvailable = if case .available = SystemLanguageModel.default.availability { true } else { false }
        Form {
            // Which Spotlight the keys open, first and set apart: this switch is how macOS's own
            // comes back (asked for: it read as one setting among the others).
            Section {
                Toggle(isOn: $preferences.commandSpaceOpensSiri) {
                    SpotlightChoiceLabel(isOn: preferences.commandSpaceOpensSiri, shortcut: siri.shortcut)
                }
                if preferences.commandSpaceOpensSiri, case .failed(let reason) = model.commandSpaceState {
                    LabeledContent {
                        Button("Show Permissions") { model.settingsPane = .about }
                    } label: {
                        StatusLabel(title: reason, tone: .attention)
                    }
                } else if preferences.commandSpaceOpensSiri, case .needsPermission = model.commandSpaceState {
                    LabeledContent {
                        Button("Show Permissions") { model.settingsPane = .about }
                    } label: {
                        StatusLabel(title: String(localized: "Accessibility access needed"), tone: .attention)
                    }
                }
                Picker(selection: $preferences.siri.shortcut) {
                    ForEach(SiriShortcut.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Shortcut", "The keys that open Spotlight: Space with Command, Option or Control. ⌘Space replaces the system's search; the others leave it where it is.")
                }
                .choiceBar()
                .disabled(!preferences.commandSpaceOpensSiri)
            } header: {
                Text("Spotlight in the Notch")
            }

            Section {
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
                Picker(selection: $preferences.siri.galleryIconSize) {
                    ForEach(SiriGalleryIconSize.allCases) { Text($0.title).tag($0) }
                } label: {
                    InfoLabel("Icon size", "How large the apps are in the gallery (⌘1). Its window grows with them, so the same number of apps fits in a row.")
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
                Toggle(isOn: $preferences.siri.showsPeople) {
                    InfoLabel("People & Calendar  ⌘8", "Your contacts (call, message, email, copy) and your coming events. Each is read only after you allow it from its own row there, only while Spotlight is open, and never leaves this Mac.")
                }
                Toggle(isOn: $preferences.siri.showsDefinitions) {
                    InfoLabel("Dictionary", "A word typed alone is looked up in your Mac's dictionaries: Return shows the whole entry.")
                }
                Toggle(isOn: $preferences.siri.showsBookmarks) {
                    InfoLabel("Bookmarks", "Your browsers' bookmarks in search results: Chrome's, Arc's and Brave's, and Safari's where macOS lets NotchIsland read them. Read from their files while Spotlight is open; history is never read.")
                }
                Toggle(isOn: $preferences.siri.convertsCurrency) {
                    InfoLabel("Currencies", "\u{201C}100 usd in eur\u{201D}: the European Central Bank's daily rates, fetched at most once a day and only when you type a currency. What you type is never sent.")
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
                Toggle(isOn: $preferences.siri.searchesFileContents) {
                    InfoLabel("Search Inside Files", "Also find files by what they say, from three letters on. Files named after the word come first.")
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
                InfoLabel("Files", "The folders Spotlight searches for files. macOS asks for access to Desktop, Documents, Downloads and iCloud Drive the first time. On a file, Space or ⌘Y previews it and ⌘R shows it in Finder.")
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
/// The newest version: looked up when About opens; one click downloads it, checks it, installs it
/// in place and reopens NotchIsland (`AppUpdater`).
private struct UpdateSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updater = model.updater
        Section {
            if let from = updater.updatedFrom {
                Label("Updated from \(from) to \(updater.current). Your settings and permissions were kept.", systemImage: "sparkles")
                    .foregroundStyle(.primary)
            }
            if ReleaseNotes.current.version == updater.current {
                LabeledContent("What this version brought") {
                    Button("What's New…") {
                        model.controller.closeSettings()
                        model.controller.showWhatsNew()
                    }
                }
            }
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
                HStack(alignment: .center, spacing: 14) {
                    AppMark(side: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NotchIsland \(release.version) is available").font(.headline)
                        Text("You have \(updater.current). It installs itself and reopens in a few seconds; settings and permissions stay.")
                            .font(.callout)
                            .foregroundStyle(SettingsPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Update Now") { Task { await updater.install(release) } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.vertical, 4)
                notes(release)
            case .downloading(let release, let progress):
                progressRow(title: "Downloading \(release.version)…", progress: progress,
                            detail: progress.map { "\(Int(($0 * 100).rounded())) %" })
            case .installing(let release, let step):
                progressRow(title: "Installing \(release.version)", progress: nil, detail: step)
            case .relaunching(let release):
                progressRow(title: "\(release.version) is installed", progress: 1, detail: String(localized: "Reopening NotchIsland…"))
            case .differentSigner(let release, _):
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(release.version) is signed differently from this copy", systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("It is intact and comes from NotchIsland's GitHub releases, but macOS will see it as a new app: Accessibility, Input Monitoring and the others have to be allowed again after it opens (About shows each one).")
                        .font(.callout)
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { updater.cancel() }
                        Button("Install Anyway") { Task { await updater.installAnyway() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            case .manual(let release, let file):
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(release.version) could not replace this copy, so it is open in Finder.").font(.headline)
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
            LabeledContent {
                HStack {
                    Slider(value: Binding(get: { Double(updater.checksPerDay) }, set: { new in
                        let count = Int(new.rounded())
                        if count != updater.checksPerDay { updater.checksPerDay = count }
                    }), in: Double(AppUpdater.checksPerDayRange.lowerBound)...Double(AppUpdater.checksPerDayRange.upperBound))
                    .labelsHidden()
                    .tint(Color.islandAccent)
                    .frame(minWidth: 160, maxWidth: 240)
                    ReservedWidthText(SettingsFormat.checksPerDay(updater.checksPerDay),
                                      fitting: [SettingsFormat.checksPerDay(AppUpdater.checksPerDayRange.lowerBound),
                                                SettingsFormat.checksPerDay(AppUpdater.checksPerDayRange.upperBound)])
                        .foregroundStyle(SettingsPalette.secondary)
                }
            } label: {
                InfoLabel("Automatic checks", "How often NotchIsland looks for a new version on its own: now \(SettingsFormat.checkInterval(perDay: updater.checksPerDay)). Each look is one small request to GitHub.")
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Downloaded from NotchIsland's GitHub releases. Before installing, NotchIsland checks that the new copy is intact and signed exactly as this one, which is what lets macOS keep its permissions.")
        }
        .task { if updater.state == .idle { await updater.check() } }
    }

    private func progressRow(title: String, progress: Double?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(SettingsPalette.secondary)
                }
            }
            if let progress {
                ProgressView(value: progress).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func notes(_ release: AppUpdater.Release) -> some View {
        if !release.notes.isEmpty {
            DisclosureGroup("What's New") {
                Text(Self.notes(release.notes))
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
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

    var body: some View {
        let count = model.shelf.items.count
        Form {
            UpdateSection()

            FeedbackSection()

            PermissionsSection()

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
