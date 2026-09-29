import AppKit
import CoreAudio
import SwiftUI

/// What the liquid card shows: the volume (for a change macOS shows its own card for, an AirPods
/// stem swipe), or headphones that just connected.
nonisolated enum LiquidCardKind: Equatable, Sendable {
    case volume(name: String)
    case airPods(AirPodsInfo)

    /// macOS's card it lies on.
    var card: SystemVolumeCard.Kind {
        switch self {
        case .volume: .volume
        case .airPods: .airPods
        }
    }

    /// How long macOS's card stays is learnt per kind: the noise-control card is the connection
    /// card's window but stays longer.
    var lifetimeKey: String {
        switch self {
        case .volume: "volume"
        case .airPods(let info): info.listeningMode == nil ? "airPods" : "airPodsMode"
        }
    }
}

/// The island's card over macOS's own volume or AirPods card when that one comes up away from the
/// notch (the desktop, beside a tiled window): the island's liquid runs out of the notch to it,
/// lands on it in the card's own outline, turns into the island's surface (black fading into clear
/// glass in the fade style), stays while macOS's card does, and runs back.
///
/// Its own window above macOS's card (the island's window is centred on the notch and cannot reach
/// it). Where the card comes up is remembered per situation (`SystemVolumeCardMemory`) so the liquid
/// is on its way at once; the window list then says where the card really is, and the liquid goes
/// there if that is elsewhere.
@MainActor final class LiquidCard {
    /// How long after a change the card is looked for (it comes up within ~0.45 s, measured), and
    /// how often while it is up: the cover leaves the moment macOS's card is gone (its window goes
    /// ~1.7 s after the last change, having shrunk to 90 % in its last half second, measured), so
    /// it neither leaves the card bare nor stays after it.
    static let searchTime: TimeInterval = 1.0
    /// Quick while the card is due to come up (and may have to be followed elsewhere), slower
    /// after: the way out is timed from the last change, not from seeing the card go. The window
    /// list is read off the main thread (it was a third of the main thread's work per change).
    static let quickPoll: Duration = .milliseconds(25)
    static let slowPoll: Duration = .milliseconds(60)
    static let quickPollTime: TimeInterval = 0.6
    /// The liquid turning into the surface as it lands, and back before it leaves.
    static let toSurface: TimeInterval = 0.3
    static let toLiquid: TimeInterval = 0.1

    private unowned let model: AppModel
    let memory = SystemVolumeCardMemory()
    let state = LiquidCardState()
    private var panel: IslandPanel?
    /// The liquid itself: an outline worked out for every frame, played by the render server.
    private let liquidLayer = CAShapeLayer()
    /// The frames of a move already worked out, by where it goes (the card comes up where it did
    /// before, so the next change reuses them).
    private var framesCache: [String: [CGPath]] = [:]
    private var playID = 0
    /// The card came up somewhere: the frames for there are worked out once the liquid is home.
    private var needsPrewarm = false
    private var watch: Task<Void, Never>?
    private var hideAfter = Date.distantPast
    private var cardSeen = false
    /// The last change macOS's card is up for: it goes a set time after it (`lifetimes`).
    private var lastChange = Date.distantPast
    /// How long macOS's card stays after the last change, by kind: measured each time (it went
    /// 1.70–1.74 s after a volume key, its last half second shrinking), so the cover can leave with
    /// it rather than after it.
    /// By `LiquidCardKind.lifetimeKey`: the noise-control card stays longer than the connection
    /// card in the same window (4.5 s against 3, seen).
    private var lifetimes: [String: TimeInterval] = ["volume": 1.72, "airPods": 3.0, "airPodsMode": 4.5]
    /// The cover's own way out starts this long before macOS's card goes, so both end together
    /// (the card has shrunk to 90 % under it by then).
    static let exitLead: TimeInterval = 0.32
    private var landing: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    var isShown: Bool { state.motion != nil }

    /// A volume change. True when this card answers it (the island shows nothing then).
    func handleLevel(_ kind: LevelKind, source: LevelChangeSource, duration: TimeInterval, flows: Bool = true) -> Bool {
        guard kind == .volume else { return false }
        if source == .external || isShown { lastChange = Date() }
        if state.isLeaving {
            // Running back as the volume changes again: back to the card.
            return source == .external || source == .key ? comeBack(duration: duration) : false
        }
        if isShown {
            if case .airPods = state.kind {} else { state.kind = .volume(name: Self.outputName()) }
            hideAfter = max(hideAfter, Date().addingTimeInterval(duration))
            return true
        }
        guard source == .external else { return false }
        return begin(.volume(name: Self.outputName()), duration: duration, islandBanner: .levelCovering(.volume), flows: flows)
    }

