import SwiftUI

/// What fills the Mac's disk — System Data most of all — and clearing it, from the drive beside
/// About's title in Settings (`AppInfoMenu`). In the look of How NotchIsland Works (`InfoPageShell`).
/// Measured while it is open; everything it clears goes to the Trash, except the Trash itself.
/// Every card says plainly whether its contents are filler, something the user would miss, or
/// macOS's to manage, and where System Settings counts it (asked for).
struct StoragePage: View {
    private enum Topic: String, CaseIterable, Identifiable {
        case overview, filler, notice, keep, yours

        var id: Self { self }

        var title: String {
            switch self {
            case .overview: String(localized: "Overview")
            case .filler: String(localized: "Safe to Delete")
            case .notice: String(localized: "Think First")
            case .keep: String(localized: "Leave Alone")
            case .yours: String(localized: "Your Files")
            }
        }
    }

    let close: () -> Void

    @State private var report = StorageReport()
    @Environment(AppModel.self) private var model

    /// Rows of cards a tab fits without scrolling (asked for): more than six cards go four to a row.
    static func columns(for count: Int) -> Int { count > 6 ? 4 : 3 }

    var body: some View {
        InfoPageShell(topics: Topic.allCases, title: \.title, label: "Storage", close: close, page: page)
            .onAppear { report.start() }
            .onDisappear {
                report.stop()
                model.storageLoading = nil
            }
            // The notch shows the measuring (`StorageLoadingBand`), gone a moment after it is full.
            .onChange(of: report.progress, initial: true) { _, progress in
                model.storageLoading = report.isDone ? 1 : progress
                guard report.isDone else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [model] in
                    if model.storageLoading == 1 { model.storageLoading = nil }
                }
            }
    }

    @ViewBuilder private func page(_ topic: Topic) -> some View {
        switch topic {
        case .overview: StorageOverview(report: report)
        case .filler: StorageCards(report: report, verdict: .filler)
        case .notice: StorageCards(report: report, verdict: .notice)
        case .keep: StorageCards(report: report, verdict: .keep)
        case .yours: StorageCards(report: report, verdict: .yours)
        }
    }
}

nonisolated enum StorageFormat {
    static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// A sum still growing: "…" until it has something, then the sum and "…" until done.
    static func measured(_ bytes: Int64, isDone: Bool) -> String {
        isDone ? self.bytes(bytes) : bytes == 0 ? "…" : self.bytes(bytes) + "…"
    }
}

/// How each verdict looks: the same colour and words on the bars, the badges and the cards.
extension StorageSpot.Verdict {
    var color: Color {
        switch self {
        case .filler: .green
        case .notice: .orange
        case .keep: Color(white: 0.62)
        case .yours: .blue
        }
    }

    var symbol: String {
        switch self {
        case .filler: "checkmark.circle.fill"
        case .notice: "exclamationmark.triangle.fill"
        case .keep: "hand.raised.fill"
        case .yours: "person.crop.circle.fill"
        }
    }

    var badge: String {
        switch self {
        case .filler: String(localized: "Safe to delete")
        case .notice: String(localized: "You'd notice")
        case .keep: String(localized: "Leave alone")
        case .yours: String(localized: "Your files")
        }
    }

    var meaning: String {
        switch self {
        case .filler: String(localized: "Made again when it's needed. Nothing of yours goes, and you won't notice it's gone.")
        case .notice: String(localized: "Can go, but an app loses its data or downloads it again. Read the card first.")
        case .keep: String(localized: "Counted in your storage, but only its app or macOS should remove it.")
        case .yours: String(localized: "Your apps, documents, photos and music. Not filler: only you decide what goes.")
        }
    }
}

// MARK: - Overview

/// Two rows that fit the page: what each verdict adds up to, then what takes the space beside what
/// System Data is.
private struct StorageOverview: View {
    let report: StorageReport

    private func total(_ verdict: StorageSpot.Verdict) -> Int64 {
        report.spots.filter { $0.verdict == verdict }.reduce(0) { $0 + report.bytes(of: $1) }
    }

