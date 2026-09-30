import SwiftUI

// The Mac's other readings, a widget each (`SystemSpecs`): the network's speed, the free disk space,
// and how long the Mac has been up with how warm it runs. Each reads only while it is shown; a
// picture in Settings shows sample values and reads nothing.

enum SystemReadings {
    static func network(download: Double, upload: Double) -> WidgetReading {
        WidgetReading("↓ " + NetworkMonitor.rate(download), caption: "↑ " + NetworkMonitor.rate(upload), symbol: "network",
                      widest: "↓ 888.8 MB/s", spoken: String(localized: "Download \(NetworkMonitor.rate(download)), upload \(NetworkMonitor.rate(upload))"))
    }

    /// The startup disk's free space (what Finder calls available) and its size.
    nonisolated static func disk() -> (free: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }

    static func disk(_ space: (free: Int64, total: Int64)?) -> WidgetReading {
        guard let space else { return WidgetReading("—", caption: String(localized: "Free"), symbol: "internaldrive.fill") }
        let low = space.total > 0 && Double(space.free) / Double(space.total) < 0.1
        return WidgetReading(ByteCountFormatter.string(fromByteCount: space.free, countStyle: .file),
                             caption: String(localized: "Free of \(ByteCountFormatter.string(fromByteCount: space.total, countStyle: .file))"),
                             symbol: "internaldrive.fill", tint: low ? .orange : nil, widest: "888.8 GB")
    }

    static func uptime(_ seconds: TimeInterval, thermal: ProcessInfo.ThermalState, format: WidgetFormat) -> WidgetReading {
        let minutes = Int(seconds / 60)
        let value = minutes >= 24 * 60
            ? Duration.seconds(minutes * 60).formatted(.units(allowed: [.days, .hours], width: .narrow))
            : format.duration(minutes: minutes)
        let (state, tint): (String, Color?) = switch thermal {
        case .nominal: (String(localized: "Running Cool"), nil)
        case .fair: (String(localized: "Warm"), nil)
        case .serious: (String(localized: "Hot"), .orange)
        case .critical: (String(localized: "Too Hot"), .red)
        @unknown default: (String(localized: "Uptime"), nil)
        }
        return WidgetReading(value, caption: state, symbol: thermal == .nominal || thermal == .fair ? "clock.arrow.circlepath" : "thermometer.high",
                             tint: tint, widest: "88d 88h")
    }
}

/// Feeds a system reading's widget: the network's speed sampled while shown, the disk read as the
/// widget comes on screen, the uptime redrawn on the minute.
struct SystemReadingSource<Content: View>: View {
    let kind: IslandWidgetKind
    @ViewBuilder let content: (WidgetReading) -> Content

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPicture
    @Environment(\.widgetReadsLive) private var readsLive
    /// Samples in a picture that reads nothing.
    private var isPreview: Bool { isPicture && !readsLive }
    @Environment(\.widgetStyle) private var style
    @Environment(\.locale) private var locale
    @State private var disk: (free: Int64, total: Int64)?

    var body: some View {
        switch kind {
        case .network:
            let network = model.network
            content(isPreview ? SystemReadings.network(download: 2_400_000, upload: 310_000)
                              : SystemReadings.network(download: network.download, upload: network.upload))
                .whileShown { if !isPreview { withoutAnimation { network.startObserving() } } } stop: { if !isPreview { network.stopObserving() } }
        case .diskSpace:
            content(SystemReadings.disk(isPreview ? (212_000_000_000, 494_000_000_000) : disk))
                // Read as it comes on screen: the space changes slowly, and nothing watches it.
                .whileShown {
                    guard !isPreview else { return }
                    Task {
                        let space = await Task.detached(priority: .utility) { SystemReadings.disk() }.value
                        disk = space
                    }
                }
        default:
            let format = WidgetFormat(style.format, locale: locale)
            if isPreview {
                content(SystemReadings.uptime(3 * 86400 + 4 * 3600, thermal: .nominal, format: format))
            } else {
                PanelTimelineView(.everyMinute) { _ in
                    content(SystemReadings.uptime(ProcessInfo.processInfo.systemUptime, thermal: ProcessInfo.processInfo.thermalState, format: format))
                }
            }
        }
    }
}

// MARK: - AirPods

/// The AirPods' batteries as last reported: each bud and the case, a level each.
struct AirPodsBatteryWidget: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        AirPodsReadingSource { ReadingWidget(widget: widget, size: size, reading: $0) }
    }
}

struct AirPodsReadingSource<Content: View>: View {
    @ViewBuilder let content: (WidgetReading) -> Content

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPicture
    @Environment(\.widgetReadsLive) private var readsLive
    /// Samples in a picture that reads nothing.
    private var isPreview: Bool { isPicture && !readsLive }
    @Environment(\.widgetStyle) private var style
    @Environment(\.locale) private var locale

    var body: some View {
        let store = model.airPodsBattery
        let format = WidgetFormat(style.format, locale: locale)
        content(Self.reading(isPreview ? .init(name: "AirPods Pro", left: 86, right: 84, chargingCase: 60, single: nil, date: Date())
                                       : store.last, format: format))
            .whileShown { if !isPreview { store.acquire() } } stop: { if !isPreview { store.release() } }
    }

    /// The buds' level (the lower one), and under it each part's: "L 86% · R 84% · Case 60%".
    static func reading(_ last: AirPodsBatteryStore.Reading?, format: WidgetFormat) -> WidgetReading {
        guard let last, let lowest = last.lowest ?? last.chargingCase else {
            return WidgetReading("—", caption: String(localized: "Not seen yet"), symbol: "airpods", widest: format.percent(1))
        }
        func level(_ value: Int) -> String { format.percent(Double(value) / 100) }
        var parts: [String] = []
        if let left = last.left, let right = last.right, left != right {
            parts = [String(localized: "L \(level(left))"), String(localized: "R \(level(right))")]
        }
        if let chargingCase = last.chargingCase { parts.append(String(localized: "Case \(level(chargingCase))")) }
        return WidgetReading(level(lowest), caption: parts.isEmpty ? last.name : parts.joined(separator: " · "),
                             symbol: "airpods", tint: lowest <= 10 ? .red : lowest <= 20 ? .orange : nil, widest: format.percent(1),
                             spoken: "\(last.name): \(level(lowest))")
    }
}