    /// Headphones connected, the island's card meant to cover macOS's. True when this card shows them.
    func airPodsConnected(_ info: AirPodsInfo, duration: TimeInterval, flows: Bool = true) -> Bool {
        lastChange = Date()
        if state.isLeaving {
            state.kind = .airPods(info)
            return comeBack(duration: duration)
        }
        if isShown {
            state.kind = .airPods(info)
            hideAfter = max(hideAfter, Date().addingTimeInterval(duration))
            return true
        }
        return begin(.airPods(info), duration: duration, islandBanner: .airPods(info), flows: flows)
    }

    /// Fresher batteries for the headphones on the card. True when they are on it.
    func airPodsUpdated(_ info: AirPodsInfo) -> Bool {
        guard isShown, case .airPods(let shown) = state.kind, shown.name == info.name,
              shown.listeningMode == info.listeningMode else { return false }
        state.kind = .airPods(info)
        return true
    }

    /// Runs out to where macOS's card is (or is expected), unless that is under the notch, where the
    /// island itself covers it (or the user turned the flow off); then only watches the card, so the
    /// island's cover lasts as long as it does.
    private func begin(_ kind: LiquidCardKind, duration: TimeInterval, islandBanner: BannerKind, flows: Bool) -> Bool {
        guard let metrics = model.metrics else { return false }
        let situation = model.fullscreen.fullscreenApps.count
        // Already up (headphones are announced once their batteries are read): there.
        let expected = SystemVolumeCard.find()
            ?? memory.expected(fullscreenApps: situation, notch: metrics.notchRect, screen: metrics.screenFrame)
        if !flows || SystemVolumeCard.isUnderNotch(expected, notch: metrics.notchRect) {
            watchCard(situation: situation, duration: duration, flowing: false, kind: kind, islandBanner: islandBanner, flows: flows)
            return false
        }
        show(kind, towards: expected, metrics: metrics, duration: duration)
        watchCard(situation: situation, duration: duration, flowing: true, kind: kind, islandBanner: islandBanner, flows: flows)
        return true
    }

    // MARK: Showing

    private func show(_ kind: LiquidCardKind, towards window: CGRect, metrics: NotchMetrics, duration: TimeInterval) {
        hideAfter = Date().addingTimeInterval(duration)
        let cover = LiquidFlow.cover(overCardWindow: window, kind: kind.card)
        let notchCard = LiquidFlow.cover(overCardWindow: SystemVolumeCard.guess(fullscreenApps: 1, notch: metrics.notchRect,
                                                                                  screen: metrics.screenFrame))
        state.kind = kind
        state.notch = metrics.notchRect
        state.frame = frame(covering: [cover.rect, notchCard.rect], metrics: metrics)
        state.surfaceShown = false
        let panel = self.panel ?? makePanel()
        panel.level = IslandPanel.coveringLevel
        panel.ignoresMouseEvents = true
        panel.stage(state.frame)
        setLiquid(shown: true, duration: 0)
        liquidLayer.path = nil
        panel.orderFrontRegardless()
        let from = LiquidFlow.start(notch: metrics.notchRect, towards: cover.rect)
        play({ .out(start: $0, from: from, to: cover) }, duration: LiquidFlow.out.total,
             key: "out|\(kind.card)|\(metrics.notchRect)|\(state.frame)|\(cover.rect)") { [weak self] in
            self?.land(after: LiquidFlow.out.total)
        }
        Log.levels.notice("liquid card out to \(window.logDescription, privacy: .public)")
        DiagnosticsFlow.record("liquid card out (\(String(describing: kind.card))) to \(window.logDescription)")
    }

    /// A change while the liquid runs back (macOS's card comes up again): the drop turns round from
    /// where it is to the card, and the cleanup of the way back is called off.
    private func comeBack(duration: TimeInterval) -> Bool {
        guard case .back(_, let from) = state.motion else { return false }
        landing?.cancel()
        hideAfter = Date().addingTimeInterval(duration)
        setLiquid(shown: true, duration: 0)
        let now = state.drop(at: Date())
        play({ .move(start: $0, from: now, to: from) }, duration: LiquidFlow.move.total, key: nil) { [weak self] in
            self?.land(after: LiquidFlow.move.total)
        }
        let situation = model.fullscreen.fullscreenApps.count
        watchCard(situation: situation, duration: duration, flowing: true, kind: state.kind,
                  islandBanner: .levelCovering(.volume), flows: true)
        Log.levels.notice("liquid card comes back")
        DiagnosticsFlow.record("liquid card comes back")
        return true
    }

