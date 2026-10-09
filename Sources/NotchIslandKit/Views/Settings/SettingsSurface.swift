import AppKit
import SwiftUI

/// Settings' page area: the sidebar and the pages, each page in a view graph of its own, and — on
/// demand — one widget's Customize over them, in a graph of its own (`WidgetCustomizeView`).
struct SettingsSurface: NSViewRepresentable {
    let placement: SettingsPlacement
    let model: AppModel
    /// Settings has started to close: the surface fades out with the island's content.
    var isClosing = false

    func makeNSView(context: Context) -> SettingsSurfaceAnchor {
        let anchor = SettingsSurfaceAnchor(model: model, placement: placement)
        return anchor
    }

    func updateNSView(_ anchor: SettingsSurfaceAnchor, context: Context) {
        anchor.placement = placement
        anchor.surface?.update(placement: placement)
        if isClosing { anchor.close() }
    }

    static func dismantleNSView(_ anchor: SettingsSurfaceAnchor, coordinator: ()) {
        anchor.dismantle()
    }
}

/// Where Settings' surface is shown, in the island's SwiftUI: an empty view whose place on the
/// screen Settings' own window (`SettingsWindow`, with the kept surface in it) takes.
final class SettingsSurfaceAnchor: NSView {
    private let model: AppModel
    var placement: SettingsPlacement
    private(set) var surface: SettingsSurfaceView?
    private var isClosing = false

    init(model: AppModel, placement: SettingsPlacement) {
        self.model = model
        self.placement = placement
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
        if window != nil, surface == nil, !isClosing {
            Log.window.notice("settings anchor in its window without a size yet; waiting for its layout")
        }
    }

    /// Settings' window over this view, once it is in a window with a size. Put into the window
    /// before SwiftUI had sized it, the view was given up on, and Settings grew empty.
    private func attach() {
        guard window != nil, surface == nil, !isClosing, let frame = screenFrame else { return }
        let settings = SettingsWindow.reused(model: model, placement: placement, frame: frame)
        surface = settings.surface
        settings.show()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        place()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        place()
    }

    override func layout() {
        super.layout()
        place()
    }

    /// This view's place on the screen.
    private var screenFrame: CGRect? {
        guard let window else { return nil }
        let frame = window.convertToScreen(convert(bounds, to: nil)).integral
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }

    /// Settings' window over this view's place.
    func place() {
        guard surface != nil else { return attach() }
        guard !isClosing, let frame = screenFrame else { return }
        SettingsWindow.current?.place(frame)
    }

    /// Settings starts to close: gone from sight with the island's content.
    func close() {
        guard !isClosing else { return }
        isClosing = true
        if surface != nil { SettingsWindow.current?.hide(fade: model.island.presentation.isIdle ? 0.1 : 0.18) }
    }

    func dismantle() {
        isClosing = true
        guard surface != nil else { return }
        SettingsWindow.current?.hide(fade: nil)
        self.surface = nil
    }
}

final class SettingsSurfaceView: NSView {
    private let model: AppModel
    private var placement: SettingsPlacement
    /// Each page in a view graph of its own, kept, the shown one visible.
    let deck: SettingsPageDeckView
    /// The sidebar and the deck beside it.
    private let pagesHost = SettingsPagesView()
    /// The sidebar and the pages, as one view (what fades in when Settings opens).
    var pagesView: NSView { pagesHost }
    /// The sidebar (SwiftUI), under the deck.
    let sidebarHost: DeferringHostingView<AnyView>
    /// Customize while it is open or on its way out; built as it opens, gone once it has closed.
    private var customizeHost: NSHostingView<AnyView>?
    private var customizePresentation: CustomizePresentation?
    private var customizeRemoval: Timer?

    init(model: AppModel, placement: SettingsPlacement) {
        self.model = model
        self.placement = placement
        deck = SettingsPageDeckView(model: model)
        sidebarHost = DeferringHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        wantsLayer = true
        sidebarHost.sizingOptions = []
        sidebarHost.safeAreaRegions = []
        sidebarHost.rootView = pagesRoot
        if let id = model.studio.customizing, let presentation = customizePresentation {
            customizeHost?.rootView = customizeRoot(id, presentation)
        }
        pagesHost.addSubview(sidebarHost)
        pagesHost.addSubview(deck)
        addSubview(pagesHost)
        deck.show(model.settingsPane)
        observePane()
        observeCustomizing()
    }

    /// Settings opens again with the kept pages: as a new surface would have started.
    func reattach(placement: SettingsPlacement) {
        update(placement: placement)
    }

    /// Settings is shown: the page it shows starts afresh, fading in on the render server.
    func show() {
        layer?.removeAnimation(forKey: Self.hideKey)
        alphaValue = 1
        deck.show(model.settingsPane)
        deck.reopen()
        // Left faded by a Customize that closed with Settings.
        pagesHost.alphaValue = 1
        pagesHost.fadeInOnRenderServer(duration: IslandSettingsView.pagesFadeIn)
    }

