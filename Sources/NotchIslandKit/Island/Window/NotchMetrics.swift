import AppKit

/// Where the notch is, in global AppKit coordinates (bottom-left origin).
nonisolated struct NotchMetrics: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    /// Global AppKit coordinates.
    let screenFrame: CGRect
    /// Global AppKit coordinates (bottom-left origin), flush with the screen top.
    let notchRect: CGRect
    let isPhysical: Bool

    var notchSize: CGSize { notchRect.size }

    /// Width of the pill synthesised on screens without a camera housing.
    static let synthesizedWidth: CGFloat = 180
    /// Floor for the synthesised height, for menu bars thinner than a glyph row.
    static let minimumSynthesizedHeight: CGFloat = 24

    /// Derives the metrics from the raw values `NSScreen` reports. Pure, so the
    /// geometry is testable without a display.
    ///
    /// A physical notch is the top safe-area inset (height) and the gap between
    /// the two auxiliary top areas (width). Only widths of the auxiliary areas
    /// are used, which keeps this independent of the coordinate space AppKit
    /// reports them in.
    static func derive(
        displayID: CGDirectDisplayID,
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        menuBarThickness: CGFloat
    ) -> NotchMetrics {
        if safeAreaTop > 0, let left = auxiliaryTopLeftWidth, let right = auxiliaryTopRightWidth {
            let gap = screenFrame.width - left - right
            // A 1 pt gap would be rounding noise, not a camera housing.
            if gap > 1 {
                let rect = CGRect(
                    x: screenFrame.minX + left,
                    y: screenFrame.maxY - safeAreaTop,
                    width: gap,
                    height: safeAreaTop
                )
                return NotchMetrics(displayID: displayID, screenFrame: screenFrame, notchRect: rect, isPhysical: true)
            }
        }
        let height = max(menuBarThickness, minimumSynthesizedHeight)
        let rect = CGRect(
            x: screenFrame.midX - synthesizedWidth / 2,
            y: screenFrame.maxY - height,
            width: synthesizedWidth,
            height: height
        )
        return NotchMetrics(displayID: displayID, screenFrame: screenFrame, notchRect: rect, isPhysical: false)
    }
}

@MainActor enum ScreenLocator {
    static func metrics(for screen: NSScreen) -> NotchMetrics? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return NotchMetrics.derive(
            displayID: CGDirectDisplayID(number.uint32Value),
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarThickness: NSStatusBar.system.thickness
        )
    }

    /// The screen with a camera housing, else the menu-bar screen.
    ///
    /// The fallback is `NSScreen.screens.first` (the screen that owns the menu
    /// bar), not `NSScreen.main`, which follows the key window and would move
    /// the island between displays as focus changes.
    static func preferred() -> NotchMetrics? {
        let all = NSScreen.screens.compactMap(metrics(for:))
        return all.first(where: \.isPhysical) ?? all.first
    }
}
