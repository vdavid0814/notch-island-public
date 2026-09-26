import CoreGraphics
import SwiftUI

/// Spacing, radii and size tokens for everything drawn inside the island.
///
/// There are deliberately no colours here: every foreground is semantic (`.primary`, `.secondary`,
/// `.tint`, and `.green` / `.red` / `.orange` only where they carry meaning), so dark/light,
/// Increase Contrast and the accent colour are handled by the system.
///
/// Island sizes and radii are not tokens either — they come from `IslandLayout`, the single source
/// of truth for geometry. These tokens only place content inside whatever size it gives.
nonisolated enum Metrics {
    /// 2-pt based spacing scale.
    nonisolated enum Spacing {
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 16
        static let xxLarge: CGFloat = 20
    }

    /// Clearance between content and the edge of the physical notch gap, so nothing looks like it
    /// is touching (or disappearing under) the camera housing.
    static let notchClearance: CGFloat = 6

    /// Alpha of the idle hover target. The window server routes the pointer by the alpha of the
    /// window's backing store, which is 8 bits per channel: anything below 1/255 quantises to zero
    /// and the pointer passes straight through the notch. 0.004 is the smallest round value that
    /// survives; the idle island sits in the notch cut-out, which has no pixels, so it is never seen.
    static let hitTargetOpacity: Double = 0.004

    /// The pill that hugs the notch. Its height is the notch height, so everything is sized to sit
    /// concentrically in the pill's round ends.
    nonisolated enum Compact {
        /// Inset of the ear content from the pill's top, bottom and round end. Equal on all sides so
        /// the artwork sits concentric with the end cap.
        static let inset: CGFloat = 4
        /// Tighter than the global clearance: the pill is short, and the ears are narrow.
        static let notchClearance: CGFloat = 4
        static let equalizerSize = CGSize(width: 16, height: 12)
        /// The pill's equalizer fills the cover's square (`NowPlayingCompact`); each of its five
        /// bars is this share of the square's side wide, the gaps between them a little narrower.
        static let equalizerBarShare: CGFloat = 0.12
        /// How far the trailing time may shrink before it truncates. The ear is one glyph wide, so
        /// "4:59" already shrinks a little; "1:02:03" needs ~0.5 at the standard notch.
        static let timeMinimumScale: CGFloat = 0.5
        /// Corner radius floor for the compact artwork, where the concentric radius would vanish
        /// against the flat top edge.
        static let artworkMinimumRadius: CGFloat = 5
    }

    /// The transient notice that drops below the notch.
    nonisolated enum Banner {
        /// Inset of the header ears and the detail row from the body edge. Large enough to clear the
        /// 24-pt continuous bottom corners.
        static let horizontalInset: CGFloat = 20
        /// Room kept under the detail row.
        static let rowBottomInset: CGFloat = 10
        static let rowSpacing: CGFloat = 10
    }

    /// The full panel. Values multiplied by the island scale factor where they size content.
    nonisolated enum Expanded {
        /// From the body's edge to the header ears and the page: the same as `pageBottomInset`, so a
        /// widget sits as far from the island's side as from its bottom.
        static let horizontalInset: CGFloat = pageBottomInset
        /// Gap between the header band and the page. Smaller than the bottom inset: the header's
        /// controls already leave air under themselves inside the band.
        static let pageTopInset: CGFloat = 8
        /// Room kept above the bottom edge: half the old 16 pt, still clear of the 30-pt continuous
        /// corners for the widgets' own rounded corners.
        static let pageBottomInset: CGFloat = 8
        static let columnSpacing: CGFloat = 20
        static let sideColumnWidth: CGFloat = 170
        /// Sized so artwork, the text/control stack beside it and the side column share one height
        /// that nearly fills the page: nothing floats in a gap.
        static let artworkSize: CGFloat = 104
        static let artworkMinimumRadius: CGFloat = 12
        static let bigTimeFontSize: CGFloat = 44
        static let headerSliderWidth: CGFloat = 90
        static let fileTileWidth: CGFloat = 76
        static let thumbnailSize: CGFloat = 52
        static let thumbnailRadius: CGFloat = 6
        /// The timer page's control column: the length slider plus Start, and the preset chips
        /// above it spread to the same width.
        static let timerControlsWidth: CGFloat = 260
    }

    /// Fixed heights for the island's glass controls, like the CAD app's `CadControl`: every
    /// button, chip and segmented switcher picks its height from here by control size, so two
    /// controls in one row can never differ by a few points.
    nonisolated enum Control {
        static func height(_ size: ControlSize) -> CGFloat {
            switch size {
            case .mini: 20
            case .small: 24
            case .large: 34
            case .extraLarge: 40
            default: 28
            }
        }

        /// Label padding either side of a capsule's text (CAD: 11 pt at 30 pt).
        static func horizontalPadding(_ size: ControlSize) -> CGFloat {
            (height(size) * 0.36).rounded()
        }

        /// Text style of a control's label. Text styles rather than point sizes, so labels track the
        /// system's type ramp; each one fits its fixed height with room to spare.
        static func font(_ size: ControlSize) -> Font {
            switch size {
            case .mini: .caption2.weight(.semibold)
            case .small: .subheadline.weight(.semibold)
            case .large: .body.weight(.semibold)
            case .extraLarge: .title3.weight(.semibold)
            default: .callout.weight(.semibold)
            }
        }

        /// The largest control size that leaves at least 4 pt above and below inside a band of the
        /// notch's height (header ears of the expanded island).
        static func size(fittingBand bandHeight: CGFloat) -> ControlSize {
            bandHeight >= height(.small) + 8 ? .small : .mini
        }

        /// One step up: the primary control of a row (play/pause) stands out by size as well as tint.
        static func larger(_ size: ControlSize) -> ControlSize {
            switch size {
            case .mini: .small
            case .small: .regular
            case .regular: .large
            default: .extraLarge
            }
        }

        /// One step down, never below `.small`: secondary controls beside a primary area.
        static func smaller(_ size: ControlSize) -> ControlSize {
            switch size {
            case .extraLarge: .large
            case .large: .regular
            default: .small
            }
        }
    }

    /// Width of each ear either side of the notch gap, inside the island's shoulders.
    ///
    /// - Parameters:
    ///   - islandWidth: full island frame width (`IslandLayout.size(for:).width`).
    ///   - notchWidth: physical notch width.
    ///   - shoulder: `IslandLayout.shoulderRadius(for:)`; the shoulders are inside the frame.
    static func earWidth(islandWidth: CGFloat, notchWidth: CGFloat, shoulder: CGFloat) -> CGFloat {
        max(0, (islandWidth - 2 * max(shoulder, 0) - notchWidth) / 2)
    }

    /// Control size for the expanded panel at a given island scale. The panel re-lays out at larger
    /// sizes rather than scaling as a bitmap: a `scaleEffect` would resample the AppKit-backed
    /// sliders and blur them.
    static func controlSize(forScale factor: CGFloat) -> ControlSize {
        switch factor {
        case ..<0.76: .mini
        case ..<0.95: .small
        case 1.1...: .large
        default: .regular
        }
    }
}
