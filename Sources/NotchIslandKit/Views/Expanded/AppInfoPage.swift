import SwiftUI

/// What the About page's ⓘ says about a day's energy, worked out from `docs/ENERGY-LOG.md`: the
/// coalition's energy (own + GPU + what the system billed to it) on a MacBook Pro M5, release builds.
nonisolated enum AppInfoEnergy {
    struct Part: Sendable, Identifiable {
        let title: String
        /// How much of it in the day.
        let detail: String
        let joules: Double

        var id: String { title }
    }

    /// Hours of the Mac in use the day is counted over.
    static let hours = 10.0
    /// A 13-inch MacBook Air's battery (53.8 Wh).
    static let batteryJoules = 53.8 * 3600

    /// 143.4 mJ per 5 minutes at rest (2026-10-15); 73.6 mJ a hover opening and close (2026-10-15);
    /// a Spotlight opening 31 + closing 45 + search 303 mJ (2026-10-14); a standard report 18 mJ.
    static let parts = [
        Part(title: "At rest", detail: "\(Int(hours)) hours", joules: 0.1434 / 300 * hours * 3600),
        Part(title: "Opening the panel", detail: "50 times", joules: 50 * 0.0736),
        Part(title: "Spotlight", detail: "10 searches", joules: 10 * (0.031 + 0.045 + 0.303)),
        Part(title: "Diagnostics", detail: "10 reports", joules: hours * 0.018),
    ]

    static var totalJoules: Double { parts.reduce(0) { $0 + $1.joules } }
    static var batteryShare: Double { totalJoules / batteryJoules }
}

/// How NotchIsland works and what it costs, from the ⓘ beside About's title in Settings (`AppInfoMenu`),
/// or by its URL a display as large as Settings, grown out of the notch as the panel does. Pages of widgets picked from the bar
/// over them (two fingers sideways stay Settings' back and forward). Kept open until Done (or a click elsewhere).
struct AppInfoPage: View {
    private enum Topic: String, CaseIterable, Identifiable {
        case memory, energy, features

        var id: Self { self }

        var title: String {
            switch self {
            case .memory: String(localized: "Memory")
            case .energy: String(localized: "Energy")
            case .features: String(localized: "Features")
            }
        }
    }

    /// Done, inside Settings; nil: the island closes.
    var close: (() -> Void)?

    @Environment(AppModel.self) private var model

    var body: some View {
        InfoPageShell(topics: Topic.allCases, title: \.title, label: "How NotchIsland works",
                      close: { if let close { close() } else { model.controller.collapse() } }, page: page)
    }

    @ViewBuilder private func page(_ topic: Topic) -> some View {
        switch topic {
        case .memory: MemoryInfo()
        case .energy: EnergyInfo()
        case .features: FeaturesInfo()
        }
    }
}

nonisolated enum InfoPageMetrics {
    /// From the page's edge to its cards, past its own padding.
    static let inset: CGFloat = 4
}

/// The look of the info pages (this one and What's New, `WhatsNewPage`): the version, a bar of topics
/// and Done over a page of cards. Two fingers sideways are left to whatever
/// is around it: only the bar changes the topic.
struct InfoPageShell<Topic: Hashable & Identifiable, Page: View>: View {
    private static var inset: CGFloat { InfoPageMetrics.inset }

    let topics: [Topic]
    let title: (Topic) -> String
    let label: LocalizedStringKey
    /// On Settings' solid ground; false: on the island's own surface, whatever its style.
    var solidGround = true
    /// False: the window is made as high as the cards want (`IslandLayout.size(for:)`).
    var scrolls = true
    /// The topic shown until the bar picks another; nil: the first.
    var opening: Topic?
    /// A back button before the version (What's New's cards, back to its highlights).
    var back: (() -> Void)?
    /// The bar picked another topic.
    var picked: (Topic) -> Void = { _ in }
    let close: () -> Void
    @ViewBuilder let page: (Topic) -> Page

    @State private var chosen: Topic?
    private var shown: Topic? {
        (chosen ?? opening).flatMap { topics.contains($0) ? $0 : nil } ?? topics.first
    }
    private var topic: Binding<Topic?> {
        Binding(get: { shown }, set: { new in
            withAnimation(.smooth(duration: 0.25)) { chosen = new }
            if let new { picked(new) }
        })
    }

