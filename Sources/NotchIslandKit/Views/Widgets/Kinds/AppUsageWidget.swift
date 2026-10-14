import AppKit
import SwiftUI

/// Usage by App, the iPhone's Battery Usage by App on the island: the apps that used the most
/// battery on the day Daily Usage has picked (today, from midnight, until a day is picked there),
/// each with its icon, its name and the percent of the battery it used — together what Daily Usage
/// says the day used. It reads `AppEnergyRecorder`'s ledger, leased while
/// shown; a picture shows a sample day and reads nothing.
///
/// The list is moved and sized in Customize as a part of its own (its look comes later), the title
/// and the day as texts (`WidgetLabel`). How many rows: Customize's Settings (`WidgetConfig.count`).
struct AppUsageWidget: View {
    let widget: IslandWidget
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.isElementEditing) private var isEditing
    @Environment(\.widgetDate) private var fixedDate
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    static var title: String { String(localized: "Usage by App") }

    static func titlePoints(inner: CGSize) -> CGFloat { DailyUsageWidget.titlePoints(inner: inner) }

    /// Rows until the user sets how many: three in a widget two cells tall, five in a taller one.
    static func count(_ widget: IslandWidget) -> Int { widget.config.count ?? (widget.frame.height <= 2 ? 3 : 5) }

    static func headerHeight(_ widget: IslandWidget, inner: CGSize) -> CGFloat {
        guard widget.shows(.label) || widget.shows(.usageDay) else { return 0 }
        return (titlePoints(inner: inner) * 1.4).rounded(.up)
    }

    /// A day as the pictures show it: Daily Usage's sample day (70 %).
    static let samples: [AppUsageRow] = [
        ("com.apple.Safari", "Safari", "/Applications/Safari.app", 0.34),
        ("com.apple.mail", "Mail", "/System/Applications/Mail.app", 0.19),
        ("com.apple.Music", "Music", "/System/Applications/Music.app", 0.14),
        ("com.apple.MobileSMS", "Messages", "/System/Applications/Messages.app", 0.11),
        (AppAttribution.systemKey, "macOS", nil, 0.08),
        ("com.apple.finder", "Finder", "/System/Library/CoreServices/Finder.app", 0.06),
        ("com.apple.Notes", "Notes", "/System/Applications/Notes.app", 0.05),
        ("com.apple.Photos", "Photos", "/System/Applications/Photos.app", 0.03),
    ].map { AppUsageRow(key: $0.0, name: $0.1, path: $0.2, points: $0.3 * 70, share: $0.3) }

    /// What an empty day says: why there is nothing and when there will be.
    static func emptyText(picked: Bool, onBattery: Bool) -> (title: String, detail: String) {
        if picked { return (String(localized: "Nothing counted"), String(localized: "The Mac did not run on battery that day.")) }
        if onBattery { return (String(localized: "Counting…"), String(localized: "The apps appear when the battery drops a percent.")) }
        return (String(localized: "Not on battery today"), String(localized: "Apps are counted while the Mac runs on battery."))
    }

    /// The percent of the battery: "<1 %" below half a percent, as the iPhone shows a sliver.
    static func pointsText(_ points: Double) -> String {
        points < 0.5 ? "<" + IslandFormat.percent(0.01) : IslandFormat.percent(points / 100)
    }

    var body: some View {
        let battery = model.battery
        var calendar = Calendar(identifier: .gregorian)
        let _ = calendar.timeZone = timeZone
        let _ = calendar.locale = locale
        let today = calendar.startOfDay(for: fixedDate ?? .now)
        let picked = isPreview ? nil : battery.pickedDay(calendar: calendar)
        let rows = isPreview ? Self.samples : battery.appUsage(on: picked, calendar: calendar)
        let header = Self.headerHeight(widget, inner: size)
        VStack(alignment: .leading, spacing: header > 0 ? 4 : 0) {
            if header > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if widget.shows(.label) { title }
                    Spacer(minLength: 4)
                    if widget.shows(.usageDay) { dayLabel(picked ?? today, today: today, calendar: calendar) }
                }
                .frame(height: header)
            }
            AppUsageList(rows: rows, count: Self.count(widget), showsEmpty: !isEditing && (isPreview || battery.appLedger != nil),
                         empty: Self.emptyText(picked: picked != nil, onBattery: model.power.isOnBattery))
                .frame(width: size.width, height: max(size.height - header - (header > 0 ? 4 : 0), 0))
                .movableElement(.appList, of: widget)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .whileShown {
            guard !isPreview else { return }
            battery.acquire(.apps)
            battery.acquire(.history)
        } stop: {
            guard !isPreview else { return }
            battery.release(.apps)
            battery.release(.history)
        }
    }

    private var title: some View {
        let points = Self.titlePoints(inner: size)
        return WidgetLabel(id: .label, text: Self.title, widget: widget, size: points, weight: .semibold, isSecondary: true) {
            Text(Self.title)
                .font(.system(size: points, weight: .semibold))
                .clearTextEdge().foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .movableElement(.label, of: widget)
    }

    private func dayLabel(_ day: Date, today: Date, calendar: Calendar) -> some View {
        let points = DailyUsageWidget.dayPoints(inner: size)
        let text = DailyUsageWidget.dayText(day, today: today, locale: locale, calendar: calendar)
        return WidgetLabel(id: .usageDay, text: text, widget: widget, size: points, weight: .medium, isSecondary: true) {
            Text(text)
                .font(.system(size: points, weight: .medium))
                .clearTextEdge().foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize()
        .movableElement(.usageDay, of: widget)
    }
}

/// The rows: an app's icon, its name and the percent of the battery it used, that also as a thin bar
/// under the name (the largest app's the longest); `count` rows share the height, at most 24 points each.
struct AppUsageList: View {
    let rows: [AppUsageRow]
    let count: Int
    /// The empty day's text; false in the editor, where the rows' room is what is being set.
    var showsEmpty = true
    var empty: (title: String, detail: String)

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = min(proxy.size.height / CGFloat(max(count, 1)), 24)
            let iconSize = (rowHeight * 0.78).rounded()
            let points = max(min(rowHeight * 0.48, 12), 8)
            let largest = rows.first?.share ?? 1
            if rows.isEmpty {
                if showsEmpty {
                    // Two lines, centred: what it is, then when the apps come (wrapped, never cut).
                    VStack(spacing: 3) {
                        Text(empty.title)
                            .font(.system(size: 12, weight: .semibold))
                            .clearTextEdge().foregroundStyle(.secondary)
                        Text(empty.detail)
                            .font(.system(size: 10, weight: .medium))
                            .clearTextEdge().foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.prefix(count)) { row in
                        HStack(spacing: 6) {
                            AppUsageIcon(row: row, size: iconSize)
                            // The name and the percent on a line, the bar under both: the name has
                            // all the room the percent leaves.
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(row.name)
                                        .font(.system(size: points, weight: .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(AppUsageWidget.pointsText(row.points))
                                        .font(.system(size: points, weight: .semibold, design: .rounded).monospacedDigit())
                                        .clearTextEdge().foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                GeometryReader { bar in
                                    Capsule()
                                        .fill(.secondary.opacity(0.35))
                                        .frame(width: max(bar.size.width * row.share / max(largest, 0.01), 2), height: 2)
                                }
                                .frame(height: 2)
                            }
                        }
                        .frame(height: rowHeight)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }
}

/// An app's own icon; macOS's processes together as a gear, what was not measured as a question mark.
struct AppUsageIcon: View {
    let row: AppUsageRow
    let size: CGFloat

    /// Icons by bundle path: Finder's look-up is a few milliseconds, the rows ask at every redraw.
    @MainActor private static var icons: [String: NSImage] = [:]

    static func icon(_ path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    var body: some View {
        if let path = row.path, !row.isSystem, !row.isUnmeasured {
            Image(nsImage: Self.icon(path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: row.isUnmeasured ? "questionmark" : "gearshape.2.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 0.82, height: size * 0.82)
                .background(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(Color(white: 0.42)))
                .frame(width: size, height: size)
        }
    }
}
