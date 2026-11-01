import AppKit
import SwiftUI

/// Live Activities ▸ New Track: the Now Playing pill dropping into the new track's title and back,
/// in its real sizes over the preview desktop, as large and for as long as the sliders under it
/// say (also while they are dragged). The title stands still for half a second, then glides
/// through, as in the notch. Drawn, as Now Playing's is: a photograph could not follow the sliders.
struct TrackTitlePicture: View {
    let size: Double
    let duration: Double

    @Environment(AppModel.self) private var model
    @Environment(\.settingsPictureScale) private var scale
    @Environment(\.settingsPictureRadius) private var radius
    @AppStorage(DesktopBackdropStyle.key) private var backdrop: DesktopBackdropStyle = DesktopBackdropStyle.defaultStyle

    private static let clock = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now
    static let color = ArtworkColor(red: 1, green: 0.38, blue: 0.3)
    static let title = "Island Lights — Liquid Glass Extended Mix"

    var body: some View {
        var layout = model.layout
        let _ = layout.trackTitleSize = CGFloat(size)
        let screen = layout.screen == .zero ? IslandLayout.fallbackScreen : layout.screen
        // The middle of the screen, on the scale of the activities' photographs.
        let k = IslandPhoto.activitySize.width * scale / DemoDirector.activityPictureSize.width
        let pill = IslandPresentation.compact(.nowPlaying)
        let pillSize = layout.size(for: pill)
        let split = NotchSplit(layout: layout, presentation: pill, outerInset: Metrics.Compact.inset,
                               clearance: Metrics.Compact.notchClearance)
        let glyph = max(0, layout.notch.height - 2 * Metrics.Compact.inset) * k
        let frame = CGSize(width: IslandPhoto.activitySize.width * scale, height: IslandPhoto.activitySize.height * scale)
        ZStack(alignment: .top) {
            DesktopBackdrop(style: backdrop, detail: .miniature)
                .frame(width: screen.width * k, height: screen.height * k)
            PreviewMenuBar(height: layout.notch.height * k, notchWidth: pillSize.width * k, darkText: backdrop.prefersDarkMenuBar,
                           backing: backdrop.menuBarBacking, date: Self.clock)
                .frame(width: frame.width)
            TrackTitleLoop(geometry: TrackTitleLoop.Geometry(layout: layout, scale: k), duration: duration)
                .frame(width: frame.width, height: frame.height)
            // The cover and the bars stay where the pill has them, as in the notch.
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: Metrics.Compact.artworkMinimumRadius * k, style: .continuous)
                    .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: glyph, height: glyph)
                Spacer(minLength: 0)
                EqualizerView(isAnimating: true, onBattery: true, size: CGSize(width: glyph, height: glyph),
                              barWidth: glyph * Metrics.Compact.equalizerBarShare, tint: Self.color)
                    .frame(width: glyph, height: glyph)
            }
            .padding(.horizontal, split.contentInset * k)
            .frame(width: pillSize.width * k, height: layout.notch.height * k)
        }
        .frame(width: frame.width, height: frame.height, alignment: .top)
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct TrackTitleLoop: NSViewRepresentable {
    /// The pill and the notice as the picture draws them (points of the picture).
    struct Geometry: Equatable {
        var pill: CGSize
        var pillRadius: CGFloat
        var pillShoulder: CGFloat
        var banner: CGSize
        var bannerRadius: CGFloat
        var bannerShoulder: CGFloat
        var notchHeight: CGFloat
        var titleRow: CGFloat
        var titleInset: CGFloat
        var titleFont: CGFloat
        /// The picture's points to the notch's.
        var scale: CGFloat

        init(layout: IslandLayout, scale k: CGFloat) {
            let pill = IslandPresentation.compact(.nowPlaying), banner = IslandPresentation.banner(.trackTitle)
            let pillSize = layout.size(for: pill), bannerSize = layout.size(for: banner)
            self.pill = CGSize(width: pillSize.width * k, height: pillSize.height * k)
            pillRadius = layout.bottomRadius(for: pill) * k
            pillShoulder = layout.shoulderRadius(for: pill) * k
            self.banner = CGSize(width: bannerSize.width * k, height: bannerSize.height * k)
            bannerRadius = layout.bottomRadius(for: banner) * k
            bannerShoulder = layout.shoulderRadius(for: banner) * k
            notchHeight = layout.notch.height * k
            // As `TrackTitleBanner` lays its row out.
            let row = layout.trackTitleRow
            titleRow = (row - (row * 0.12).rounded()) * k
            titleInset = IslandLayout.trackTitleSideInset * layout.trackTitleSize * k
            titleFont = layout.trackTitleFont * k
            scale = k
        }
    }

    let geometry: Geometry
    let duration: Double

    func makeNSView(context: Context) -> TrackTitleLoopView { TrackTitleLoopView() }

    func updateNSView(_ view: TrackTitleLoopView, context: Context) {
        view.geometry = geometry
        view.duration = duration
    }
}