    /// Settings closes: faded out over `fade` (at once without), its pages standing still
    /// (clocks, readings, looping pictures) until shown again.
    func hide(fade: TimeInterval?) {
        deck.closed()
        // Customize goes with Settings (the pages stay faded until Settings shows them again).
        if model.studio.customizing != nil { model.studio.customizing = nil }
        tearDownCustomize(restoresPages: false)
        guard let fade, let layer, alphaValue > 0 else {
            layer?.removeAnimation(forKey: Self.hideKey)
            alphaValue = 0
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? 1
        animation.toValue = 0
        animation.duration = fade
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        alphaValue = 0
        layer.add(animation, forKey: Self.hideKey)
        CATransaction.commit()
    }

    static let hideKey = "settingsHide"

    /// What decides whether the pages can be seen, for the log (`SettingsWindow.verifyShown`).
    var visibilityDescription: String {
        let page = deck.shown.map { "\($0)" } ?? "none"
        return "surface alpha \(alphaValue) opacity \(layer?.opacity ?? -1) frame \(frame.size); "
            + "pages hidden \(pagesHost.isHidden) alpha \(pagesHost.alphaValue) opacity \(pagesHost.layer?.opacity ?? -1) "
            + "animations \(pagesHost.layer?.animationKeys() ?? []); deck \(page), \(deck.subviews.filter { !$0.isHidden }.count) shown"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        pagesHost.frame = bounds
        sidebarHost.frame = pagesHost.bounds
        // Beside the sidebar, as `SettingsPages` leaves room for it.
        let leading = placement.leading + SettingsPlacement.sidebarWidth
        let deckFrame = CGRect(x: leading, y: 0, width: max(0, bounds.width - leading), height: bounds.height)
        if deck.frame != deckFrame { deck.frame = deckFrame }
        customizeHost?.frame = bounds
    }

    /// The deck shows the pane the sidebar (or a link) picks.
    private func observePane() {
        withObservationTracking {
            _ = model.settingsPane
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.window?.isVisible == true { self.deck.show(self.model.settingsPane) }
                self.observePane()
            }
        }
    }

    // MARK: Customize

    /// Customize opens for the widget `WidgetStudio.customizing` names, and closes when it is nil.
    private func observeCustomizing() {
        withObservationTracking {
            _ = model.studio.customizing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let id = self.model.studio.customizing { self.openCustomize(id) } else { self.closeCustomize() }
                self.observeCustomizing()
            }
        }
    }

    /// Comes in over the pages, which fade out behind it.
    private func openCustomize(_ id: WidgetID) {
        customizeRemoval?.invalidate()
        customizeRemoval = nil
        tearDownCustomize()
        let presentation = CustomizePresentation()
        let host = NSHostingView(rootView: customizeRoot(id, presentation))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = bounds
        addSubview(host)
        customizeHost = host
        customizePresentation = presentation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            pagesHost.animator().alphaValue = 0
        }
        // It comes in in steps of its own as it appears (`WidgetCustomizeView`).
        presentation.isShown = true
    }

    private func customizeRoot(_ id: WidgetID, _ presentation: CustomizePresentation) -> AnyView {
        AnyView(WidgetCustomizeView(id: id, placement: placement, presentation: presentation,
                                    close: { [weak self] in self?.model.studio.customizing = nil })
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true)
            .toggleStyle(.islandSwitch)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule))
    }

    /// Goes out; the pages come back.
    private func closeCustomize() {
        guard let presentation = customizePresentation else { return }
        presentation.isShown = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            pagesHost.animator().alphaValue = 1
        }
        // Taken away once it has gone out, on the efficiency cores: torn down at the main thread's
        // own priority, its graph's teardown was most of a close (~150 ms on the performance cores,
        // Energy Impact ~200, measured). A run-loop timer, so the lowered priority holds for the turn.
        let removal = Timer(timeInterval: WidgetCustomizeView.outDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.customizeRemoval = nil
                MainThrift.lowPower(for: 0.5)
                self.tearDownCustomize()
            }
        }
        RunLoop.main.add(removal, forMode: .common)
        customizeRemoval = removal
    }

    private func tearDownCustomize(restoresPages: Bool = true) {
        customizeRemoval?.invalidate()
        customizeRemoval = nil
        customizeHost?.removeFromSuperview()
        customizeHost = nil
        customizePresentation = nil
        if restoresPages, pagesHost.alphaValue != 1 { pagesHost.alphaValue = 1 }
    }

    func update(placement: SettingsPlacement) {
        guard placement != self.placement else { return }
        self.placement = placement
        needsLayout = true
        sidebarHost.rootView = pagesRoot
    }

    private var pagesRoot: AnyView {
        AnyView(SettingsPages(placement: placement)
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true))
    }
}

/// The sidebar and the deck: one layer to sink back and fade.
final class SettingsPagesView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
}