    var body: some View {
        VStack(spacing: InfoRow<EmptyView>.spacing) {
            InfoRow {
                ForEach([StorageSpot.Verdict.filler, .notice, .keep, .yours], id: \.self) { verdict in
                    StorageBox(verdict: verdict) {
                        Label(verdict.badge, systemImage: verdict.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(verdict.color)
                        Text(verbatim: StorageFormat.measured(total(verdict), isDone: report.isDone))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(verdict.meaning)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            InfoRow {
                StorageBox {
                    HStack(alignment: .firstTextBaseline) {
                        Label("What takes the space", systemImage: "chart.bar.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer(minLength: 8)
                        Text(verbatim: report.capacity > 0
                             ? String(localized: "\(StorageFormat.bytes(report.available)) free of \(StorageFormat.bytes(report.capacity))") : "")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    StorageBars(report: report)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(2)
                StorageBox {
                    Label("What is System Data?", systemImage: "questionmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("System Settings ▸ Storage puts there whatever has no row of its own.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    StorageLine(title: String(localized: "\(StorageFormat.measured(report.systemData, isDone: report.isDone)) found here"),
                                detail: String(localized: "The rest is macOS's own, or needs Full Disk Access."))
                    StorageLine(title: String(localized: "Much of it is filler"),
                                detail: String(localized: "Caches, logs, leftovers, downloads kept just in case."))
                    StorageLine(title: String(localized: "Some is your apps' data"),
                                detail: String(localized: "Their settings, sign-ins and downloads."))
                    StorageLine(title: String(localized: "The rest is macOS's"),
                                detail: report.snapshots == 0 ? String(localized: "Swap and Spotlight's index. It manages them itself.")
                                    : String(localized: "Swap, Spotlight's index and \(report.snapshots) Time Machine snapshots."))
                }
                .frame(width: 330)
            }
        }
    }
}

/// A bold line and a line under it, smaller than the info pages' (`InfoLine`), without a symbol (asked for).
private struct StorageLine: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The largest spots measured, as bars of the largest, coloured by what clearing them means: as many
/// as the box has room for (asked for), the last one what nothing here measured.
private struct StorageBars: View {
    let report: StorageReport

    /// Rows the box has room for, measured.
    @State private var room = 12
    private static let rowHeight: CGFloat = 22
    private static let spacing: CGFloat = 7

    var body: some View {
        let measured = report.spots.filter { report.bytes(of: $0) >= 1 << 20 }.sorted { report.bytes(of: $0) > report.bytes(of: $1) }
        let rest = report.isDone ? report.capacity - report.available - report.found : 0
        let showsRest = rest >= 1 << 30
        let largest = measured.prefix(max(1, room - (showsRest ? 1 : 0)))
        let top = Double(max(largest.first.map { report.bytes(of: $0) } ?? 1, showsRest ? rest : 0))
        VStack(spacing: Self.spacing) {
            if largest.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(largest)) { spot in
                StorageBar(symbol: spot.verdict.symbol, color: spot.verdict.color, help: spot.verdict.badge, title: spot.title,
                           category: spot.category.title, bytes: report.bytes(of: spot), top: top)
            }
            if showsRest {
                StorageBar(symbol: "questionmark.circle.fill", color: .white.opacity(0.35), help: String(localized: "Not measured here"),
                           title: String(localized: "Everything else"), category: String(localized: "Other"), bytes: rest, top: top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Int.self) { proxy in
            max(1, Int((proxy.size.height + Self.spacing) / (Self.rowHeight + Self.spacing)))
        } action: { room = $0 }
    }
}

/// One bar: what it is, where System Settings counts it, and how large, against the largest.
private struct StorageBar: View {
    let symbol: String
    let color: Color
    let help: String
    let title: String
    let category: String
    let bytes: Int64
    let top: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 18)
                .help(help)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Text(category)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(4, proxy.size.width * Double(bytes) / top))
            }
            .frame(height: 7)
            Text(verbatim: StorageFormat.bytes(bytes))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 66, alignment: .trailing)
        }
        .frame(height: 22)
    }
}

// MARK: - Cards

/// A verdict's spots under a line on what they all are, in full rows: three to a row, four past six,
/// so a tab fits without scrolling.
private struct StorageCards: View {
    let report: StorageReport
    let verdict: StorageSpot.Verdict

    @Environment(\.infoCardRadius) private var radius

    var body: some View {
        let spots = report.shown(verdict)
        let columns = StoragePage.columns(for: spots.count)
        VStack(spacing: InfoRow<EmptyView>.spacing) {
            HStack(spacing: 10) {
                Image(systemName: verdict.symbol).foregroundStyle(verdict.color)
                Text(verdict.meaning).foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(verdict.color.opacity(0.14), in: .rect(cornerRadius: radius, style: .continuous))
            // Each row as high as its tallest card: stretched over the page, the cards were mostly empty.
            ForEach(Array(stride(from: 0, to: spots.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: InfoRow<EmptyView>.spacing) {
                    ForEach(spots[start..<min(start + columns, spots.count)]) { spot in
                        StorageCard(report: report, spot: spot).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    ForEach(spots.count..<max(spots.count, start + columns), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if spots.isEmpty {
                StorageBox {
                    Label(report.isDone ? String(localized: "Nothing large here") : String(localized: "Measuring…"),
                          systemImage: report.isDone ? "checkmark.circle.fill" : "hourglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                    if !report.isDone { ProgressView().controlSize(.small) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A spot: what it is, how large, what happens if it goes, and Move to Trash, asked once more on the
/// card itself (a dialog over the island's panel would take the click as one outside Settings).
private struct StorageCard: View {
    let report: StorageReport
    let spot: StorageSpot

    @State private var isAsking = false

    var body: some View {
        StorageBox(verdict: spot.verdict) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: spot.symbol).foregroundStyle(spot.tint)
                Text(spot.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                size
            }
            .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 5) {
                Label(spot.verdict.badge, systemImage: spot.verdict.symbol)
                    .foregroundStyle(spot.verdict.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(spot.verdict.color.opacity(0.18), in: .capsule)
                Text(spot.category.title)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: .capsule)
                    .help("Where System Settings ▸ Storage counts it")
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            Text(spot.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if report.size(of: spot) == .denied {
                Text("Size unknown: macOS lets NotchIsland in here only with Full Disk Access.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            (Text("If you delete it: ").bold() + Text(spot.consequence))
                .font(.system(size: 13))
                .foregroundStyle(spot.verdict == .filler && spot.removal != .emptyTrash ? Color.green : .white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if isAsking {
                Text(question)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
    }

    @ViewBuilder private var size: some View {
        switch report.size(of: spot) {
        case .measuring:
            ProgressView().controlSize(.mini)
        case .bytes(let bytes):
            Text(verbatim: StorageFormat.bytes(bytes))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        case .denied:
            Text(verbatim: "?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow)
        }
    }

    private var question: String {
        let amount = StorageFormat.bytes(report.bytes(of: spot))
        let action = spot.removal == .emptyTrash ? String(localized: "Delete \(amount) for good?")
            : String(localized: "Move \(amount) to the Trash?")
        return [action, spot.caution].compactMap { $0 }.joined(separator: " ")
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 6) {
            if isAsking {
                Button("Cancel") { withAnimation(.smooth(duration: 0.2)) { isAsking = false } }
                    .buttonStyle(.glass)
                Button(spot.removal == .emptyTrash ? "Empty Trash" : "Move to Trash", role: .destructive) {
                    withAnimation(.smooth(duration: 0.2)) { isAsking = false }
                    report.remove(spot)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            } else if report.removing.contains(spot.id) {
                ProgressView().controlSize(.small)
                Text(spot.removal == .emptyTrash ? "Emptying…" : "Moving to the Trash…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.6))
            } else if report.size(of: spot) == .denied {
                Button("Allow Full Disk Access", systemImage: "lock.open") { report.openFullDiskAccess() }
                    .buttonStyle(.glass)
                showButton
            } else if spot.removal == .none {
                Button("Show in Finder", systemImage: "folder") { report.reveal(spot) }
                    .buttonStyle(.glass)
            } else {
                Button(spot.removal == .emptyTrash ? "Empty Trash" : "Move to Trash", systemImage: "trash") {
                    withAnimation(.smooth(duration: 0.2)) { isAsking = true }
                }
                .buttonStyle(.glass)
                .disabled(report.bytes(of: spot) == 0)
                showButton
            }
        }
        .lineLimit(1)
    }

    private var showButton: some View {
        Button("Show", systemImage: "folder") { report.reveal(spot) }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .help("Show in Finder")
    }
}

/// The page's card, tighter than the info pages' (`InfoWidget`) so a tab fits without scrolling; its
/// edge in its verdict's colour.
private struct StorageBox<Content: View>: View {
    var verdict: StorageSpot.Verdict?
    @ViewBuilder var content: Content

    @Environment(\.infoCardRadius) private var radius

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(verdict.map { $0.color.opacity(0.35) } ?? .white.opacity(0.08), lineWidth: verdict == nil ? 1 : 1.5)
            }
    }
}
