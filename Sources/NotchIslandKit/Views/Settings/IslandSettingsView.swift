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
        case .siri: "Siri"
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
        case .siri: "siri"
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

    @Environment(AppModel.self) private var model
    /// The pages join once the island has grown. Laid out during the growth they were re-laid out
    /// every frame (their AppKit controls included: ~0.45 s of main thread per open, measured) and
    /// the growth stuttered; the empty window colour grows in smoothly instead.
    @State private var showsPages = false

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
                Label {
                    Text("NotchIsland Settings")
                } icon: {
                    AppMark(side: 18)
                }
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
            // Dropped as soon as Settings starts to close, so the shrink is as light as the growth.
            if showsPages && model.island.presentation.isSettings {
                // The sidebar floats as far from the island's side as from its bottom, its lower
                // outer corner concentric with the island's (radius = the island's minus the gap).
                let gap = Self.sidebarGap
                let islandRadius = layout.bottomRadius(for: .settings)
                let sidebarShape = UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: max(16, islandRadius - gap),
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
                HStack(spacing: 0) {
                    SettingsSidebar(selection: Binding(get: { model.settingsPane }, set: { model.settingsPane = $0 }))
                        .frame(width: 236)
                        // Liquid Glass, smoked towards the black of the island.
                        .glassEffect(Glass.regular.tint(Color.black.opacity(0.45)), in: sidebarShape)
                        .padding(.leading, layout.shoulderRadius(for: .settings) + gap)
                        .padding(.bottom, gap)
                        .padding(.top, 4)
                    SettingsDetail(pane: model.settingsPane)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { SettingsBackdrop() }
        .environment(\.colorScheme, .dark)
        .task {
            // Most of the growth first (its tail is too small to see a frame drop in).
            try? await Task.sleep(for: .seconds(model.preferences.animationDuration * 0.9))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { showsPages = true }
            // Synchronous system queries (Login Items alone took ~20 ms): after the pages are in.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            model.permissions.refresh()
            model.launchAtLogin.refresh()
        }
    }
}

/// Settings' ground: black where it hangs from the notch, easing over most of the page
/// into the window's grey, which is slightly see-through so the island's glass shows faintly
/// behind it. Mostly opaque, so text keeps its contrast whatever is on the desktop.
private struct SettingsBackdrop: View {
    /// Where the fade reaches the window's grey: most of the page, so it reads as light falling
    /// off rather than a band.
    static let fadeLength = 0.7

    var body: some View {
        ZStack {
            // What shows faintly through: the desktop, blurred by the window server as behind any
            // translucent macOS window (live Liquid Glass here cost hundreds of MB, see
            // `GlassIsland`).
            WindowVibrancy()
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

/// The system's behind-window blur (`NSVisualEffectView`), dark.
private struct WindowVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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

            List(selection: Binding(get: { selection }, set: { if let new = $0 { selection = new } })) {
                ForEach(Array(IslandSettingsPane.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { pane in
                            Label {
                                Text(pane.title).font(.system(size: 13.5, weight: .medium))
                            } icon: {
                                SettingsTile(systemImage: pane.systemImage, tint: pane.tint, side: 24)
                            }
                            .padding(.vertical, 3)
                            .tag(pane)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
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

private struct SettingsDetail: View {
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
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: pane == .widgets ? .infinity : 720)
            .frame(maxWidth: .infinity)
        }
        .id(pane)
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
