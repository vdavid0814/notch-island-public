import AppKit
import SwiftUI

/// Settings' page area: the pages (sidebar and page) and, on demand, one widget's Customize editor,
/// each in a view graph of its own, and over them a layer the widget flies in between the two.
///
/// Customize opens as a hero: the widget is drawn once (`ImageRenderer`, at the canvas's
/// magnification) into one layer that the render server carries from the widget's place on the
/// stage to its place on the canvas, while the pages sink back and the editor fades in around it.
/// Nothing is laid out per frame; the layer is removed once the canvas draws the widget itself.
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
        guard window != nil, surface == nil, !isClosing, let frame = screenFrame else { return }
        let settings = SettingsWindow.reused(model: model, placement: placement, frame: frame)
        surface = settings.surface
        model.studio.probe.driver = settings.surface
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
        guard surface != nil, !isClosing, let frame = screenFrame else { return }
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
        guard let surface else { return }
        surface.cancel()
        SettingsWindow.current?.hide(fade: nil)
        self.surface = nil
    }
}

final class SettingsSurfaceView: NSView, CustomizeDriving {
    private let model: AppModel
    private var placement: SettingsPlacement
    /// Each page in a view graph of its own, kept, the shown one visible.
    let deck: SettingsPageDeckView
    /// The sidebar and the deck beside it: what the Customize editor sinks back from.
    private let pagesHost = SettingsPagesView()
    /// The sidebar and the pages, as one view (what fades in when Settings opens).
    var pagesView: NSView { pagesHost }
    /// The sidebar (SwiftUI), under the deck.
    let sidebarHost: DeferringHostingView<AnyView>
    /// The editor while Customize shows (opening, open, closing).
    private var editorHost: NSHostingView<AnyView>?
    /// The editor, built at the first Customize and kept, hidden, for the next: built afresh at
    /// every opening, its inspector's native controls took ~150 ms of a performance core, Activity
    /// Monitor ~240 for a second (measured). Hidden, it lays nothing out (`DeferringHostingView`).
    private var keptEditor: DeferringHostingView<AnyView>?
    /// Counts the openings: a new one gives the kept editor a new editing session.
    private var editorOpenings = 0
    private let overlay = FlierOverlay()
    private var flier: CALayer?
    /// A step of the transition waiting for its moment (cancelled by the next one).
    private var pending: [DispatchWorkItem] = []

    /// Opening: the flier's spring. Closing: back to the stage.
    static let spring = (response: 0.5, bounce: 0.12)
    /// The stage scrolled back into view before a widget flies from it.
    static let stageScroll: TimeInterval = 0.3
    static let pagesOut: TimeInterval = 0.22
    static let pagesBack: TimeInterval = 0.42
    /// The editor starts to fade in this long after the widget took off.
    static let editorDelay: TimeInterval = 0.15
    static let editorIn: TimeInterval = 0.25
    static let editorOut: TimeInterval = 0.16
    /// Reduced Motion, a deep link, the island's menu.
    static let crossFade: TimeInterval = 0.18

    /// `showsPage` false (building Settings ahead): no page yet, each comes in a step of its own.
    init(model: AppModel, placement: SettingsPlacement, showsPage: Bool = true) {
        self.model = model
        self.placement = placement
        deck = SettingsPageDeckView(model: model)
        sidebarHost = DeferringHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        wantsLayer = true
        sidebarHost.sizingOptions = []
        sidebarHost.safeAreaRegions = []
        sidebarHost.rootView = pagesRoot
        pagesHost.addSubview(sidebarHost)
        pagesHost.addSubview(deck)
        addSubview(pagesHost)
        if showsPage { deck.show(model.settingsPane) }
        observePane()
        addSubview(overlay)
        takeEarlyRequest()
    }

    /// Settings opens again with the kept pages: as a new surface would have started.
    func reattach(placement: SettingsPlacement) {
        cancel()
        update(placement: placement)
        takeEarlyRequest()
    }

    /// A request that arrived before Settings had grown (a deep link, the island's menu).
    private func takeEarlyRequest() {
        if let id = model.studio.customizing, model.editedWidgets.board.contains(id) {
            DispatchQueue.main.async { [weak self] in self?.open(id, animated: false) }
        }
    }

