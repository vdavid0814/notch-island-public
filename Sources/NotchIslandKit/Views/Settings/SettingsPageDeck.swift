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

    override func layout() {
        super.layout()
        for page in pages.values where page.host.frame != bounds { page.host.frame = bounds }
    }

    /// Shows `pane`, at its top, as a new page was: the page it takes the place of fades out as
    /// this one fades in, rising a little into place. Both are layers the render server moves
    /// (opacity and a transform): nothing is laid out or drawn again for it, so every frame of it is
    /// cheap. With Reduce Motion, or the first page of all, it is simply there.
    func show(_ pane: IslandSettingsPane) {
        guard pane != shown || pages[pane]?.visit.isShown == false else { return }
        let old = shown.flatMap { $0 != pane ? pages[$0] : nil }
        let leaving = shown
        old?.visit.isShown = false
        let page = pages[pane] ?? make(pane)
        page.host.isHidden = false
        page.host.scrollToTop()
        page.visit.count += 1
        page.visit.isShown = true
        shown = pane
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
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        // The deck is flipped: its layers' y grows downwards.
        rise.fromValue = Self.rise
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
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Not if it was shown again meanwhile.
                if self.shown != leaving { old.host.isHidden = true }
                outgoing.removeAnimation(forKey: Self.transitionKey)
            }
        }
        outgoing.add(fadeOut, forKey: Self.transitionKey)
        CATransaction.commit()
    }

    private static let transitionKey = "settingsPage"
    private static let transitionDuration: CFTimeInterval = 0.26
    /// How far below its place a page starts.
    private static let rise: CGFloat = 14

    /// Settings has closed: the shown page stands still too.
    func closed() {
        guard let shown, let page = pages[shown] else { return }
        page.visit.isShown = false
    }

    /// Settings opens again: the page it shows starts afresh.
    func reopen() {
        guard let shown, let page = pages[shown], !page.visit.isShown else { return }
        page.host.scrollToTop()
        page.visit.count += 1
        page.visit.isShown = true
    }

    func isBuilt(_ pane: IslandSettingsPane) -> Bool { pages[pane] != nil }

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

extension NSView {
    /// The first scroll view inside, back at its top.
    func scrollToTop() {
        guard let scroll = firstSubview(of: NSScrollView.self), let document = scroll.documentView else { return }
        let top = document.isFlipped ? 0 : max(0, document.frame.height - scroll.contentView.bounds.height)
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

