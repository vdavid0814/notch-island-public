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

    func makeNSView(context: Context) -> SettingsSurfaceView {
        let view = SettingsSurfaceView(model: model, placement: placement)
        model.studio.probe.driver = view
        return view
    }

    func updateNSView(_ view: SettingsSurfaceView, context: Context) {
        view.update(placement: placement)
    }

    static func dismantleNSView(_ view: SettingsSurfaceView, coordinator: ()) {
        view.cancel()
    }
}

final class SettingsSurfaceView: NSView, CustomizeDriving {
    private let model: AppModel
    private var placement: SettingsPlacement
    private let pagesHost: NSHostingView<AnyView>
    private var editorHost: NSHostingView<AnyView>?
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

    init(model: AppModel, placement: SettingsPlacement) {
        self.model = model
        self.placement = placement
        pagesHost = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        wantsLayer = true
        pagesHost.sizingOptions = []
        pagesHost.safeAreaRegions = []
        pagesHost.wantsLayer = true
        pagesHost.rootView = pagesRoot
        addSubview(pagesHost)
        addSubview(overlay)
        pagesHost.fadeInOnRenderServer(duration: IslandSettingsView.pagesFadeIn)
        // A request that arrived before Settings had grown (a deep link, the island's menu).
        if let id = model.studio.customizing, model.editedWidgets.board.contains(id) {
            DispatchQueue.main.async { [weak self] in self?.open(id, animated: false) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        pagesHost.frame = bounds
        editorHost?.frame = bounds
        overlay.frame = bounds
    }

    func update(placement: SettingsPlacement) {
        guard placement != self.placement else { return }
        self.placement = placement
        pagesHost.rootView = pagesRoot
        if let id = model.studio.customizing, editorHost != nil { editorHost?.rootView = editorRoot(id) }
    }

    private var pagesRoot: AnyView {
        AnyView(SettingsPages(placement: placement)
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.appearsActive, true))
    }

    private func editorRoot(_ id: WidgetID) -> AnyView {
        AnyView(CustomizeEditor(widgetID: id, placement: placement, close: { [weak self] in self?.close() })
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
        editorHost?.removeFromSuperview()
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
        let host = NSHostingView(rootView: editorRoot(id))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.frame = bounds
        addSubview(host, positioned: .below, relativeTo: overlay)
        editorHost = host
        return host
    }

    private func tearDownEditor() {
        guard let editor = editorHost else { return }
        editorHost = nil
        MainThrift.lowPower(for: 0.3)
        editor.removeFromSuperview()
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
            .controlSize(Metrics.controlSize(forScale: model.layout.scale.factor))
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
