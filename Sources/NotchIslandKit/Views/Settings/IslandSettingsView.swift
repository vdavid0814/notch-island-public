import AppKit
import SwiftUI

/// Settings' pages, in sidebar order.
nonisolated enum IslandSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general, widgets, activities, siri, about

    nonisolated static let key = "ni2.settings.pane"

    var id: String { rawValue }

    /// A pane by name, including the names of pages that were merged into others (Appearance is
    /// part of General, Permissions of About), so old links and the remembered pane still work.
    static func named(_ name: String) -> IslandSettingsPane? {
        switch name {
        case "appearance": .general
        case "permissions": .about
        default: IslandSettingsPane(rawValue: name)
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .widgets: "Widgets"
        case .activities: "Live Activities"
        case .siri: "Spotlight"
        case .about: "About"
        }
    }

    /// Under the page's title.
    var subtitle: String {
        switch self {
        case .general: "How the island looks, opens and behaves."
        case .widgets: "Arrange the open island and choose what each widget shows."
        case .activities: "What appears in the notch by itself."
        case .siri: "Search and ask, right in the notch."
        case .about: "Version, permissions and data."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .widgets: "square.grid.2x2.fill"
        case .activities: "waveform"
        case .siri: "magnifyingglass"
        case .about: "info.circle.fill"
        }
    }

    /// The sidebar tile's colour, as System Settings gives each pane one.
    var tint: Color {
        switch self {
        case .general: .gray
        case .widgets: .blue
        case .activities: .pink
        case .siri: .purple
        case .about: .indigo
        }
    }

    /// Sidebar groups.
    static let groups: [[IslandSettingsPane]] = [[.general, .widgets], [.activities, .siri], [.about]]
}

/// The colours Settings is drawn with. Settings is read, not glanced at, so it sits on solid
/// ground whatever the island's surface style: a dark window colour, a lighter sidebar, and
/// cards a step lighter again, with text at full contrast.
nonisolated enum SettingsPalette {
    static let window = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let sidebar = Color(red: 0.13, green: 0.13, blue: 0.145)
    static let card = Color(red: 0.155, green: 0.155, blue: 0.17)
    static let cardStroke = Color.white.opacity(0.07)
    /// Secondary text, a little brighter than the system's on this dark ground.
    static let secondary = Color.white.opacity(0.62)

    /// Settings' panels (the sidebar; Customize's outline and inspector), top to bottom: the greys
    /// the smoked Liquid Glass they were drawn in showed over Settings' ground (measured on screen),
    /// now a plain material. The glass cost the window server a pass of its own over the whole
    /// panel whenever anything in Settings changed (~3 J per tour of the pages, measured).
    static let panel = LinearGradient(stops: [
        .init(color: Color(red: 17.4 / 255, green: 17.4 / 255, blue: 19.7 / 255), location: 0),
        .init(color: Color(red: 18.9 / 255, green: 18.9 / 255, blue: 20.5 / 255), location: 0.09),
        .init(color: Color(red: 21.2 / 255, green: 21.2 / 255, blue: 22.8 / 255), location: 0.23),
        .init(color: Color(red: 24.3 / 255, green: 24.3 / 255, blue: 26.6 / 255), location: 0.37),
        .init(color: Color(red: 26.6 / 255, green: 26.6 / 255, blue: 29.7 / 255), location: 0.5),
        .init(color: Color(red: 27.4 / 255, green: 28.2 / 255, blue: 31.2 / 255), location: 0.64),
        .init(color: Color(red: 28.9 / 255, green: 28.9 / 255, blue: 32.0 / 255), location: 0.92),
        .init(color: Color(red: 29.7 / 255, green: 28.9 / 255, blue: 32.8 / 255), location: 1),
    ], startPoint: .top, endPoint: .bottom)
}

extension View {
    /// Puts a Settings panel on its plain material, edged like Settings' cards.
    func settingsPanel(in shape: some InsettableShape) -> some View {
        background(SettingsPalette.panel, in: shape)
            .overlay { shape.strokeBorder(SettingsPalette.cardStroke) }
    }
}

/// Settings, grown out of the notch over most of the screen: laid out like System Settings — a
/// sidebar of pages and one grouped form per page, centred at a readable width — with only the
/// system's own controls.
///
/// It lives only while open (the island's content is torn down on close), so it costs nothing the
/// rest of the time. Esc, the close button or a click outside close it.
struct IslandSettingsView: View {
    /// Between the sidebar and the island's edge, at the side and at the bottom alike.
    static let sidebarGap: CGFloat = 8
    /// How long the pages take to fade in once the island has grown.
    static let pagesFadeIn: TimeInterval = 0.16