    /// macOS's card came up elsewhere than expected: there instead, as liquid again.
    private func move(to window: CGRect) {
        guard let metrics = model.metrics else { return }
        let cover = LiquidFlow.cover(overCardWindow: window, kind: state.kind.card)
        let frame = frame(covering: [state.frame, cover.rect], metrics: metrics)
        if frame != state.frame {
            state.frame = frame
            panel?.stage(frame)
        }
        setLiquid(shown: true, duration: 0)
        state.surfaceShown = false
        state.contentVisible = false
        let from = state.drop(at: Date())
        play({ .move(start: $0, from: from, to: cover) }, duration: LiquidFlow.move.total, key: nil) { [weak self] in
            self?.land(after: LiquidFlow.move.total)
        }
        Log.levels.notice("liquid card moved to \(window.logDescription, privacy: .public)")
    }

    private func land(after seconds: TimeInterval) {
        landing?.cancel()
        // The content fades in as the drop settles; then the liquid becomes the surface.
        landing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds * 0.55))
            guard !Task.isCancelled, let self else { return }
            self.state.contentVisible = true
            try? await Task.sleep(for: .seconds(seconds * 0.45))
            guard !Task.isCancelled else { return }
            self.state.settle()
            self.state.surfaceShown = true
            self.setLiquid(shown: false, duration: Self.toSurface)
            self.panel?.ignoresMouseEvents = false
        }
    }

    private func hide() {
        landing?.cancel()
        panel?.ignoresMouseEvents = true
        state.contentVisible = false
        // Liquid again (the black over the surface) as it already runs back: macOS's card has gone.
        setLiquid(shown: true, duration: Self.toLiquid)
        let from = state.drop(at: Date())
        // Leaving from now on, even before the frames are worked out (a change meanwhile turns it round).
        state.start(.back(start: Date(), from: from))
        let total = max(LiquidFlow.back.total, 0.2 + Double(LiquidCardState.absorb))
        play({ .back(start: $0, from: from) }, duration: total,
             key: "back|\(state.kind.card)|\(state.notch)|\(state.frame)|\(from.rect)") { [weak self] in
            guard let self else { return }
            self.landing = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.toLiquid))
                guard !Task.isCancelled, let self else { return }
                self.state.surfaceShown = false
                try? await Task.sleep(for: .seconds(total - Self.toLiquid))
                guard !Task.isCancelled else { return }
                self.state.stop()
                self.liquidLayer.removeAllAnimations()
                self.liquidLayer.path = nil
                self.panel?.orderOut(nil)
                if self.needsPrewarm {
                    self.needsPrewarm = false
                    self.prewarm()
                }
            }
        }
        Log.levels.notice("liquid card back")
        DiagnosticsFlow.record("liquid card back")
    }

    // MARK: macOS's card

    /// Looks for macOS's card: remembers where it came up, follows it if it is elsewhere, and leaves
    /// with it: the cover's way out starts `exitLead` before the card is due to go (the last change
    /// plus its measured lifetime), or at once if it goes sooner. The pointer on the card, or a drag
    /// of its slider, keeps it. Then how long the card really stayed is learnt.
    private func watchCard(situation: Int, duration: TimeInterval, flowing: Bool, kind: LiquidCardKind, islandBanner: BannerKind,
                           flows: Bool) {
        watch?.cancel()
        cardSeen = false
        let started = Date()
        let cardKind = kind.card
        let lifetimeKey = kind.lifetimeKey
        var target = flowing ? state.target : nil
        var left = false
        /// The card came up under the notch while the liquid ran elsewhere: the island covers it now.
        var handedOver = false
        var learnt = false
        /// Sent out from here: shown from now on, even before its frames are worked out and it
        /// starts to move (it was sent out again on every look meanwhile, 25 times, seen).
        var sentOut = flowing
        /// The AirPods cards leave with macOS's, whatever the banner's time (5.5 s against a card
        /// of 4.5, seen); the volume card keeps its tuned timing.
        let followsCardOnly = cardKind == .airPods
        watch = Task { [weak self] in
            while !Task.isCancelled {
                let quick = Date().timeIntervalSince(started) < Self.quickPollTime
                try? await Task.sleep(for: quick ? Self.quickPoll : Self.slowPoll, tolerance: .milliseconds(5))
                let card = await SystemVolumeCard.findOffMain()
                guard !Task.isCancelled, let self, let metrics = self.model.metrics else { return }
                let now = Date()
                let exitAt = self.lastChange.addingTimeInterval((self.lifetimes[lifetimeKey] ?? 1.72) - Self.exitLead)
                let isKept = self.state.isHeld || self.model.banners.isHeld || self.model.island.isInteracting
                if card == nil, self.cardSeen, !learnt {
                    // Gone: learn how long it stayed after the last change (once).
                    learnt = true
                    let stayed = now.timeIntervalSince(self.lastChange)
                    if (0.8...6).contains(stayed) {
                        self.lifetimes[lifetimeKey] = ((self.lifetimes[lifetimeKey] ?? stayed) + stayed) / 2
                    }
                    Log.levels.notice("macOS's card went \(stayed, format: .fixed(precision: 2), privacy: .public) s after the last change")
                }
                if left {
                    if card == nil { return }
                    continue
                }
                if let card {
                    if !self.cardSeen {
                        self.cardSeen = true
                        self.memory.learn(card, fullscreenApps: situation, screen: metrics.screenFrame)
                        self.needsPrewarm = true
                        Log.levels.notice("macOS's card at \(card.logDescription, privacy: .public) (\(now.timeIntervalSince(started) * 1000, format: .fixed(precision: 0), privacy: .public) ms)")
                    }
                    let shown = (self.isShown || sentOut) && !handedOver
                    let cover = LiquidFlow.cover(overCardWindow: card, kind: shown ? self.state.kind.card : cardKind)
                    if shown, flows, SystemVolumeCard.isUnderNotch(card, notch: metrics.notchRect) {
                        // Ran out to where it came up before, came up under the notch (the situation
                        // was read wrong): the liquid goes home, the island covers the card.
                        handedOver = true
                        let banner: BannerKind = if case .airPods(let info) = self.state.kind { .airPods(info) } else { islandBanner }
                        self.hide()
                        self.model.banners.post(banner, duration: 0.1)
                        Log.levels.notice("macOS's card came up under the notch: the island covers it")
                        continue
                    }
                    if shown {
                        if let current = target, current.rect.distance(to: cover.rect) > 2 {
                            self.move(to: card)
                        }
                        target = cover
                        if now >= exitAt, followsCardOnly || now >= self.hideAfter, !isKept {
                            self.hide()
                            left = true
                        }
                    } else if flows, !SystemVolumeCard.isUnderNotch(card, notch: metrics.notchRect) {
                        // Expected under the notch, came up beside it: the island's cover goes, the
                        // liquid runs there.
                        self.model.banners.dismiss(islandBanner)
                        self.show(kind, towards: card, metrics: metrics, duration: duration)
                        sentOut = true
                        target = cover
                    } else {
                        // Under the notch: the island's cover lasts as long as the card.
                        guard SystemVolumeCard.isUnderNotch(card, notch: metrics.notchRect),
                              let current = self.model.banners.current, Self.isCover(current, like: islandBanner) else { return }
                        if now >= exitAt, !isKept {
                            self.model.banners.dismiss(current)
                            left = true
                        } else {
                            self.model.banners.post(current, duration: 0.1, preempting: false)
                        }
                    }
                    continue
                }
                // No card now.
                if self.cardSeen {
                    if (self.isShown || sentOut), !handedOver {
                        if (followsCardOnly || now >= self.hideAfter), !isKept { self.hide() } else { continue }
                    } else if let current = self.model.banners.current, Self.isCover(current, like: islandBanner), !isKept {
                        self.model.banners.dismiss(current)
                    }
                    return
                }
                guard now.timeIntervalSince(started) > Self.searchTime else { continue }
                // It never came (a change made by an app): the cover keeps its own time.
                if !(self.isShown || sentOut) { return }
                if now >= self.hideAfter, !isKept {
                    self.hide()
                    return
                }
            }
        }
    }

    /// For the report: where macOS's card is expected now, what was learnt of its lifetime, and the
    /// frames worked out.
    var diagnosticsSummary: String {
        let situation = model.fullscreen.fullscreenApps.count
        let expected = model.metrics.map {
            memory.expected(fullscreenApps: situation, notch: $0.notchRect, screen: $0.screenFrame).logDescription
        } ?? "no screen"
        let lifetimes = lifetimes.map { "\($0.key) \(String(format: "%.2f", $0.value)) s" }.sorted().joined(separator: ", ")
        return "\(isShown ? "showing \(state.kind)" : "idle"); card expected at \(expected) (situation \(situation)); "
            + "card lasts \(lifetimes); \(framesCache.count) moves worked out"
    }

    /// The island banner covering macOS's card of the same kind (the AirPods one changes as their
    /// batteries come in).
    static func isCover(_ banner: BannerKind, like cover: BannerKind) -> Bool {
        switch (banner, cover) {
        case (.airPods, .airPods): true
        default: banner == cover
        }
    }

    // MARK: Window

    /// Three layers: the card's surface (SwiftUI), the liquid over it (Core Animation), and the
    /// card's content on top (SwiftUI).
    private func makePanel() -> IslandPanel {
        let panel = IslandPanel(contentRect: state.frame)
        let container = NSView(frame: CGRect(origin: .zero, size: state.frame.size))
        container.wantsLayer = true
        let surface = NSHostingView(rootView: LiquidSurfaceLayer(state: state).environment(model))
        let content = NSHostingView(rootView: LiquidContentLayer(state: state).environment(model))
        let liquid = NSView(frame: container.bounds)
        liquid.wantsLayer = true
        liquidLayer.fillColor = CGColor(gray: 0, alpha: 1)
        liquidLayer.frame = liquid.bounds
        liquidLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        liquid.layer?.addSublayer(liquidLayer)
        for view in [surface, liquid, content] as [NSView] {
            (view as? NSHostingView<AnyView>)?.sizingOptions = []
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        surface.sizingOptions = []
        content.sizingOptions = []
        panel.contentView = container
        self.panel = panel
        return panel
    }

    // MARK: Frames

    /// Works out ahead, at background priority, the frames of the way out to where macOS's card is
    /// expected and back (for both cards), so the first change does not wait on them (~0.45 s of
    /// CPU on a performance core at that moment, measured). After launch and whenever the
    /// situation or the card's place changes.
    func prewarm() {
        guard let metrics = model.metrics, !isShown else { return }
        let situation = model.fullscreen.fullscreenApps.count
        let window = memory.expected(fullscreenApps: situation, notch: metrics.notchRect, screen: metrics.screenFrame)
        guard !SystemVolumeCard.isUnderNotch(window, notch: metrics.notchRect) else { return }
        var jobs: [(key: String, scenes: [LiquidScene], clip: CGRect, origin: CGPoint)] = []
        for kind in [SystemVolumeCard.Kind.volume, .airPods] {
            let cover = LiquidFlow.cover(overCardWindow: window, kind: kind)
            let notchCard = LiquidFlow.cover(overCardWindow: SystemVolumeCard.guess(fullscreenApps: 1, notch: metrics.notchRect,
                                                                                      screen: metrics.screenFrame))
            let frame = frame(covering: [cover.rect, notchCard.rect], metrics: metrics)
            let from = LiquidFlow.start(notch: metrics.notchRect, towards: cover.rect)
            let out = "out|\(kind)|\(metrics.notchRect)|\(frame)|\(cover.rect)"
            let back = "back|\(kind)|\(metrics.notchRect)|\(frame)|\(cover.rect)"
            let clip = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + LiquidCardState.overdraw)
            if framesCache[out] == nil {
                jobs.append((out, Self.scenes({ .out(start: $0, from: from, to: cover) }, duration: LiquidFlow.out.total,
                                              notch: metrics.notchRect), clip, frame.origin))
            }
            if framesCache[back] == nil {
                let total = max(LiquidFlow.back.total, 0.2 + Double(LiquidCardState.absorb))
                jobs.append((back, Self.scenes({ .back(start: $0, from: cover) }, duration: total, notch: metrics.notchRect), clip, frame.origin))
            }
        }
        guard !jobs.isEmpty else { return }
        Task(priority: .background) { [weak self] in
            for job in jobs {
                let paths = await Self.trace(job.scenes, clip: job.clip, origin: job.origin)
                guard let self else { return }
                if self.framesCache.count > 12 { self.framesCache.removeAll() }
                self.framesCache[job.key] = paths
            }
        }
    }

    /// Every frame's scene of a move, 120 a second.
    private static func scenes(_ make: (Date) -> LiquidCardState.Motion, duration: TimeInterval, notch: CGRect) -> [LiquidScene] {
        let nominal = Date()
        let motion = make(nominal)
        let leftNotch: Date? = if case .out = motion { nominal } else { nil }
        let count = max(2, Int((duration * 120).rounded(.up)) + 1)
        return (0..<count).map { index in
            LiquidCardState.scene(motion: motion, leftNotch: leftNotch, notch: notch,
                                  at: nominal.addingTimeInterval(min(Double(index) / 120, duration)))
        }
    }

    /// Plays a move on the render server: its outline at every frame (120 a second), worked out off
    /// the main thread (or reused), then the state follows from the moment it starts.
    private func play(_ make: @escaping (Date) -> LiquidCardState.Motion, duration: TimeInterval, key: String?,
                      then started: @escaping () -> Void) {
        playID += 1
        let id = playID
        let notch = state.notch, frame = state.frame
        let cached = key.flatMap { framesCache[$0] }
        let scenes = cached == nil ? Self.scenes(make, duration: duration, notch: notch) : []
        let clip = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + LiquidCardState.overdraw)
        Task { [weak self] in
            let paths = if let cached { cached } else { await Self.trace(scenes, clip: clip, origin: frame.origin) }
            guard let self, self.playID == id else { return }
            if let key, cached == nil { self.framesCache[key] = paths }
            if self.framesCache.count > 12 { self.framesCache.removeAll() }
            self.state.start(make(Date()))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.liquidLayer.path = paths.last
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = paths
            animation.duration = duration
            animation.calculationMode = .discrete
            self.liquidLayer.add(animation, forKey: "flow")
            CATransaction.commit()
            started()
        }
    }

    @concurrent nonisolated private static func trace(_ scenes: [LiquidScene], clip: CGRect, origin: CGPoint) async -> [CGPath] {
        var move = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        return scenes.map { LiquidField.path($0, clip: clip).copy(using: &move) ?? CGMutablePath() }
    }

    /// The liquid shows (black over the surface) or clears (the surface under it shows).
    private func setLiquid(shown: Bool, duration: TimeInterval) {
        let target: Float = shown ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        liquidLayer.opacity = target
        CATransaction.commit()
    }

    /// Everything the liquid may reach: the notch, the card and the neck between, with room for the
    /// blur; the top is the screen's.
    private func frame(covering rects: [CGRect], metrics: NotchMetrics) -> CGRect {
        let union = rects.reduce(metrics.notchRect) { $0.union($1) }.insetBy(dx: -24, dy: -24)
        let top = metrics.screenFrame.maxY
        return CGRect(x: union.minX, y: union.minY, width: union.width, height: top - union.minY).integral
    }

    /// The output macOS's card names (the AirPods, usually).
    static func outputName() -> String {
        DiagnosticsEnvironment.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
            .flatMap(DiagnosticsEnvironment.deviceName) ?? "Volume"
    }
}

