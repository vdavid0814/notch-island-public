import AppKit
import CoreGraphics

/// macOS's own volume card: the one it shows for a volume change it handles itself (an AirPods stem
/// swipe, which no key tap sees).
///
/// A `MenuBarAgent` window at level 101, 352 × 148 pt with its shadow, just below the menu bar
/// (window list, macOS 27, measured). Where depends on the Space: under the notch over a full-screen
/// app, right of the screen's centre on the desktop and beside a tiled window (x 848 of 1280, 80 pt
/// from the right edge). So where it came up last is kept per situation (`SystemVolumeCardMemory`),
/// and each time the window list says where it really is.
nonisolated enum SystemVolumeCard {
    static let windowSize = CGSize(width: 352, height: 148)

    /// Which of macOS's cards: they share the window, not the card in it.
    nonisolated enum Kind: Sendable, Hashable {
        case volume, airPods

        /// The card in its window (the rest is its shadow), measured from the window's image with its
        /// alpha (`screencapture -l`, macOS 27): centred, `top` below the window's top edge.
        var size: CGSize {
            switch self {
            case .volume: CGSize(width: 293, height: 64)
            case .airPods: CGSize(width: 236, height: 52)
            }
        }

        var top: CGFloat { 10 }

        /// Continuous corners, fitted to the edge of each card's image (the AirPods card is all but
        /// a capsule).
        var radius: CGFloat {
            switch self {
            case .volume: 23
            case .airPods: 25.5
            }
        }
    }
    /// The desktop's card: its right edge this far from the screen's.
    static let desktopRightMargin: CGFloat = 80
    static let owner = "MenuBarAgent"

    /// The card's window on screen now, in global AppKit coordinates; nil when none is up.
    static func find() -> CGRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows {
            guard window[kCGWindowOwnerName as String] as? String == owner,
                  (window[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  abs(bounds.width - windowSize.width) < 12, abs(bounds.height - windowSize.height) < 12,
                  bounds.minY < 80 else { continue }
            return appKit(bounds)
        }
        return nil
    }

    @concurrent static func findOffMain() async -> CGRect? { find() }

    /// A window-list rect (top-left origin on the primary display) in AppKit's coordinates.
    static func appKit(_ rect: CGRect) -> CGRect {
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: rect.minX, y: primary - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The card itself inside its window.
    static func card(inWindow window: CGRect, kind: Kind = .volume) -> CGRect {
        CGRect(x: window.midX - kind.size.width / 2, y: window.maxY - kind.top - kind.size.height,
               width: kind.size.width, height: kind.size.height)
    }

    /// Where the card's window comes up, never seen yet in this situation: under the notch over a
    /// full-screen app, else at the desktop's place on the right.
    static func guess(fullscreenApps: Int, notch: CGRect, screen: CGRect) -> CGRect {
        let top = screen.maxY - notch.height - 1
        let x = fullscreenApps == 1 ? notch.midX - windowSize.width / 2 : screen.maxX - desktopRightMargin - windowSize.width
        return CGRect(x: x, y: top - windowSize.height, width: windowSize.width, height: windowSize.height)
    }

    /// The card lies under the notch (where the island itself covers it).
    static func isUnderNotch(_ window: CGRect, notch: CGRect) -> Bool {
        abs(window.midX - notch.midX) < 60
    }
}

/// Where macOS's volume card came up last, per situation (how many full-screen apps share the
/// Space, and the screen's size), relative to the screen.
@MainActor final class SystemVolumeCardMemory {
    static let key = "ni2.levels.volumeCard"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func situation(fullscreenApps: Int, screen: CGRect) -> String {
        "\(min(fullscreenApps, 2))@\(Int(screen.width))x\(Int(screen.height))"
    }

    func expected(fullscreenApps: Int, notch: CGRect, screen: CGRect) -> CGRect {
        let saved = defaults.dictionary(forKey: Self.key)?[Self.situation(fullscreenApps: fullscreenApps, screen: screen)] as? [Double]
        guard let saved, saved.count == 4 else {
            return SystemVolumeCard.guess(fullscreenApps: fullscreenApps, notch: notch, screen: screen)
        }
        return CGRect(x: screen.minX + saved[0], y: screen.minY + saved[1], width: saved[2], height: saved[3])
    }

    func learn(_ window: CGRect, fullscreenApps: Int, screen: CGRect) {
        var all = defaults.dictionary(forKey: Self.key) ?? [:]
        all[Self.situation(fullscreenApps: fullscreenApps, screen: screen)] =
            [window.minX - screen.minX, window.minY - screen.minY, window.width, window.height].map(Double.init)
        defaults.set(all, forKey: Self.key)
    }
}
