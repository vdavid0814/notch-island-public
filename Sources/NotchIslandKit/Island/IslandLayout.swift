import CoreGraphics

/// The user's size preference. Only the expanded panel scales: compact and
/// banner shapes must hug the physical notch whatever the preference says.
nonisolated enum IslandScale: String, Sendable, CaseIterable, Identifiable, Codable {
    case extraSmall
    case small
    case compact
    case standard
    case large

    var id: String { rawValue }

    var factor: CGFloat {
        switch self {
        case .extraSmall: 0.72
        case .small: 0.8
        case .compact: 0.9
        case .standard: 1.0
        case .large: 1.15
        }
    }

    var title: String {
        switch self {
        // Named from the middle out (the user's wish): the stored names stay, so saved choices keep
        // their size — `compact` is shown as Standard, `standard` as Large, `large` as Extra Large.
        case .extraSmall: "Extra Small"
        case .small: "Small"
        case .compact: "Standard"
        case .standard: "Large"
        case .large: "Extra Large"
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
    /// The screen the island is on (zero when unknown): Settings takes most of it.
    var screen: CGSize = .zero
    /// Siri's window proportions (Settings ▸ Siri ▸ Window).
    var siri = SiriLayout()

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
    /// The AirPods card (see `size(for: .banner(.airPods))`).
    static let airPodsBannerWidth: CGFloat = 400
    static let airPodsDetailHeight: CGFloat = 112
    /// Each ear of the minimal level pill: the symbol on one side, a small slider on the other.
    static let levelPillEar: CGFloat = 92
    /// The detail row a banner adds below the header band.
    static let bannerDetailHeight: CGFloat = 48
    /// Expanded panel before scaling: extra width beside the notch, its floor, and the page height.
    static let expandedExtraWidth: CGFloat = 380
    static let expandedMinimumWidth: CGFloat = 600
    static let expandedPageHeight: CGFloat = 160
    /// The assistant below its header band: the search field, a list of hits and actions, or an
    /// answer. As wide as the expanded panel, so from the header's Siri button it grows downward.
    static let assistantPageHeight: CGFloat = 280
    /// Settings in the island: most of the screen, grown out of the notch (a full-screen feel
    /// without leaving it). Kept this far from the screen's sides and bottom, and no larger than
    /// the maximum on big displays.
    static let settingsSideMargin: CGFloat = 50
    static let settingsBottomMargin: CGFloat = 64
    static let settingsMaximum = CGSize(width: 1180, height: 740)
    static let settingsMinimum = CGSize(width: 820, height: 520)
    /// Standing in for the screen before one is known (a 14-inch MacBook's default resolution).
    static let fallbackScreen = CGSize(width: 1512, height: 982)
    /// The app gallery (Applications ⌘1): wider and taller than the list, for nine columns of apps
    /// and four rows of them.
    static let assistantGalleryWidth: CGFloat = 820
    static let assistantGalleryPageHeight: CGFloat = 440
    /// One app in the gallery (`GalleryCell`: 6 + 48-pt icon + 4 + caption line + 6) and the space
    /// between rows: the gallery is exactly the user's number of rows tall, never a cut-off row.
    static let galleryCellHeight: CGFloat = 77
    static let galleryRowSpacing: CGFloat = 4

    /// The gallery page for `rows` rows: the field above them, the insets around.
    static func galleryPageHeight(rows: Int) -> CGFloat {
        let rows = CGFloat(max(1, rows))
        return assistantTopInset * 2 + assistantFieldHeight + Metrics.Expanded.pageBottomInset
            + rows * galleryCellHeight + (rows - 1) * galleryRowSpacing
    }
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
    static var assistantSuggestionsPageHeight: CGFloat { assistantRowsPageHeight(3) }

    /// The field and `count` rows under it.
    static func assistantRowsPageHeight(_ count: Int) -> CGFloat {
        let rows = CGFloat(max(count, 1))
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
        case .banner(.airPods):
            // Large enough to lie over macOS's own AirPods card (about 300 × 60 pt under the
            // notch, in a 352 × 148 window with its shadow), which the island covers.
            return CGSize(width: max(notch.width + 2 * ear, Self.airPodsBannerWidth),
                          height: notch.height + Self.airPodsDetailHeight)
        case .banner(.levelPill):
            // Pill height; the trailing ear holds a small slider, so both ears are that wide.
            return CGSize(width: notch.width + 2 * Self.levelPillEar, height: notch.height)
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
        case .settings:
            let screen = screen == .zero ? Self.fallbackScreen : screen
            let width = min(max(screen.width - 2 * Self.settingsSideMargin, Self.settingsMinimum.width), Self.settingsMaximum.width)
            let page = min(max(screen.height - notch.height - Self.settingsBottomMargin, Self.settingsMinimum.height),
                           Self.settingsMaximum.height)
            return CGSize(width: width.rounded(), height: notch.height + page.rounded())
        case .assistant(let room):
            let f = scale.factor
            // The user's rows and columns scale the defaults (7 list rows, a 9 × 4 gallery).
            let list = (Self.assistantPageHeight * f * CGFloat(siri.listRows) / 7).rounded()
            let page: CGFloat = switch room {
            case .field: Self.assistantFieldPageHeight
            case .rows(let count): min(Self.assistantRowsPageHeight(count), max(list, Self.assistantSuggestionsPageHeight))
            case .list: max(list, Self.assistantSuggestionsPageHeight)
            case .gallery: Self.galleryPageHeight(rows: siri.galleryRows)
            }
            let panel = (max(notch.width + Self.expandedExtraWidth, Self.expandedMinimumWidth) * f * siri.widthFactor).rounded()
            let gallery = (Self.assistantGalleryWidth * f * CGFloat(siri.galleryColumns) / 9).rounded()
            return CGSize(
                width: room == .gallery ? max(panel, gallery) : panel,
                height: notch.height + page
            )
        }
    }

    func bottomRadius(for p: IslandPresentation) -> CGFloat {
        switch p {
        case .idle: min(8, notch.height / 2)
        case .compact, .banner(.levelPill): notch.height / 2
        case .banner: 24
        case .expanded, .assistant, .settings: 30 * scale.factor
        }
    }

    /// Radius of the concave fillet where the island meets the top bezel.
    func shoulderRadius(for p: IslandPresentation) -> CGFloat {
        switch p {
        case .idle: 0
        case .compact, .banner(.levelPill): 6
        case .banner: 8
        case .expanded, .assistant, .settings: 10
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