/// Where the liquid is: what it is doing since when, the window it is drawn in, what the card shows,
/// and which of liquid, surface and content are up.
@MainActor @Observable final class LiquidCardState {
    nonisolated enum Motion: Equatable {
        /// Out of the notch to the card.
        case out(start: Date, from: LiquidBlob, to: LiquidBlob)
        /// To where the card really came up.
        case move(start: Date, from: LiquidBlob, to: LiquidBlob)
        /// At rest over the card.
        case landed(LiquidBlob)
        /// Back into the notch.
        case back(start: Date, from: LiquidBlob)
    }

    /// Past the screen's top edge, so the blur never rounds the island off there.
    nonisolated static let overdraw: CGFloat = 30
    /// How long the notch swells as the drop runs back into it.
    nonisolated static let absorb: CGFloat = 0.2

    var frame: CGRect = .zero
    var notch: CGRect = .zero
    private(set) var motion: Motion?
    /// When the drop left the notch: its neck thins with that time, also through a move.
    private var leftNotch: Date?
    var kind: LiquidCardKind = .volume(name: "")
    /// The island's surface (glass and shade) the landed card becomes, and its content.
    var surfaceShown = false
    var contentVisible = false
    /// The pointer is on the card.
    var isHeld = false

    /// Running back into the notch.
    var isLeaving: Bool {
        if case .back = motion { true } else { false }
    }