    @Environment(AppModel.self) private var model
    /// The pages join once the island has grown. Laid out during the growth they were re-laid out
    /// every frame (their AppKit controls included: ~0.45 s of main thread per open, measured) and
    /// the growth stuttered; the empty window colour grows in smoothly instead.
    @State private var showsPages = false

    static func placement(_ layout: IslandLayout) -> SettingsPlacement {
        let gap = sidebarGap
        return SettingsPlacement(
            outerRadius: max(16, layout.bottomRadius(for: .settings) - gap),
            leading: layout.shoulderRadius(for: .settings) + gap,
            gap: gap
        )
    }

    /// The pages' room: Settings' size under the band at the notch's height.
    static func surfaceSize(_ layout: IslandLayout) -> CGSize {
        let size = layout.size(for: .settings)
        return CGSize(width: size.width, height: max(0, size.height - layout.notch.height))
    }

    var body: some View {
        let layout = model.layout
        let split = NotchSplit(
            layout: layout,
            presentation: .settings,
            outerInset: Metrics.Expanded.horizontalInset,
            clearance: Metrics.notchClearance
        )
        VStack(spacing: 0) {
            NotchSplitBand(split: split, height: layout.notch.height) {
                // Only the window's name: the app's mark and version head the sidebar below.
                Text("Settings")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } trailing: {
                Button {
                    model.controller.closeSettings()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .islandButton(.circle)
                .controlSize(Metrics.Control.size(fittingBand: layout.notch.height))
                .help("Close (esc)")
            }
            .background(.black)
            // Gone from sight as soon as Settings starts to close (the same fade the removal had);
            // torn down with the rest of Settings once it has closed, on the efficiency cores
            // (`IslandController`), not in the turn the shrink starts in.
            if showsPages {
                // The sidebar floats as far from the island's side as from its bottom, its lower
                // outer corner concentric with the island's (radius = the island's minus the gap).
                let placement = Self.placement(layout)
                // In a view graph of its own, dropped with it when Settings closes: in the island's
                // graph, the pages' caches outlived them (measured: ~70 MB kept after one visit).
                // Faded in by the render server: faded by SwiftUI, every frame of the fade updated
                // the island's graph around it. A widget's Customize editor takes the pages' place
                // there, the widget flying between them (`SettingsSurface`).
                SettingsSurface(placement: placement, model: model, isClosing: !model.island.presentation.isSettings)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { SettingsBackdrop() }
        .environment(\.colorScheme, .dark)
        .onDisappear {
            WallpaperLibrary.shared.purge()
            MemoryRelief.afterLargeSurfaceClosed()
        }
        .task {
            // Most of the growth first (its tail is too small to see a frame drop in). At full
            // speed: built unseen on the efficiency cores it took up to a second longer to appear,
            // and held the panel's fading widgets still while it ran (tried, seen on video).
            try? await Task.sleep(for: .seconds(model.preferences.animationDuration * 0.9))
            guard !Task.isCancelled else { return }
            showsPages = true
            // Synchronous system queries (Login Items alone took ~20 ms): after the pages are in.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            model.permissions.refresh()
            model.launchAtLogin.refresh()
        }
    }
}

/// Where Settings' sidebar floats (and the Customize editor's outline, in its place): all the pages
/// take from outside their graph.
nonisolated struct SettingsPlacement: Equatable, Sendable {
    /// The sidebar's lower outer corner.
    var outerRadius: CGFloat
    /// From the island's side to the sidebar.
    var leading: CGFloat
    /// Under the sidebar.
    var gap: CGFloat

    /// The sidebar's (and the outline's) width.
    static let sidebarWidth: CGFloat = 236
}

/// The sidebar and the page beside it.
struct SettingsPages: View {
    let placement: SettingsPlacement

    @Environment(AppModel.self) private var model

    var body: some View {
        let sidebarShape = UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: placement.outerRadius,
            bottomTrailingRadius: 16,
            topTrailingRadius: 16,
            style: .continuous
        )
        HStack(spacing: 0) {
            SettingsSidebar(selection: Binding(get: { model.settingsPane }, set: { model.settingsPane = $0 }))
                .frame(width: SettingsPlacement.sidebarWidth)
                .settingsPanel(in: sidebarShape)
                .padding(.leading, placement.leading)
                .padding(.bottom, placement.gap)
                .padding(.top, 4)
            // The pages themselves are kept beside it, each in a graph of its own
            // (`SettingsPageDeckView`, laid over this room by `SettingsSurfaceView`).
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Settings' ground: black where it hangs from the notch, easing over most of the page
/// into the window's grey. A plain, opaque material: text keeps its contrast whatever is on the
/// desktop.
private struct SettingsBackdrop: View {
    /// Where the fade reaches the window's grey: most of the page, so it reads as light falling
    /// off rather than a band.
    static let fadeLength = 0.7

    /// What the gradient's last few percent of see-through showed: the desktop through the system's
    /// behind-window blur (`NSVisualEffectView`, `.hudWindow`), a light grey on average. Solid now,
    /// so the grey of the page stays as it was without the window server blurring the desktop
    /// behind Settings.
    static let ground = Color(red: 60 / 255, green: 60 / 255, blue: 64 / 255)

    var body: some View {
        ZStack {
            Self.ground
            LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
        }
    }

    /// Black to the window colour along a smoothstep curve (twelve stops, so no step shows), the
    /// opacity easing from solid to the faint see-through of the glass behind.
    static let stops: [Gradient.Stop] = (0...12).map { index in
        let x = Double(index) / 12
        let t = x * x * (3 - 2 * x)
        let grey = 0.09 * t
        return Gradient.Stop(
            color: Color(red: grey, green: grey, blue: grey + 0.01 * t).opacity(1 - 0.06 * t),
            location: x * fadeLength
        )
    } + [Gradient.Stop(color: SettingsPalette.window.opacity(0.94), location: 1)]
}

private struct SettingsSidebar: View {
    @Binding var selection: IslandSettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark(side: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NotchIsland").font(.headline)
                    Text(SettingsFormat.version(Bundle.main.infoDictionary))
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // The selected page on a plate in the theme's colour (the list's own selection is the
            // system's grey or blue): ↑ and ↓ still move it.
            List {
                ForEach(Array(IslandSettingsPane.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { pane in
                            Label {
                                Text(pane.title).font(.system(size: 13.5, weight: .medium))
                            } icon: {
                                SettingsTile(systemImage: pane.systemImage, tint: pane.tint, side: 24)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                            .background {
                                if pane == selection {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.islandAccent.opacity(Self.plateOpacity))
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { selection = pane }
                            .accessibilityAddTraits(pane == selection ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(by: -1) }
            .onKeyPress(.downArrow) { move(by: 1) }
        }
    }
}

extension SettingsSidebar {
    /// The plate is the theme's colour this faint (white gives the grey of the system's plate).
    static let plateOpacity = 0.2

    private func move(by step: Int) -> KeyPress.Result {
        let panes = IslandSettingsPane.groups.flatMap { $0 }
        guard let index = panes.firstIndex(of: selection) else { return .ignored }
        selection = panes[min(max(index + step, 0), panes.count - 1)]
        return .handled
    }
}

/// A symbol on a small coloured squircle, like System Settings' sidebar icons.
struct SettingsTile: View {
    let systemImage: String
    let tint: Color
    var side: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
            .fill(tint.gradient)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: side * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct SettingsDetail: View {
    let pane: IslandSettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(pane: pane)
            Group {
                switch pane {
                case .general: GeneralSettingsPage()
                case .widgets: WidgetsSettingsPage()
                case .activities: ActivitiesSettingsPage()
                case .siri: SiriSettingsPage()
                case .about: AboutSettingsPage()
                }
            }
            .formStyle(.settings)
            // Switches and sliders in the theme's colour, where the system's blue was.
            .toggleStyle(.islandSwitch)
            // Every button the system's own, in its capsule (as the pickers are): the square-ish
            // push button and flat tiles stood out (asked for).
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: pane == .widgets ? .infinity : 720)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The page's tile, title and one line on what it is for.
private struct SettingsPageHeader: View {
    let pane: IslandSettingsPane

    var body: some View {
        HStack(spacing: 14) {
            SettingsTile(systemImage: pane.systemImage, tint: pane.tint, side: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title).font(.system(size: 22, weight: .bold))
                Text(pane.subtitle).font(.system(size: 13)).foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pane == .widgets ? 28 : 0)
        .frame(maxWidth: pane == .widgets ? .infinity : 680)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}