    var body: some View {
        VStack(spacing: Metrics.Spacing.small) {
            ZStack {
                if topics.count > 1 {
                    Picker("Topic", selection: topic) {
                        ForEach(topics) { Text(title($0)).tag(Optional($0)) }
                    }
                    .choiceBar()
                    .labelsHidden()
                    .fixedSize()
                }
                HStack {
                    if let back {
                        Button("Highlights", systemImage: "chevron.left", action: back)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .labelStyle(.iconOnly)
                            .help("Back to the highlights")
                    }
                    Text(verbatim: SettingsFormat.version(Bundle.main.infoDictionary))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.Spacing.small)
                    Button("Done", systemImage: "checkmark", action: close)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .labelStyle(.iconOnly)
                        .help("Close")
                }
            }
            GeometryReader { proxy in
                let column = (proxy.size.width - 2 * Self.inset - 2 * InfoRow<EmptyView>.spacing) / 3
                if scrolls {
                    ScrollView(.vertical) {
                        // The cards fill the page while they fit; on a small screen it scrolls.
                        Group { if let shown { page(shown) } }
                            .environment(\.infoColumn, column)
                            .frame(minHeight: proxy.size.height - 2 * Self.inset)
                            .padding(Self.inset)
                    }
                    .scrollIndicators(.automatic)
                    .id(shown)
                    .transition(.opacity)
                } else {
                    Group { if let shown { page(shown) } }
                        .environment(\.infoColumn, column)
                        .environment(\.infoPageWidth, proxy.size.width - 2 * Self.inset)
                        .padding(Self.inset)
                        .id(shown)
                        .transition(.opacity)
                }
            }
        }
        // Read, not glanced at: on Settings' solid ground whatever the island's surface, out past its
        // edges (the island's outline clips it).
        .background(alignment: .top) {
            if solidGround {
                LinearGradient(colors: [.black, SettingsPalette.window], startPoint: .top, endPoint: .bottom)
                    .padding(.horizontal, -40)
                    .padding(.bottom, -40)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }
}

/// A card of text: a symbol and title over a line or two.
nonisolated struct InfoCard: Identifiable, Sendable {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var id: String { title }
}

/// Cards in full rows, `columns` to a row.
struct InfoCardGrid: View {
    let cards: [InfoCard]
    /// Cards in a row; not three: the page's width shared by as many (`infoPageWidth`).
    var columns = 3

    @Environment(\.infoPageWidth) private var pageWidth
    @Environment(\.infoColumn) private var column

    var body: some View {
        let spacing = InfoRow<EmptyView>.spacing
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: cards.count, by: columns)), id: \.self) { start in
                InfoRow {
                    ForEach(cards[start..<min(start + columns, cards.count)]) { card in
                        InfoWidget(title: card.title, symbol: card.symbol, tint: card.tint) {
                            Text(card.detail)
                                .font(.system(size: 14.5))
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .infoColumns()
                    }
                    ForEach(cards.count..<max(cards.count, start + columns), id: \.self) { _ in
                        Color.clear.infoColumns()
                    }
                }
            }
        }
        .environment(\.infoColumn, columns == 3 || pageWidth <= 0 ? column
                     : (pageWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }
}

extension EnvironmentValues {
    /// One of the page's three columns.
    @Entry var infoColumn: CGFloat = 300
    /// The page's width inside its insets, for a grid of its own columns (`InfoCardGrid`).
    @Entry var infoPageWidth: CGFloat = 0
    /// How high every row is (`WhatsNewPage`); nil: as the room falls.
    @Entry var infoRowHeight: CGFloat?
    /// The cards' corner: concentric with the page they lie in (`AppInfoMenu`).
    @Entry var infoCardRadius: CGFloat = 20
}

/// A row of cards on the page's three columns, as tall as the room it is given. (A `Grid` took its
/// columns from its texts' single-line widths, wider than the page.)
struct InfoRow<Content: View>: View {
    static var spacing: CGFloat { 12 }

    @ViewBuilder var content: Content
    @Environment(\.infoRowHeight) private var height

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) { content }
            .frame(minHeight: height, maxHeight: height ?? .infinity)
    }
}

extension View {
    /// `columns` of the page's three columns wide.
    func infoColumns(_ columns: CGFloat = 1) -> some View {
        modifier(InfoColumns(columns: columns))
    }
}

private struct InfoColumns: ViewModifier {
    let columns: CGFloat
    @Environment(\.infoColumn) private var column