    var isAnimating: Bool {
        switch motion {
        case .out, .move, .back: true
        case .landed, nil: false
        }
    }

    /// Where the drop is headed (or lies).
    var target: LiquidBlob? {
        switch motion {
        case .out(_, _, let to), .move(_, _, let to): to
        case .landed(let blob): blob
        case .back, nil: nil
        }
    }

    func start(_ motion: Motion) {
        switch motion {
        case .out(let start, _, _): leftNotch = start
        case .back: leftNotch = nil
        case .move, .landed: break
        }
        self.motion = motion
    }

    func settle() {
        if let target { motion = .landed(target) }
        leftNotch = nil
    }

    func stop() {
        motion = nil
        leftNotch = nil
        contentVisible = false
        surfaceShown = false
        isHeld = false
    }

    private func progress(_ curve: LiquidCurve, since start: Date, at date: Date) -> Double {
        curve.value(at: date.timeIntervalSince(start))
    }

    /// The drop at `date`.
    func drop(at date: Date) -> LiquidBlob {
        switch motion {
        case .out(let start, let from, let to):
            return LiquidFlow.drop(progress(LiquidFlow.out, since: start, at: date), from: from, to: to)
        case .move(let start, let from, let to):
            return from.mixed(with: to, by: progress(LiquidFlow.move, since: start, at: date))
        case .landed(let blob):
            return blob
        case .back(let start, let from):
            // The way out, backwards: up to the menu bar, then along it into the notch.
            let q = progress(LiquidFlow.back, since: start, at: date)
            return LiquidFlow.drop(1 - q, from: LiquidFlow.start(notch: notch, towards: from.rect), to: from)
        case nil:
            return LiquidBlob(rect: .zero, radius: 0)
        }
    }