/// The looping notice of `TrackTitlePicture`: a black island whose outline springs from the pill to
/// the notice and back, the title fading in with it and gliding through as the notice's does.
/// Each step is added just before it starts (`GrowthLoopView`'s way): between them nothing is
/// attached and the window server draws no frame.
final class TrackTitleLoopView: NSView {
    private let island = CAShapeLayer()
    private let title = MarqueeTitleView()
    static let animationKey = "trackTitle"
    static let lead: CFTimeInterval = 0.05
    /// The pill's spring open and shut, the title's fade, and the rest between two loops.
    static let openLength = 0.45
    static let closeLength = 0.4
    static let fadeLength = 0.25
    static let rest = 1.4

    var geometry: TrackTitleLoop.Geometry? {
        didSet {
            guard geometry != oldValue else { return }
            needsLayout = true
            restart()
        }
    }

    var duration: Double = 0 {
        didSet { if duration != oldValue { restart() } }
    }

    private var cycleStart: CFTimeInterval = 0
    private var nextStep = 0
    private var timer: (any DispatchSourceTimer)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        island.fillColor = NSColor.black.cgColor
        layer?.addSublayer(island)
        title.startsByItself = false
        title.alphaValue = 0
        addSubview(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { timer?.cancel() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    override func viewDidHide() {
        super.viewDidHide()
        restart()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        restart()
    }

    override func layout() {
        super.layout()
        guard let geometry else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.frame = bounds
        title.frame = CGRect(x: ((bounds.width - geometry.banner.width) / 2 + geometry.titleInset).rounded(),
                             y: geometry.notchHeight,
                             width: max(geometry.banner.width - 2 * geometry.titleInset, 0), height: geometry.titleRow)
        CATransaction.commit()
        title.update(MarqueeTitleView.Content(text: TrackTitlePicture.title, fontSize: geometry.titleFont,
                                              color: NSColor(Color(TrackTitlePicture.color))),
                     timing: timing(geometry))
    }

    private func timing(_ geometry: TrackTitleLoop.Geometry) -> MarqueeTitleView.Timing {
        // The notch's speed, in the picture's points.
        MarqueeTitleView.Timing(hold: 0.5, speed: 32 * geometry.scale, within: max(duration - Self.openLength * 0.6, 0.6))
    }

    private func path(_ size: CGSize, radius: CGFloat, shoulder: CGFloat) -> CGPath {
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        return IslandShape(bottomRadius: radius, shoulderRadius: shoulder).path(in: rect).cgPath
    }

    private var closed: CGPath? { geometry.map { path($0.pill, radius: $0.pillRadius, shoulder: $0.pillShoulder) } }
    private var open: CGPath? { geometry.map { path($0.banner, radius: $0.bannerRadius, shoulder: $0.bannerShoulder) } }

    /// Open, the title's time, close, rest.
    private var closeAt: Double { duration }
    private var cycle: Double { duration + Self.closeLength + Self.rest }

    private func restart() {
        timer?.cancel()
        timer = nil
        island.removeAnimation(forKey: Self.animationKey)
        title.layer?.removeAnimation(forKey: Self.animationKey)
        title.stop()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.path = closed
        title.alphaValue = 0
        CATransaction.commit()
        guard window != nil, geometry != nil, duration > 0, !isHiddenOrHasHiddenAncestor else { return }
        cycleStart = CACurrentMediaTime() + Self.lead
        nextStep = 0
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.addNextStep() }
        }
        self.timer = timer
        timer.schedule(deadline: .now())
        timer.resume()
    }

    private func addNextStep() {
        guard window != nil, let closed, let open, duration > 0, !isHiddenOrHasHiddenAncestor else { return }
        let opens = nextStep % 2 == 0
        var begin = cycleStart + Double(nextStep / 2) * cycle + (opens ? 0 : closeAt)
        let earliest = CACurrentMediaTime() + 0.01
        if begin < earliest {
            cycleStart += earliest - begin
            begin = earliest
        }
        let spring = CASpringAnimation(perceptualDuration: opens ? Self.openLength : Self.closeLength, bounce: opens ? 0.15 : 0)
        spring.keyPath = "path"
        spring.fromValue = opens ? closed : open
        spring.toValue = opens ? open : closed
        spring.beginTime = begin
        spring.duration = min(spring.settlingDuration, opens ? closeAt : cycle - closeAt)
        spring.fillMode = .backwards
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opens ? 0 : 1
        fade.toValue = opens ? 1 : 0
        fade.beginTime = begin + (opens ? 0.1 : 0)
        fade.duration = opens ? Self.fadeLength : Self.fadeLength * 0.6
        fade.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.path = opens ? open : closed
        title.alphaValue = opens ? 1 : 0
        // Scrolled out of sight, the loop keeps its time without a frame (as `GrowthLoopView`).
        if !visibleRect.isEmpty {
            island.add(spring, forKey: Self.animationKey)
            title.layer?.add(fade, forKey: Self.animationKey)
            if opens { title.start(at: begin + 0.1 + 0.5) }
        }
        CATransaction.commit()

        nextStep += 1
        let following = cycleStart + Double(nextStep / 2) * cycle + (nextStep % 2 == 0 ? 0 : closeAt)
        let wait = max(0, following - Self.lead - CACurrentMediaTime())
        timer?.schedule(deadline: .now() + wait, leeway: .milliseconds(5))
    }
}
