import CoreGraphics

/// The user's size preference. Only the expanded panel scales: compact and
/// banner shapes must hug the physical notch whatever the preference says.
nonisolated enum IslandScale: String, Sendable, CaseIterable, Identifiable, Codable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var factor: CGFloat {
        switch self {
        case .compact: 0.9
        case .standard: 1.0
        case .large: 1.15
        }
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }
}

/// Island geometry as a pure function of the notch size and the scale.
///
/// This is the single source of truth for sizes: the views draw with it, the
/// window controller stages frames with it and the pointer monitor hit-tests
/// with it, so the three can never drift apart (legacy recomputed the same
/// geometry in four places).
nonisolated struct IslandLayout: Sendable, Equatable {
    let notch: CGSize
    let scale: IslandScale

    /// Glass extends this far above the window top, where it is clipped, so its
    /// top edge never shows a rim against the bezel.
    static let overdraw: CGFloat = 24
    /// Transparent slack around the island while animating: room for spring
    /// overshoot and the glass shadow.
    static let stageMargin: CGFloat = 28
    /// Slack kept after settling, so the glass shadow is not clipped.
    static let restingMargin: CGFloat = 10

    /// Banners need room for a symbol, a native slider and a value on one row.
    static let bannerMinimumWidth: CGFloat = 380
    /// The detail row a banner adds below the header band.
    static let bannerDetailHeight: CGFloat = 48
    /// Expanded panel before scaling: extra width beside the notch, its floor, and the page height.
    static let expandedExtraWidth: CGFloat = 380
    static let expandedMinimumWidth: CGFloat = 600
    static let expandedPageHeight: CGFloat = 160
    /// The assistant below its header band: the search field, a list of hits and actions, or an
    /// answer. As wide as the expanded panel, so from the header's Siri button it grows downward.
    static let assistantPageHeight: CGFloat = 280
    /// The assistant's field and rows (`AssistantView`), which are not scaled.
    static let assistantFieldHeight: CGFloat = 40
    static let assistantRowHeight: CGFloat = 32
    static let assistantRowSpacing: CGFloat = 2
    /// Above the field (`Metrics.Spacing.medium`), between it and the rows (the same), and below
    /// the last thing showing: a little less than the panel's bottom inset, so the field alone
    /// reads as one bar.
    static let assistantTopInset: CGFloat = 8
    static let assistantBottomInset: CGFloat = 12
    /// Only the field.
    static var assistantFieldPageHeight: CGFloat { assistantTopInset + assistantFieldHeight + assistantBottomInset }
    /// The field and the three suggestions under it.
    static var assistantSuggestionsPageHeight: CGFloat {
        let rows = CGFloat(AssistantCategory.allCases.count)
        return assistantFieldPageHeight + assistantTopInset + rows * assistantRowHeight + (rows - 1) * assistantRowSpacing
    }

    /// Width of each ear beside the notch in compact and banner: as narrow as the
    /// glyph allows — the compact shoulder (6), the glyph's outer inset (4), the
    /// glyph itself (notch height − 2 × 4) and the clearance from the notch (4).
    var ear: CGFloat { notch.height + 6 }

    /// Visible island size, without the overdraw.
    func size(for p: IslandPresentation) -> CGSize {
        switch p {
        case .idle:
            return notch
        case .compact:
            // Never taller than the notch: a taller pill reads as a window stuck to the screen.
            return CGSize(width: notch.width + 2 * ear, height: notch.height)
        case .banner:
            return CGSize(
                width: max(notch.width + 2 * ear, Self.bannerMinimumWidth),
                height: notch.height + Self.bannerDetailHeight
            )
        case .expanded:
            let f = scale.factor
            // Scaled lengths are rounded so glass edges stay on the pixel grid at every scale.
            return CGSize(
                width: (max(notch.width + Self.expandedExtraWidth, Self.expandedMinimumWidth) * f).rounded(),
                // The header band stays exactly the notch height; only the page scales.
                height: notch.height + (Self.expandedPageHeight * f).rounded()
            )
        case .assistant(let room):
            let f = scale.factor
            let list = (Self.assistantPageHeight * f).rounded()
            let page: CGFloat = switch room {
            case .field: Self.assistantFieldPageHeight
            case .suggestions: min(Self.assistantSuggestionsPageHeight, list)
            case .list: max(list, Self.assistantSuggestionsPageHeight)
            }
            return CGSize(
                width: (max(notch.width + Self.expandedExtraWidth, Self.expandedMinimumWidth) * f).rounded(),
                height: notch.height + page
            )
        }
    }

    func bottomRadius(for p: IslandPresentation) -> CGFloat {
        switch p {
        case .idle: min(8, notch.height / 2)
        case .compact: notch.height / 2
        case .banner: 24
        case .expanded, .assistant: 30 * scale.factor
        }
    }

    /// Radius of the concave fillet where the island meets the top bezel.
    func shoulderRadius(for p: IslandPresentation) -> CGFloat {
        switch p {
        case .idle: 0
        case .compact: 6
        case .banner: 8
        case .expanded, .assistant: 10
        }
    }

    /// Island rect in window-local AppKit coordinates (bottom-left origin) for a
    /// window of `stageSize`: centred horizontally, flush with the top.
    func islandRect(for p: IslandPresentation, inStage stageSize: CGSize) -> CGRect {
        let size = size(for: p)
        return CGRect(
            x: (stageSize.width - size.width) / 2,
            y: stageSize.height - size.height,
            width: size.width,
            height: size.height
        )
    }
}