    /// Settings is shown: the page it shows starts afresh, fading in on the render server.
    func show() {
        layer?.removeAnimation(forKey: Self.hideKey)
        alphaValue = 1
        deck.show(model.settingsPane)
        deck.reopen()
        pagesHost.fadeInOnRenderServer(duration: IslandSettingsView.pagesFadeIn)
    }

    /// Settings closes: faded out over `fade` (at once without), its pages standing still
    /// (clocks, readings, looping pictures) until shown again.
    func hide(fade: TimeInterval?) {
        deck.closed()
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
        editorHost?.frame = bounds
        overlay.frame = bounds
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

    func update(placement: SettingsPlacement) {
        guard placement != self.placement else { return }
        self.placement = placement
        needsLayout = true
        sidebarHost.rootView = pagesRoot
        if let id = model.studio.customizing, editorHost != nil { editorHost?.rootView = editorRoot(id) }
        // A hidden kept editor takes the new placement when it opens next (`makeEditorHost`).
    }

    private var pagesRoot: AnyView {
        AnyView(SettingsPages(placement: placement)
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true))
    }

    private func editorRoot(_ id: WidgetID) -> AnyView {
        AnyView(CustomizeEditor(widgetID: id, opening: editorOpenings, placement: placement, close: { [weak self] in self?.close() })
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true)
            .toggleStyle(.islandSwitch)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule))
    }

    private var studio: WidgetStudio { model.studio }

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Opening

    func open(_ id: WidgetID, animated: Bool) { open(id, animated: animated, mayScroll: true) }

    private func open(_ id: WidgetID, animated: Bool, mayScroll: Bool) {
        // Idle, or asked for before Settings had grown (`customizing` set, no editor yet).
        guard model.editedWidgets.board.contains(id), studio.phase == .idle, studio.customizing == nil || editorHost == nil else { return }
        cancelPending()
        let source = sourceRect(id)
        // The widget scrolled out of sight on the stage: the stage comes back first.
        if animated, !reducesMotion, mayScroll, LeanSpring.frozenTime == nil, let source, !bounds.contains(source) {
            studio.stageScrollRequest += 1
            schedule(after: Self.stageScroll + 0.05) { [weak self] in self?.open(id, animated: true, mayScroll: false) }
            return
        }
        studio.customizing = id
        let layout = CustomizeLayout(size: bounds.size, placement: placement)
        guard animated, !reducesMotion, let source, bounds.intersects(source),
              let widget = model.editedWidgets.board.widget(id),
              let landing = landingRect(widget, layout: layout),
              let snapshot = snapshot(widget, size: landing.size.applying(.init(scaleX: 1 / landing.zoom, y: 1 / landing.zoom)),
                                      zoom: landing.zoom) else {
            crossFadeIn(id)
            return
        }
        MainThrift.lowPower(for: 0.6)
        // The flier takes the widget's place on the stage in the frame the stage lets go of it.
        whenDrawn(\.stageReport) { [weak self] in
            guard let self, self.studio.phase == .opening, self.studio.customizing == id else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let flier = self.makeFlier(snapshot, landing: landing.rect, zoom: landing.zoom, cornerRadius: WidgetMetrics.cornerRadius)
            flier.transform = Self.transform(from: landing.rect, to: source)
            self.overlay.layer?.addSublayer(flier)
            self.flier = flier
            CATransaction.commit()

            self.fly(flier, to: CATransform3DIdentity, shadowPeak: 0.35)
            self.sink(self.pagesHost, out: true, duration: Self.pagesOut)

            // The editor builds unseen, then fades in around the landing widget.
            let editor = self.makeEditorHost(id)
            editor.alphaValue = 0
            self.schedule(after: Self.editorDelay) { [weak self] in
                self?.fadeIn(editor, from: 1.015, duration: Self.editorIn, started: Self.editorDelay)
            }
            self.schedule(after: Self.settleTime) { [weak self] in self?.landed() }
        }
        studio.phase = .opening
    }

    /// The flier has landed: the canvas draws the widget itself, the pages go.
    private func landed() {
        editorHost?.alphaValue = 1
        pagesHost.isHidden = true
        // The flier goes in the frame the canvas draws the widget.
        whenDrawn(\.canvasReport) { [weak self] in self?.removeFlier() }
        studio.phase = .open
    }

    /// `work` in the update in which the stage (the canvas) takes the next change of phase in, so
    /// both reach the screen together; shortly after it in any case (nothing there to report).
    private func whenDrawn(_ report: ReferenceWritableKeyPath<StudioProbe, (() -> Void)?>, _ work: @escaping () -> Void) {
        var isDone = false
        let once = {
            guard !isDone else { return }
            isDone = true
            work()
        }
        studio.probe[keyPath: report] = once
        let fallback = DispatchWorkItem { [weak self] in
            self?.studio.probe[keyPath: report] = nil
            once()
        }
        pending.append(fallback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: fallback)
    }

    /// Reduced Motion, a deep link, the island's menu: the editor over the pages in a short fade.
    private func crossFadeIn(_ id: WidgetID) {
        studio.phase = .open
        let editor = makeEditorHost(id)
        editor.alphaValue = 0
        fadeIn(editor, from: 1, duration: Self.crossFade)
        schedule(after: Self.crossFade) { [weak self] in self?.pagesHost.isHidden = true }
    }

    // MARK: Closing

    func close() {
        guard let id = studio.customizing, studio.phase == .open || studio.phase == .opening else { return }
        cancelPending()
        removeFlier()
        pagesHost.isHidden = false
        let layout = CustomizeLayout(size: bounds.size, placement: placement)
        guard !reducesMotion, let widget = model.editedWidgets.board.widget(id), let landing = landingRect(widget, layout: layout),
              let snapshot = snapshot(widget, size: landing.size.applying(.init(scaleX: 1 / landing.zoom, y: 1 / landing.zoom)),
                                      zoom: landing.zoom) else {
            crossFadeOut()
            return
        }
        // The flier takes the widget's place on the canvas in the frame the canvas lets go of it.
        whenDrawn(\.canvasReport) { [weak self] in
            guard let self, self.studio.phase == .closing, self.studio.customizing == id else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let flier = self.makeFlier(snapshot, landing: landing.rect, zoom: landing.zoom, cornerRadius: WidgetMetrics.cornerRadius)
            self.overlay.layer?.addSublayer(flier)
            self.flier = flier
            CATransaction.commit()

            if let editor = self.editorHost { self.fadeOut(editor, duration: Self.editorOut) }
            self.sink(self.pagesHost, out: false, duration: Self.pagesBack)
            // The widget's place on the stage, read now: the stage may have moved meanwhile.
            let target = self.sourceRect(id).map { Self.transform(from: landing.rect, to: $0) } ?? CATransform3DMakeScale(0.9, 0.9, 1)
            self.fly(flier, to: target, shadowPeak: 0.35)
            self.schedule(after: Self.settleTime) { [weak self] in
                guard let self else { return }
                // The flier goes in the frame the stage draws the widget again.
                self.whenDrawn(\.stageReport) { [weak self] in self?.removeFlier() }
                self.studio.phase = .idle
                self.studio.customizing = nil
                self.tearDownEditor()
            }
        }
        studio.phase = .closing
    }

    private func crossFadeOut() {
        if let editor = editorHost { fadeOut(editor, duration: Self.crossFade) }
        pagesHost.alphaValue = 1
        schedule(after: Self.crossFade) { [weak self] in
            self?.studio.phase = .idle
            self?.studio.customizing = nil
            self?.tearDownEditor()
        }
    }

    /// Settings is closing: everything at once.
    func cancel() {
        cancelPending()
        removeFlier()
        editorHost?.isHidden = true
        editorHost = nil
        pagesHost.isHidden = false
        pagesHost.alphaValue = 1
        pagesHost.layer?.removeAllAnimations()
        studio.phase = .idle
        studio.customizing = nil
        if studio.probe.driver === self { studio.probe.driver = nil }
    }

    // MARK: Pieces

    private func makeEditorHost(_ id: WidgetID) -> NSHostingView<AnyView> {
        if let editorHost { return editorHost }
        editorOpenings += 1
        if let kept = keptEditor {
            kept.rootView = editorRoot(id)
            kept.frame = bounds
            kept.isHidden = false
            editorHost = kept
            return kept
        }
        let host = DeferringHostingView(rootView: editorRoot(id))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.frame = bounds
        addSubview(host, positioned: .below, relativeTo: overlay)
        keptEditor = host
        editorHost = host
        return host
    }

    /// Builds the kept editor ahead, hidden, laid out once (for the board's first widget; each
    /// opening gives it the widget it edits). False when it is there already or there is nothing
    /// to customize.
    func prepareEditor() -> Bool {
        guard keptEditor == nil, editorHost == nil, let id = model.editedWidgets.board.widgets.first?.id else { return false }
        let host = DeferringHostingView(rootView: editorRoot(id))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.frame = bounds
        host.isHidden = true
        addSubview(host, positioned: .below, relativeTo: overlay)
        host.forcesLayout = true
        host.layoutSubtreeIfNeeded()
        host.forcesLayout = false
        keptEditor = host
        return true
    }

    private func tearDownEditor() {
        guard let editor = editorHost else { return }
        editorHost = nil
        editor.isHidden = true
    }

    /// Where the widget is on the stage now, in this view.
    private func sourceRect(_ id: WidgetID) -> CGRect? {
        guard let anchor = studio.probe.stageView, anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor,
              let widget = model.editedWidgets.board.widget(id), let frame = studio.probe.sourceFrame(widget.frame) else { return nil }
        let scale = studio.probe.roomScale
        guard scale != 1, let room = studio.probe.roomView else { return convert(frame, from: anchor) }
        // Shown smaller about the room's top centre: where the widget is seen, not where it is laid out.
        let inRoom = room.convert(frame, from: anchor)
        let centre = room.bounds.midX
        let seen = CGRect(x: centre + (inRoom.minX - centre) * scale, y: inRoom.minY * scale, width: inRoom.width * scale, height: inRoom.height * scale)
        // The room's own frame is laid out unscaled, centred on the same line.
        let origin = convert(CGPoint(x: centre, y: 0), from: room)
        return CGRect(x: origin.x + (seen.minX - centre), y: origin.y + seen.minY, width: seen.width, height: seen.height)
    }

    /// Where the widget lands on the canvas, and at what magnification.
    private func landingRect(_ widget: IslandWidget, layout: CustomizeLayout) -> (rect: CGRect, size: CGSize, zoom: CGFloat)? {
        let area = layout.canvasArea
        guard area.width > 0, area.height > 0 else { return nil }
        let geometry = CanvasGeometry(area: area.size, widget: widget, canvasSize: .onIsland, layout: model.layout,
                                      grid: model.editedWidgets.board.grid)
        let rect = geometry.scaledWidget.offsetBy(dx: area.minX, dy: area.minY)
        return (rect, rect.size, geometry.zoom)
    }

    /// The widget drawn as the canvas draws it (a picture, the island's layout) at `zoom`, in the
    /// window's pixels: at landing the flier and the canvas are the same picture.
    private func snapshot(_ widget: IslandWidget, size: CGSize, zoom: CGFloat) -> CGImage? {
        let content = IslandWidgetView(widget: widget, size: size, thumbnails: ThumbnailCache())
            .frame(width: size.width, height: size.height)
            .environment(\.widgetRenderMode, .canvas)
            .environment(\.widgetBoard, WidgetBoardShape(grid: model.editedWidgets.board.grid,
                                                         cornerRadius: ConcentricGeometry.boardCornerRadius(model.layout)))
            .controlSize(Metrics.controlSize(forScale: model.layout.factor))
            .environment(\.colorScheme, .dark)
            .environment(model)
        let renderer = ImageRenderer(content: content)
        renderer.scale = (window?.backingScaleFactor ?? 2) * zoom
        return renderer.cgImage
    }

    private func makeFlier(_ image: CGImage, landing: CGRect, zoom: CGFloat, cornerRadius: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resize
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.frame = landing
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: 10)
        layer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: landing.size), cornerWidth: cornerRadius * zoom,
                                  cornerHeight: cornerRadius * zoom, transform: nil)
        return layer
    }

    private func removeFlier() {
        flier?.removeFromSuperlayer()
        flier = nil
    }

    /// The transform that puts a layer at `rect` onto `target` (its anchor at the centre).
    static func transform(from rect: CGRect, to target: CGRect) -> CATransform3D {
        let scale = CATransform3DMakeScale(target.width / max(rect.width, 1), target.height / max(rect.height, 1), 1)
        return CATransform3DConcat(scale, CATransform3DMakeTranslation(target.midX - rect.midX, target.midY - rect.midY, 0))
    }

    /// How long the spring takes to come to rest, near enough.
    static var settleTime: TimeInterval { spring.response * 1.1 }

    private func fly(_ layer: CALayer, to transform: CATransform3D, shadowPeak: Float) {
        let move = CASpringAnimation(perceptualDuration: Self.spring.response, bounce: Self.spring.bounce)
        move.keyPath = "transform"
        move.fromValue = layer.transform
        move.toValue = transform
        let shadow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        shadow.values = [0, shadowPeak, 0]
        shadow.keyTimes = [0, 0.4, 1]
        shadow.duration = Self.settleTime
        for animation in [move, shadow] as [CAAnimation] {
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            Self.freeze(animation)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.add(move, forKey: "fly")
        layer.add(shadow, forKey: "shadow")
        CATransaction.commit()
    }

    /// The pages sink back (0.97×, fading out) or come forward again.
    private func sink(_ view: NSView, out: Bool, duration: TimeInterval) {
        guard let layer = view.layer else { return }
        view.alphaValue = 1
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = out ? 1 : 0.97
        scale.toValue = out ? 0.97 : 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = out ? 1 : 0
        fade.toValue = out ? 0 : 1
        for animation in [scale, fade] {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: out ? .easeIn : .easeOut)
            animation.fillMode = .both
            // Held at its end until the view's own alpha takes over: removed on completion, a
            // frame of the pages at full strength could show before it did.
            animation.isRemovedOnCompletion = false
            Self.freeze(animation)
        }
        Self.centreAnchor(layer)
        layer.add(scale, forKey: "sinkScale")
        layer.add(fade, forKey: "sinkFade")
        schedule(after: duration) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.alphaValue = out ? 0 : 1
            layer.removeAnimation(forKey: "sinkScale")
            layer.removeAnimation(forKey: "sinkFade")
            CATransaction.commit()
        }
    }

    private func fadeIn(_ view: NSView, from scale: CGFloat, duration: TimeInterval, started: TimeInterval = 0) {
        guard let layer = view.layer else { return }
        view.alphaValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = scale
        grow.toValue = 1
        for animation in [fade, grow] {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.fillMode = .backwards
            Self.freeze(animation, started: started)
        }
        Self.centreAnchor(layer)
        layer.add(fade, forKey: "editorFade")
        if scale != 1 { layer.add(grow, forKey: "editorScale") }
    }

    private func fadeOut(_ view: NSView, duration: TimeInterval) {
        guard let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        Self.freeze(fade)
        layer.add(fade, forKey: "editorFade")
    }

    /// Scales about the view's centre (a layer-backed view's anchor is its corner).
    private static func centreAnchor(_ layer: CALayer) {
        guard layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
    }

    /// `demo/freeze`: the animation held at that moment of the transition (`started`: when in the
    /// transition the animation begins).
    private static func freeze(_ animation: CAAnimation, started: TimeInterval = 0) {
        guard let frozen = LeanSpring.frozenTime else { return }
        animation.speed = 0
        animation.timeOffset = max(frozen - started, 0)
    }

    /// A step of the transition, `delay` after its start. Held (`demo/freeze`), the steps before
    /// that moment happen at once and the later ones never: the frame is the transition's there.
    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        if let frozen = LeanSpring.frozenTime {
            if delay <= frozen { work() }
            return
        }
        let item = DispatchWorkItem(block: work)
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPending() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
        studio.probe.stageReport = nil
        studio.probe.canvasReport = nil
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

/// The layer the widget flies in: over everything, answering no click.
private final class FlierOverlay: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let layer = CALayer()
        // Top-left origin, as the view and SwiftUI measure.
        layer.isGeometryFlipped = true
        self.layer = layer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
