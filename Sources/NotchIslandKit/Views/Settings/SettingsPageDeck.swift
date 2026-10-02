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

    /// Shows `pane`, at its top, as a new page was.
    func show(_ pane: IslandSettingsPane) {
        guard pane != shown || pages[pane]?.visit.isShown == false else { return }
        if let shown, shown != pane, let old = pages[shown] {
            old.host.isHidden = true
            old.visit.isShown = false
        }
        let page = pages[pane] ?? make(pane)
        page.host.isHidden = false
        page.host.scrollToTop()
        page.visit.count += 1
        page.visit.isShown = true
        shown = pane
    }

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

