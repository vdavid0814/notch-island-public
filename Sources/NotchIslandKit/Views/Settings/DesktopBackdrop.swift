import AppKit
import ImageIO
import SwiftUI

/// What the widget studio and the surface previews show behind the island.
nonisolated enum DesktopBackdropStyle: String, CaseIterable, Identifiable, Sendable {
    /// The system's default wallpaper look: deep blue light folding over itself.
    case system
    /// The picture on this Mac's desktop.
    case desktop

    nonisolated static let key = "ni2.studio.backdrop"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "macOS Default"
        case .desktop: "Your Desktop"
        }
    }
}

/// A desktop for previews: the default macOS wallpaper, drawn as a mesh gradient (sharp at any
/// size, nothing to load), or the user's own desktop picture, downsampled off the main thread.
struct DesktopBackdrop: View {
    var style: DesktopBackdropStyle = .system

    @State private var picture: NSImage?

    var body: some View {
        ZStack {
            DefaultWallpaper()
            if style == .desktop, let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.25), value: picture == nil)
        .task(id: style) {
            guard style == .desktop else {
                picture = nil
                return
            }
            guard let url = NSScreen.main.flatMap({ NSWorkspace.shared.desktopImageURL(for: $0) }) else { return }
            picture = await Self.load(url).map { NSImage(cgImage: $0, size: .zero) }
        }
        .accessibilityHidden(true)
    }

    @concurrent private static func load(_ url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800,
        ] as CFDictionary)
    }
}

/// The macOS default wallpaper's look — layers of blue light over a deep navy, brightest in a
/// band across the middle — as a mesh gradient.
struct DefaultWallpaper: View {
    var body: some View {
        MeshGradient(
            width: 4, height: 4,
            points: [
                [0, 0], [0.33, 0], [0.66, 0], [1, 0],
                [0, 0.36], [0.28, 0.30], [0.7, 0.42], [1, 0.3],
                [0, 0.7], [0.36, 0.64], [0.62, 0.74], [1, 0.66],
                [0, 1], [0.33, 1], [0.66, 1], [1, 1],
            ],
            colors: [
                Color(red: 0.02, green: 0.06, blue: 0.22), Color(red: 0.03, green: 0.10, blue: 0.32),
                Color(red: 0.05, green: 0.16, blue: 0.42), Color(red: 0.04, green: 0.10, blue: 0.30),
                Color(red: 0.06, green: 0.28, blue: 0.62), Color(red: 0.20, green: 0.52, blue: 0.92),
                Color(red: 0.36, green: 0.70, blue: 0.98), Color(red: 0.10, green: 0.36, blue: 0.74),
                Color(red: 0.10, green: 0.20, blue: 0.58), Color(red: 0.44, green: 0.62, blue: 0.96),
                Color(red: 0.16, green: 0.34, blue: 0.80), Color(red: 0.28, green: 0.24, blue: 0.70),
                Color(red: 0.05, green: 0.06, blue: 0.24), Color(red: 0.12, green: 0.12, blue: 0.40),
                Color(red: 0.08, green: 0.10, blue: 0.34), Color(red: 0.14, green: 0.08, blue: 0.32),
            ],
            smoothsColors: true
        )
    }
}

/// The menu bar across the top of a preview desktop: the Apple menu and an app's menus on the
/// left, status items and the clock on the right; the island covers the middle. Each side shows
/// as many items as fit beside the island, never a truncated menu.
struct PreviewMenuBar: View {
    let height: CGFloat
    /// The island's width: the part of the bar it covers.
    let notchWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let side = max(0, (proxy.size.width - notchWidth) / 2 - 22)
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    menus(["Finder", "File", "Edit", "View", "Go", "Window"])
                    menus(["Finder", "File", "Edit", "View"])
                    menus(["Finder", "File"])
                    menus([])
                }
                .frame(width: side, alignment: .leading)
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    status(showsIcons: 3, showsDate: true)
                    status(showsIcons: 3, showsDate: false)
                    status(showsIcons: 1, showsDate: false)
                    EmptyView()
                }
                .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(width: proxy.size.width, height: height)
        }
        .frame(height: height)
        .font(.system(size: height * 0.42, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
        .background(.black.opacity(0.12))
        .accessibilityHidden(true)
    }

    private func menus(_ titles: [String]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: height * 0.46, weight: .semibold))
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(title).fontWeight(index == 0 ? .bold : .medium)
            }
        }
        .fixedSize()
    }

    private func status(showsIcons: Int, showsDate: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(["switch.2", "wifi", "battery.75percent"].suffix(showsIcons)), id: \.self) {
                Image(systemName: $0)
            }
            Text(Date.now, format: showsDate ? .dateTime.weekday(.abbreviated).hour().minute() : .dateTime.hour().minute())
        }
        .fixedSize()
    }
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