    func body(content: Content) -> some View {
        content
            .frame(width: column * columns + InfoRow<EmptyView>.spacing * (columns - 1))
            .frame(maxHeight: .infinity)
    }
}

/// A card of the page, rounded as the island's widgets are.
struct InfoWidget<Content: View>: View {
    var title: String?
    var symbol: String?
    var tint: Color = .white
    @ViewBuilder var content: Content

    @Environment(\.infoCardRadius) private var radius

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol).foregroundStyle(tint)
                    }
                    Text(title).foregroundStyle(.white.opacity(0.78))
                }
                .font(.system(size: 16, weight: .semibold))
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.08)) }
    }
}

/// A large number and what it is.
struct InfoStat: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let detail: String
    /// Rows of a set height (`WhatsNewPage`): the number fits in one.
    @Environment(\.infoRowHeight) private var rowHeight

    var body: some View {
        InfoWidget(title: title, symbol: symbol, tint: tint) {
            Text(value)
                .font(.system(size: rowHeight == nil ? 46 : 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 14.5))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InfoLine: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Memory

/// Measured 2026-10-31 on release 0.8.7: Activity Monitor's Memory column, the same as `vmmap`'s footprint.
private struct MemoryInfo: View {
    var body: some View {
        VStack(spacing: InfoRow<EmptyView>.spacing) {
            InfoRow {
                InfoStat(title: String(localized: "At rest"), symbol: "moon.fill", tint: .indigo, value: "≈ 48 MB",
                         detail: String(localized: "What it normally uses, all day."))
                    .infoColumns()
                InfoStat(title: String(localized: "At the most"), symbol: "arrow.up.to.line", tint: .orange, value: "≈ 200 MB",
                         detail: String(localized: "If you open every Settings page, one after another."))
                    .infoColumns()
                InfoStat(title: String(localized: "After that"), symbol: "arrow.down.to.line", tint: .green, value: "95–104 MB",
                         detail: String(localized: "A minute after you leave those pages."))
                    .infoColumns()
            }
            InfoRow {
                InfoWidget(title: String(localized: "Settings loads only what you open"), symbol: "square.stack.3d.up.fill", tint: .blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        InfoLine(symbol: "1.circle.fill", tint: .blue, title: String(localized: "General is always ready"),
                                 detail: String(localized: "So Settings opens right away."))
                        InfoLine(symbol: "2.circle.fill", tint: .blue, title: String(localized: "Other pages load when you open them"),
                                 detail: String(localized: "Until then, they use no memory."))
                        InfoLine(symbol: "3.circle.fill", tint: .blue, title: String(localized: "A minute after you leave, they're cleared"),
                                 detail: String(localized: "Come back sooner and the page is still there."))
                    }
                }
                .infoColumns(2)
                InfoWidget(title: String(localized: "Why it stays above 48 MB"), symbol: "checkmark.seal.fill", tint: .green) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoLine(symbol: "textformat", tint: .white.opacity(0.7), title: "20–25 MB",
                                 detail: String(localized: "macOS keeps fonts and symbols ready."))
                        InfoLine(symbol: "square.grid.3x3.middle.filled", tint: .white.opacity(0.7), title: "28–32 MB",
                                 detail: String(localized: "Freed memory, kept for reuse. It doesn't keep growing."))
                    }
                }
                .infoColumns()
            }
        }
    }
}

// MARK: - Energy

private struct EnergyInfo: View {
    private static let joules = AppInfoEnergy.totalJoules.rounded()
    private static let share = (AppInfoEnergy.batteryShare * 100).formatted(.number.precision(.significantDigits(1)))