    /// The liquid at `date` of `motion`: the notch swelling as the drop gathers or comes back, the
    /// drop, and the neck between them (thinning as the drop leaves, from `leftNotch`).
    nonisolated static func scene(motion: Motion, leftNotch: Date?, notch: CGRect, at date: Date) -> LiquidScene {
        func progress(_ curve: LiquidCurve, since start: Date) -> Double { curve.value(at: date.timeIntervalSince(start)) }
        let drop: LiquidBlob = switch motion {
        case .out(let start, let from, let to): LiquidFlow.drop(progress(LiquidFlow.out, since: start), from: from, to: to)
        case .move(let start, let from, let to): from.mixed(with: to, by: progress(LiquidFlow.move, since: start))
        case .landed(let blob): blob
        case .back(let start, let from):
            // The way out, backwards: up to the menu bar, then along it into the notch.
            LiquidFlow.drop(1 - progress(LiquidFlow.back, since: start), from: LiquidFlow.start(notch: notch, towards: from.rect), to: from)
        }
        var swell: CGFloat = 0
        var neck: CGFloat = 0
        let h = notch.height
        if let leftNotch {
            swell = LiquidFlow.bump(CGFloat(date.timeIntervalSince(leftNotch)), over: 0.18)
            neck = h * (1 - LiquidFlow.smoothstep(0.45, 0.9, CGFloat(progress(LiquidFlow.out, since: leftNotch))))
        }
        if case .back(let start, _) = motion {
            neck = h * LiquidFlow.smoothstep(0.2, 0.6, CGFloat(progress(LiquidFlow.back, since: start)))
            // The notch takes the drop in, swelling and settling before the window goes.
            swell = LiquidFlow.bump(CGFloat(date.timeIntervalSince(start)) - 0.2, over: absorb)
        }
        let grow = 12 * swell
        let notchRect = CGRect(x: notch.minX - grow, y: notch.minY - grow * 0.5, width: notch.width + 2 * grow,
                               height: notch.height + grow * 0.5 + overdraw)
        let right = drop.rect.midX >= notch.midX
        let anchor = CGPoint(x: right ? notch.maxX - h * 0.6 : notch.minX + h * 0.6, y: notch.maxY - h * 0.45)
        return LiquidScene(notch: notchRect, notchRadius: min(8 + grow, notch.height / 2), drop: drop,
                           neckFrom: anchor, neckTo: CGPoint(x: drop.rect.midX, y: drop.rect.midY), neckThickness: neck)
    }

