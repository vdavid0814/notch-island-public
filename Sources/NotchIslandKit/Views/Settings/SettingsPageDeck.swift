import AppKit
import SwiftUI

/// Whether a kept Settings page is the one shown, and how many times it has been shown: what the
/// page's views used `onAppear`/`onDisappear` for when every visit built the page anew.
@Observable final class SettingsPageVisit {
    fileprivate(set) var isShown = false
    /// Counts up each time the page is shown again.
    fileprivate(set) var count = 0
}

extension EnvironmentValues {
    @Entry var settingsPageVisit: SettingsPageVisit?
}

extension View {
    /// `shown` each time the kept Settings page around this view is shown (also the first time),
    /// `hidden` when another page takes its place or Settings closes.
    func onSettingsPageVisit(shown: @escaping () -> Void, hidden: @escaping () -> Void = {}) -> some View {
        modifier(SettingsPageVisitWatch(shown: shown, hidden: hidden))
    }
}

private struct SettingsPageVisitWatch: ViewModifier {
    let shown: () -> Void
    let hidden: () -> Void
    @Environment(\.settingsPageVisit) private var visit

    func body(content: Content) -> some View {
        content
            .onChange(of: visit?.isShown ?? true) { _, isShown in isShown ? shown() : hidden() }
    }
}

/// Settings' page area: the selected page, each page in a view graph of its own that is built
/// once and kept, hidden while another is shown.
///
/// Built at every visit (`.id(pane)`), a page was laid out from nothing each time — the forms, the
/// native controls, the widget gallery's live previews: that layout was most of Settings' cost
/// (~1.2 s of main thread on the performance cores for General and Widgets, measured). Kept,
/// switching pages hides one view and shows another. An AppKit view of `SettingsSurfaceView`'s,
/// not a representable in the sidebar's graph: SwiftUI took a representable out of the window
/// whenever Settings closed, and every page was laid out again when it came back.
final class SettingsPageDeckView: NSView {
    private let model: AppModel
    private var pages: [IslandSettingsPane: (host: DeferringHostingView<AnyView>, visit: SettingsPageVisit)] = [:]
    private(set) var shown: IslandSettingsPane?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// The room's lower corners: the sidebar's (its outer one concentric with the island's). What a
    /// page has at the room's foot — Widgets' cards, its scroller — is cut round them and never
    /// stands out of the island's own corner. A layer's own rounded corners, which the window
    /// server cuts as cheaply as the window's.
    var footRadius: CGFloat = 0 {
        didSet { if footRadius != oldValue { roundFoot() } }
    }

    override func layout() {
        super.layout()
        for page in pages.values where page.host.frame != bounds { page.host.frame = bounds }
        roundFoot()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        roundFoot()
    }

    /// Set again whenever the room is laid out or shown: made before the view is in a window, the
    /// layer does not yet know which way it runs.
    private func roundFoot() {
        guard let layer else { return }
        // The lower corners, whichever way the view's layer runs.
        let corners: CACornerMask = layer.isGeometryFlipped || layer.contentsAreFlipped()
            ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        guard layer.cornerRadius != footRadius || layer.maskedCorners != corners || !layer.masksToBounds else { return }
        // The view's own switch: AppKit sets the layer's from it.
        clipsToBounds = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = footRadius
        layer.cornerCurve = .continuous
        layer.maskedCorners = corners
        layer.masksToBounds = true
        CATransaction.commit()
    }