    var body: some View {
        VStack(spacing: InfoRow<EmptyView>.spacing) {
            InfoRow {
                InfoStat(title: String(localized: "An average day"), symbol: "leaf.fill", tint: .green,
                         value: "≈ \(Int(Self.joules)) J",
                         detail: String(localized: "About \(Self.share) % of a MacBook Air's battery."))
                    .infoColumns()
                InfoWidget(title: String(localized: "Where it goes"), symbol: "chart.bar.fill", tint: .green) {
                    VStack(spacing: 14) {
                        ForEach(AppInfoEnergy.parts) { part in
                            HStack(spacing: 10) {
                                Text(part.title)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 140, alignment: .leading)
                                Text(part.detail)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 90, alignment: .leading)
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(.green.gradient)
                                        .frame(width: max(4, proxy.size.width * part.joules / AppInfoEnergy.totalJoules))
                                }
                                .frame(height: 8)
                                Text(verbatim: part.joules.formatted(.number.precision(.fractionLength(part.joules < 1 ? 1 : 0))) + " J")
                                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.75))
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }
                .infoColumns(2)
            }
            InfoRow {
                InfoWidget(title: String(localized: "Why it uses so little"), symbol: "bolt.slash.fill", tint: .yellow) {
                    VStack(alignment: .leading, spacing: 10) {
                        InfoLine(symbol: "bell.slash.fill", tint: .yellow, title: String(localized: "It waits instead of checking"),
                                 detail: String(localized: "macOS tells it when something changes. Only the clipboard is checked regularly."))
                        InfoLine(symbol: "square.3.layers.3d", tint: .yellow, title: String(localized: "macOS draws the animations"),
                                 detail: String(localized: "The app barely works while they play, and they stay smooth."))
                    }
                }
                .infoColumns(2)
                InfoWidget(title: String(localized: "How it was measured"), symbol: "ruler.fill", tint: .white.opacity(0.7)) {
                    Text("On a MacBook Pro M5 in October 2026. Your Mac will differ. Not counted: music bars following the music, an anchored window and time in Settings.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .infoColumns()
            }
        }
    }
}

// MARK: - Features

private struct FeaturesInfo: View {
    private static let features = [
        InfoCard(symbol: "music.note", tint: .pink, title: String(localized: "Now Playing"),
                 detail: String(localized: "Cover and music bars beside the notch, controls when it opens. Browsers too.")),
        InfoCard(symbol: "square.grid.2x2.fill", tint: .blue, title: String(localized: "Widgets"),
                 detail: String(localized: "Build your own pages: controls, clocks, calendar, battery and system stats.")),
        InfoCard(symbol: "magnifyingglass", tint: .purple, title: String(localized: "Spotlight"),
                 detail: String(localized: "Find apps, files, windows, emoji, people and actions, right in the notch.")),
        InfoCard(symbol: "sparkles", tint: .indigo, title: String(localized: "Siri AI"),
                 detail: String(localized: "Ask from Spotlight and read the answer in the island, without opening Siri.")),
        InfoCard(symbol: "list.clipboard.fill", tint: .gray, title: String(localized: "Clipboard"),
                 detail: String(localized: "What you copied, in a list in Spotlight, ready to use again.")),
        InfoCard(symbol: "macwindow", tint: .teal, title: String(localized: "Window Anchor"),
                 detail: String(localized: "Keep a window under the notch, even over full-screen apps.")),
        InfoCard(symbol: "tray.fill", tint: .orange, title: String(localized: "Shelf"),
                 detail: String(localized: "Drop files on the notch to keep them handy. Drag them out or AirDrop them.")),
        InfoCard(symbol: "timer", tint: .yellow, title: String(localized: "Timers and recording"),
                 detail: String(localized: "Timers, the stopwatch and screen recording stay beside the notch while they run.")),
        InfoCard(symbol: "speaker.wave.2.fill", tint: .cyan, title: String(localized: "Volume and brightness"),
                 detail: String(localized: "Changes show in the island instead of macOS's own picture.")),
        InfoCard(symbol: "airpods.pro", tint: .white, title: String(localized: "AirPods and battery"),
                 detail: String(localized: "AirPods' battery as they connect, plus charging and low battery notices.")),
        InfoCard(symbol: "fan.fill", tint: .mint, title: String(localized: "Temperature and fans"),
                 detail: String(localized: "See how hot the chip is. On a MacBook Pro, set the fan speed too.")),
        InfoCard(symbol: "chart.bar.fill", tint: .green, title: String(localized: "Battery by app"),
                 detail: String(localized: "See which apps used your battery, and how it changed over time.")),
        InfoCard(symbol: "paintpalette.fill", tint: .red, title: String(localized: "Notch Styles"),
                 detail: String(localized: "Save how the island looks and switch back to it anytime.")),
        InfoCard(symbol: "gearshape.fill", tint: .gray, title: String(localized: "Made to fit"),
                 detail: String(localized: "Liquid Glass, Fade or Black, your colour, your size. It updates itself.")),
        InfoCard(symbol: "ellipsis.circle.fill", tint: .white, title: String(localized: "And many more…"),
                 detail: String(localized: "Look around Settings to find the rest.")),
    ]

    var body: some View { InfoCardGrid(cards: Self.features) }
}