    /// Global coordinates (y up) → the canvas's (y down, `overdraw` above the window).
    var canvasTransform: CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -frame.minX, ty: frame.maxY + Self.overdraw)
    }

    /// Where the card lies in the window (y down).
    func windowRect(_ blob: LiquidBlob) -> CGRect {
        blob.rect.applying(canvasTransform).offsetBy(dx: 0, dy: -Self.overdraw)
    }
}

/// The bottom layer: the island's surface the landed card becomes, in the card's own outline.
struct LiquidSurfaceLayer: View {
    let state: LiquidCardState

    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target = state.target {
                let rect = state.windowRect(target)
                LiquidCardSurface(radius: target.radius, style: model.effectiveGlassStyle, isShown: state.surfaceShown)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .opacity(state.surfaceShown ? 1 : 0)
            }
        }
        .frame(width: state.frame.width, height: state.frame.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
    }
}

/// The top layer: what the card shows, over the liquid.
struct LiquidContentLayer: View {
    let state: LiquidCardState

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target = state.target {
                let rect = state.windowRect(target)
                LiquidCardContent(kind: state.kind)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .opacity(state.contentVisible ? 1 : 0)
                    .animation(.easeOut(duration: state.contentVisible ? 0.16 : 0.08), value: state.contentVisible)
                    .onHover { state.isHeld = $0 }
            }
        }
        .frame(width: state.frame.width, height: state.frame.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }
}