    /// Shows `pane`, at its top, as a new page was: the page it takes the place of fades out as
    /// this one fades in, rising a little into place. Both are layers the render server moves
    /// (opacity and a transform): nothing is laid out or drawn again for it, so every frame of it is
    /// cheap. With Reduce Motion, or the first page of all, it is simply there.
    func show(_ pane: IslandSettingsPane) {
        roundFoot()
        releases.removeValue(forKey: pane)?.invalidate()
        guard pane != shown || pages[pane]?.visit.isShown == false else { return }
        let old = shown.flatMap { $0 != pane ? pages[$0] : nil }
        let leaving = shown
        old?.visit.isShown = false
        if old != nil, let leaving { releaseLater(leaving) }
        let page = pages[pane] ?? make(pane)
        page.host.isHidden = false
        // Its live pictures, out of the window since Settings last closed, are put back now
        // (`DeferringHostingView.pausesWithSettings`).
        if SettingsPresence.shared.isShown { NotificationCenter.default.post(name: SettingsPresence.didChange, object: nil) }
        page.host.scrollToTop()
        page.visit.count += 1
        page.visit.isShown = true
        shown = pane
        let step = model.settingsHistory.takeStep()
        guard let old, let leaving, window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let incoming = page.host.layer, let outgoing = old.host.layer else {
            old?.host.isHidden = true
            return
        }
        incoming.removeAnimation(forKey: Self.transitionKey)
        outgoing.removeAnimation(forKey: Self.transitionKey)
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        // A swipe's step slides sideways, as Siri's suggestions do: forward the page comes in from
        // the right and the old one leaves to the left; back the other way. Otherwise it rises.
        let slide = step.map { $0 == .forward ? bounds.width * Self.slide : -bounds.width * Self.slide }
        let rise = CABasicAnimation(keyPath: slide == nil ? "transform.translation.y" : "transform.translation.x")
        // The deck is flipped: its layers' y grows downwards.
        rise.fromValue = slide ?? Self.rise
        rise.toValue = 0
        let entrance = CAAnimationGroup()
        entrance.animations = [fadeIn, rise]
        entrance.duration = Self.transitionDuration
        entrance.timingFunction = timing
        incoming.add(entrance, forKey: Self.transitionKey)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = Self.transitionDuration * 0.55
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // Stays as it ends until it is hidden (the model layer is still opaque).
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        let exit: CAAnimation
        if let slide {
            let away = CABasicAnimation(keyPath: "transform.translation.x")
            away.fromValue = 0
            away.toValue = -slide
            let group = CAAnimationGroup()
            group.animations = [fadeOut, away]
            group.duration = Self.transitionDuration
            group.timingFunction = timing
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            fadeOut.duration = Self.transitionDuration * 0.7
            exit = group
        } else {
            exit = fadeOut
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Not if it was shown again meanwhile.
                if self.shown != leaving { old.host.isHidden = true }
                outgoing.removeAnimation(forKey: Self.transitionKey)
            }
        }
        outgoing.add(exit, forKey: Self.transitionKey)
        CATransaction.commit()
    }

    private static let transitionKey = "settingsPage"
    private static let transitionDuration: CFTimeInterval = 0.26
    /// How far below its place a page starts.
    private static let rise: CGFloat = 14
    /// How far beside its place a page a swipe brings starts, as a share of the room's width.
    private static let slide: CGFloat = 0.3

    /// Settings has closed: the shown page stands still too.
    func closed() {
        guard let shown, let page = pages[shown] else { return }
        page.visit.isShown = false
        releaseLater(shown)
    }

    /// Settings opens again: the page it shows starts afresh.
    func reopen() {
        guard let shown, let page = pages[shown], !page.visit.isShown else { return }
        releases.removeValue(forKey: shown)?.invalidate()
        page.host.scrollToTop()
        page.visit.count += 1
        page.visit.isShown = true
    }

    /// The shown page's own scroll view, where its scroller stands out in the gap beside the room
    /// (`SettingsEdgeScroller`): every page reaches the room's edges.
    var edgeScroll: NSScrollView? {
        shown.flatMap { pages[$0]?.host.firstSubview(of: NSScrollView.self) }
    }

    func isBuilt(_ pane: IslandSettingsPane) -> Bool { pages[pane] != nil }

    /// How long a page that is not kept (`IslandSettingsPane.isKept`) stays after the user has left
    /// it, for another page or by closing Settings: back within it, it is there at once (asked
    /// for, October 30). macOS short of memory gives all of Settings up anyway (`discard`).
    static let unkeptPagesLinger: TimeInterval = 60
    /// The pages waiting to be let go.
    private var releases: [IslandSettingsPane: Timer] = [:]

    /// `pane` let go `unkeptPagesLinger` from now, unless it is shown again meanwhile; in a turn on
    /// the efficiency cores, as Settings' ordering out is.
    private func releaseLater(_ pane: IslandSettingsPane) {
        guard !pane.isKept else { return }
        releases[pane]?.invalidate()
        let timer = Timer(timeInterval: Self.unkeptPagesLinger, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releases[pane] = nil
                MainThrift.lowPowerTurn(unattended: true) { [weak self] in
                    guard let self, self.releases[pane] == nil else { return }
                    self.release(pane)
                }
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        releases[pane] = timer
    }

    /// `pane` let go, unless it is the one on the screen; built again when the user goes to it.
    private func release(_ pane: IslandSettingsPane) {
        guard let page = pages[pane], !page.visit.isShown else { return }
        let before = AliasTrim.footprint()
        pages[pane] = nil
        page.host.removeFromSuperview()
        if shown == pane { shown = nil }
        // The last page but the kept ones: what they share, kept for them, goes too. The desktop
        // pictures alone are two blocks of ~9 MB each (seen with `heap`).
        if pages.keys.allSatisfy(\.isKept) {
            WallpaperLibrary.shared.release()
            IslandPhoto.forget()
        }
        AliasTrim.soon()
        // Told a moment later, the page's views and what was given back then known: a page
        // something still holds would show here as a view not gone.
        Task { @MainActor [weak host = page.host] in
            try? await Task.sleep(for: .seconds(6), tolerance: .seconds(1))
            Log.window.notice("settings page \(pane.rawValue, privacy: .public) let go: \(before >> 20, privacy: .public) → \(AliasTrim.footprint() >> 20, privacy: .public) MB, view gone \(host == nil, privacy: .public)")
        }
    }

    /// `pane` built and laid out unseen at the deck's size (`SettingsSurfaceView.prepareNextPage`).
    func prepare(_ pane: IslandSettingsPane) {
        guard pages[pane] == nil else { return }
        let page = make(pane)
        page.host.frame = bounds
        page.host.forcesLayout = true
        page.host.layoutSubtreeIfNeeded()
        page.host.forcesLayout = false
    }

    @discardableResult
    private func make(_ pane: IslandSettingsPane) -> (host: DeferringHostingView<AnyView>, visit: SettingsPageVisit) {
        let visit = SettingsPageVisit()
        let host = DeferringHostingView(rootView: AnyView(SettingsPageRoot(pane: pane, visit: visit)
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true)
            .environment(\.settingsPageVisit, visit)))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.isHidden = true
        host.frame = bounds
        addSubview(host)
        pages[pane] = (host, visit)
        return (host, visit)
    }
}

