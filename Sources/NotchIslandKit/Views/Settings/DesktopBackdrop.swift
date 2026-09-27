import AppKit
import SwiftUI

/// The menu bar across the top of a preview desktop, as macOS draws it: no bar of its own, just
/// the Apple menu and an app's menus on the left, status items and the clock on the right, in
/// white over a dark wallpaper and in black over a light one; the island covers the middle. Each
/// side shows as many items as fit beside the island, never a truncated menu. Everything scales
/// with `height`, so the same bar tops the widget studio's stage and the smallest pictures.
struct PreviewMenuBar: View {
    let height: CGFloat
    /// The island's width: the part of the bar it covers.
    let notchWidth: CGFloat
    /// Over a light wallpaper the menu bar's text is dark.
    var darkText = false
    /// A shade behind the whole bar (over the checkerboard, where no text colour would read).
    var backing: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let inset = height * 0.5
            let side = max(0, (proxy.size.width - notchWidth) / 2 - inset - height * 0.4)
            let now = Date.now
            let menusKey = PreviewMenuBarFit.Key(height: height, side: side, text: "")
            let statusKey = PreviewMenuBarFit.Key(height: height, side: side, text: Self.dateText(now, showsDate: true)
                                                  + "|" + Self.dateText(now, showsDate: false))
            HStack(spacing: 0) {
                Group {
                    // The variant that fits, once found for this width, is built alone: a ViewThatFits
                    // lays out every variant it tries, text and all, and ~10 pictures each tried up
                    // to five per side at every opening of Settings (measured: ~15–20 % of it).
                    if let fit = PreviewMenuBarFit.menus[menusKey] {
                        menus(Self.menuVariants[fit], now: now)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            ForEach(Self.menuVariants.indices, id: \.self) { index in
                                menus(Self.menuVariants[index], now: now)
                                    .onAppear { PreviewMenuBarFit.menus[menusKey] = index }
                            }
                        }
                    }
                }
                .frame(width: side, alignment: .leading)
                Spacer(minLength: 0)
                Group {
                    if let fit = PreviewMenuBarFit.status[statusKey] {
                        statusVariant(fit, now: now)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            ForEach(0..<Self.statusVariantCount, id: \.self) { index in
                                statusVariant(index, now: now)
                                    .onAppear { PreviewMenuBarFit.status[statusKey] = index }
                            }
                        }
                    }
                }
                .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, inset)
            .frame(width: proxy.size.width, height: height)
        }
        .frame(height: height)
        .font(.system(size: height * 0.44, weight: .medium))
        .foregroundStyle(darkText ? Color.black.opacity(0.85) : Color.white.opacity(0.95))
        // The system's faint shade under the menu bar, which keeps its text legible anywhere.
        .background(LinearGradient(colors: [(darkText ? Color.white : Color.black).opacity(0.14), .clear],
                                   startPoint: .top, endPoint: .bottom))
        .background(.black.opacity(backing))
        .shadow(color: .black.opacity(darkText ? 0 : 0.25), radius: height * 0.06)
        .accessibilityHidden(true)
    }

    /// Control Center, Wi-Fi and the battery, as on a MacBook's menu bar.
    static let statusIcons = ["battery.75percent", "wifi", "switch.2"]

    static let menuVariants: [[String]] = [
        ["Finder", "File", "Edit", "View", "Go", "Window", "Help"],
        ["Finder", "File", "Edit", "View", "Go"],
        ["Finder", "File", "Edit"],
        ["Finder"],
        [],
    ]

    static let statusVariantCount = 5

    @ViewBuilder private func statusVariant(_ index: Int, now: Date) -> some View {
        switch index {
        case 0: status(icons: Self.statusIcons, showsDate: true, now: now)
        case 1: status(icons: Self.statusIcons, showsDate: false, now: now)
        case 2: status(icons: Array(Self.statusIcons.suffix(2)), showsDate: false, now: now)
        case 3: status(icons: [], showsDate: false, now: now)
        default: EmptyView()
        }
    }

    static func dateText(_ date: Date, showsDate: Bool) -> String {
        date.formatted(showsDate ? .dateTime.month(.abbreviated).day().weekday(.abbreviated).hour().minute()
                                 : .dateTime.hour().minute())
    }

    private func menus(_ titles: [String], now: Date) -> some View {
        HStack(spacing: height * 0.62) {
            Image(systemName: "apple.logo").font(.system(size: height * 0.5, weight: .semibold))
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(title).fontWeight(index == 0 ? .bold : .medium)
            }
        }
        .fixedSize()
    }

    private func status(icons: [String], showsDate: Bool, now: Date) -> some View {
        HStack(spacing: height * 0.55) {
            ForEach(icons, id: \.self) { Image(systemName: $0) }
            Text(now, format: showsDate ? .dateTime.month(.abbreviated).day().weekday(.abbreviated).hour().minute()
                                        : .dateTime.hour().minute())
        }
        .fixedSize()
    }
}

/// Which variant of the preview menu bar fits a side of a given width (`PreviewMenuBar`).
@MainActor enum PreviewMenuBarFit {
    struct Key: Hashable {
        let height: CGFloat
        let side: CGFloat
        /// What the variants' width depends on besides the fixed titles (the clock's text).
        let text: String
    }

    static var menus: [Key: Int] = [:]
    static var status: [Key: Int] = [:]
}

/// NotchIsland's mark: the island hanging from a black squircle's top edge, in Liquid Glass
/// colours. Stands in for the app icon wherever Settings shows the app.
struct AppMark: View {
    var side: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.36, blue: 0.86), Color(red: 0.05, green: 0.08, blue: 0.26)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: side * 0.16, bottomTrailingRadius: side * 0.16, style: .continuous)
                    .fill(.black)
                    .frame(width: side * 0.62, height: side * 0.3)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: side * 0.025).fill(.pink.gradient)
                            .frame(width: side * 0.11, height: side * 0.11).padding(.leading, side * 0.07)
                    }
                    .overlay(alignment: .trailing) {
                        HStack(spacing: side * 0.02) {
                            ForEach(0..<3) { index in
                                Capsule().fill(.white.opacity(0.85))
                                    .frame(width: side * 0.025, height: side * [0.06, 0.1, 0.05][index])
                            }
                        }
                        .padding(.trailing, side * 0.08)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