/// The landed card's surface: the island's glass in the card's outline, under the fade style's
/// black (solid at the top, clearing into the glass towards the bottom and the sides).
struct LiquidCardSurface: View {
    let radius: CGFloat
    let style: IslandGlassStyle
    let isShown: Bool

    /// The fade's black is whole this far down, as the island's is through the notch band.
    static let solidDepth: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        GlassEffectContainer {
            Color.clear
                .islandSurfaceShade(style, solidDepth: Self.solidDepth, in: shape.inset(by: -IslandGlassStyle.shadeBleed))
                .islandGlass(in: shape, isEnabled: isShown)
                .environment(\.islandGlassStyle, style)
        }
        .clipShape(shape)
    }
}

/// What the card shows: the volume row under the output's name, like macOS's card, or the
/// headphones that connected with their batteries.
struct LiquidCardContent: View {
    let kind: LiquidCardKind

    @Environment(AppModel.self) private var model

    var body: some View {
        switch kind {
        case .volume(let name):
            SystemVolumeCardContent(name: name)
        case .airPods(let info):
            LiquidAirPodsContent(info: info)
        }
    }
}

/// Headphones that connected, laid out as macOS's own AirPods card is (measured from its image, in
/// the card's 236 × 52 pt): the picture on the left, the name and "Connected" centred, the battery
/// ring on the right. Where the fade style's glass lets macOS's card show through, each line lies on
/// its own.
struct LiquidAirPodsContent: View {
    let info: AirPodsInfo

    /// Positions in the card (points, from its top left).
    static let iconCenter = CGPoint(x: 30.5, y: 26)
    static let nameBaseline: CGFloat = 22.5
    static let statusBaseline: CGFloat = 38
    static let textCenterX: CGFloat = 118
    static let ringCenter = CGPoint(x: 209.5, y: 26)
    static let ringDiameter: CGFloat = 36
    static let ringWidth: CGFloat = 3.5
    static let nameFont = Font.system(size: 11.5, weight: .semibold)
    static let statusFont = Font.system(size: 11.5)

    var body: some View {
        let level = battery
        ZStack(alignment: .topLeading) {
            Image(systemName: info.symbol)
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .position(Self.iconCenter)
            Text(info.name)
                .font(Self.nameFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 150)
                .position(x: Self.textCenterX, y: Self.center(baseline: Self.nameBaseline, size: 11.5, weight: .semibold))
            // A change of noise control says the mode where a connection says "Connected".
            Text(info.listeningMode?.title ?? String(localized: "Connected"))
                .font(Self.statusFont)
                .foregroundStyle(.secondary)
                .position(x: Self.textCenterX, y: Self.center(baseline: Self.statusBaseline, size: 11.5, weight: .regular))
            // The battery ring in both: macOS's noise-control card keeps it (seen).
            if let level {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: Self.ringWidth)
                    // Still, as macOS's ring under it: an animated fill was redrawn on the CPU every
                    // frame (and ran ahead of or behind macOS's).
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(level <= 20 ? Color.red : Color.green, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(level)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: Self.ringDiameter - Self.ringWidth, height: Self.ringDiameter - Self.ringWidth)
                .position(Self.ringCenter)
            }
        }
        .frame(width: 236, height: 52, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Where a line of text of the system font is centred for its baseline to lie at `baseline`
    /// (a text view is as tall as the font's ascender and descender).
    static func center(baseline: CGFloat, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return baseline - font.ascender + (font.ascender - font.descender) / 2
    }

    /// The one number macOS's card shows: the lower earbud's (or the one battery there is).
    private var battery: Int? {
        switch (info.left, info.right) {
        case let (left?, right?): min(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        default: info.single ?? info.chargingCase
        }
    }
}

private extension CGRect {
    func distance(to other: CGRect) -> CGFloat {
        max(abs(midX - other.midX), abs(midY - other.midY), abs(width - other.width), abs(height - other.height))
    }
}