/// A kept page. (Its pictures stand still while Settings is closed through `SettingsPresence`; an
/// `isIslandPanelHidden` written here at each change of page went through every view of both
/// pages and made a switch a 60–80 ms turn of the main thread, measured.)
private struct SettingsPageRoot: View {
    let pane: IslandSettingsPane
    let visit: SettingsPageVisit

    var body: some View {
        SettingsDetail(pane: pane)
    }
}

extension NSScrollView {
    /// Where the clip view's origin can be, the insets taken in: a page's title lies over the top
    /// of its scroll view, so at the page's top the origin is above the document's.
    var originRange: ClosedRange<CGFloat> {
        let height = documentView?.frame.height ?? 0
        let flipped = documentView?.isFlipped ?? true
        let lowest = -(flipped ? contentInsets.top : contentInsets.bottom)
        let highest = height - contentView.bounds.height + (flipped ? contentInsets.bottom : contentInsets.top)
        return lowest...max(lowest, highest)
    }
}

extension NSView {
    /// The first scroll view inside, back at its top.
    func scrollToTop() {
        guard let scroll = firstSubview(of: NSScrollView.self), let document = scroll.documentView else { return }
        let top = document.isFlipped ? scroll.originRange.lowerBound : scroll.originRange.upperBound
        guard scroll.contentView.bounds.origin.y != top else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        for view in subviews {
            if let match = view as? T { return match }
            if let match = view.firstSubview(of: type) { return match }
        }
        return nil
    }
}

