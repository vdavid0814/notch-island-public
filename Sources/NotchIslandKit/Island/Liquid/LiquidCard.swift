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
    static let pollInterval: Duration = .milliseconds(20)
    /// The liquid turning into the surface as it lands, and back before it leaves.
    static let toSurface: TimeInterval = 0.3
    static let toLiquid: TimeInterval = 0.1

    private unowned let model: AppModel
    let memory = SystemVolumeCardMemory()
    let state = LiquidCardState()
    private var panel: IslandPanel?
    private var watch: Task<Void, Never>?
    private var hideAfter = Date.distantPast
    private var cardSeen = false
    /// The last change macOS's card is up for: it goes a set time after it (`lifetimes`).
    private var lastChange = Date.distantPast
    /// How long macOS's card stays after the last change, by kind: measured each time (it went
    /// 1.70–1.74 s after a volume key, its last half second shrinking), so the cover can leave with
    /// it rather than after it.
    private var lifetimes: [SystemVolumeCard.Kind: TimeInterval] = [.volume: 1.72, .airPods: 3.0]
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
        if isShown {
            state.kind = .airPods(info)
            hideAfter = max(hideAfter, Date().addingTimeInterval(duration))
            return true
        }
        return begin(.airPods(info), duration: duration, islandBanner: .airPods(info), flows: flows)
    }

    /// Fresher batteries for the headphones on the card. True when they are on it.
    func airPodsUpdated(_ info: AirPodsInfo) -> Bool {
        guard isShown, case .airPods(let shown) = state.kind, shown.name == info.name else { return false }
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
        state.liquidShown = true
        state.surfaceShown = false
        let panel = self.panel ?? makePanel()
        panel.level = IslandPanel.coveringLevel
        panel.ignoresMouseEvents = true
        panel.stage(state.frame)
        panel.orderFrontRegardless()
        state.start(.out(start: Date(), from: LiquidFlow.start(notch: metrics.notchRect, towards: cover.rect), to: cover))
        land(after: LiquidFlow.out.total)
        Log.levels.notice("liquid card out to \(window.logDescription, privacy: .public)")
        DiagnosticsFlow.record("liquid card out (\(String(describing: kind.card))) to \(window.logDescription)")
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
        state.liquidShown = true
        state.surfaceShown = false
        state.contentVisible = false
        state.start(.move(start: Date(), from: state.drop(at: Date()), to: cover))
        land(after: LiquidFlow.move.total)
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
            self.state.liquidShown = false
            self.panel?.ignoresMouseEvents = false
        }
    }

    private func hide() {
        landing?.cancel()
        panel?.ignoresMouseEvents = true
        state.contentVisible = false
        // Liquid again (the black over the surface) as it already runs back: macOS's card has gone.
        state.liquidShown = true
        state.start(.back(start: Date(), from: state.drop(at: Date())))
        landing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.toLiquid))
            guard !Task.isCancelled, let self else { return }
            self.state.surfaceShown = false
            try? await Task.sleep(for: .seconds(max(LiquidFlow.back.total, 0.2 + LiquidCardState.absorb) - Self.toLiquid))
            guard !Task.isCancelled else { return }
            self.state.stop()
            self.panel?.orderOut(nil)
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
        var target = flowing ? state.target : nil
        var left = false
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self, let metrics = self.model.metrics else { return }
                let card = SystemVolumeCard.find()
                let now = Date()
                let exitAt = self.lastChange.addingTimeInterval((self.lifetimes[cardKind] ?? 1.72) - Self.exitLead)
                let isKept = self.state.isHeld || self.model.banners.isHeld || self.model.island.isInteracting
                if card == nil, self.cardSeen {
                    // Gone: learn how long it stayed after the last change.
                    let stayed = now.timeIntervalSince(self.lastChange)
                    if (0.8...6).contains(stayed) {
                        self.lifetimes[cardKind] = ((self.lifetimes[cardKind] ?? stayed) + stayed) / 2
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
                        Log.levels.notice("macOS's card at \(card.logDescription, privacy: .public) (\(now.timeIntervalSince(started) * 1000, format: .fixed(precision: 0), privacy: .public) ms)")
                    }
                    let cover = LiquidFlow.cover(overCardWindow: card, kind: self.isShown ? self.state.kind.card : cardKind)
                    if self.isShown {
                        if let current = target, current.rect.distance(to: cover.rect) > 2 {
                            self.move(to: card)
                        }
                        target = cover
                        if now >= exitAt, now >= self.hideAfter, !isKept {
                            self.hide()
                            left = true
                        }
                    } else if flows, !SystemVolumeCard.isUnderNotch(card, notch: metrics.notchRect) {
                        // Expected under the notch, came up beside it: the island's cover goes, the
                        // liquid runs there.
                        self.model.banners.dismiss(islandBanner)
                        self.show(kind, towards: card, metrics: metrics, duration: duration)
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
                    if self.isShown {
                        if now >= self.hideAfter, !isKept { self.hide() } else { continue }
                    } else if let current = self.model.banners.current, Self.isCover(current, like: islandBanner), !isKept {
                        self.model.banners.dismiss(current)
                    }
                    return
                }
                guard now.timeIntervalSince(started) > Self.searchTime else { continue }
                // It never came (a change made by an app): the cover keeps its own time.
                if !self.isShown { return }
                if now >= self.hideAfter, !isKept {
                    self.hide()
                    return
                }
            }
        }
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

    private func makePanel() -> IslandPanel {
        let panel = IslandPanel(contentRect: state.frame)
        let host = NSHostingView(rootView: LiquidCardView(state: state).environment(model))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
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
    static let overdraw: CGFloat = 30
    /// How long the notch swells as the drop runs back into it.
    static let absorb: CGFloat = 0.2

    var frame: CGRect = .zero
    var notch: CGRect = .zero
    private(set) var motion: Motion?
    /// When the drop left the notch: its neck thins with that time, also through a move.
    private var leftNotch: Date?
    var kind: LiquidCardKind = .volume(name: "")
    /// The black liquid; the island's surface (glass and shade) the landed card becomes; its content.
    var liquidShown = true
    var surfaceShown = false
    var contentVisible = false
    /// The pointer is on the card.
    var isHeld = false

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
        liquidShown = true
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

    /// Every shape at `date`, in global coordinates.
    func shapes(at date: Date) -> [Path] {
        guard motion != nil else { return [] }
        let drop = drop(at: date)
        var swell: CGFloat = 0
        var neck: CGFloat = 0
        let h = notch.height
        if let leftNotch {
            let t = CGFloat(date.timeIntervalSince(leftNotch))
            let p = CGFloat(progress(LiquidFlow.out, since: leftNotch, at: date))
            swell = LiquidFlow.bump(t, over: 0.18)
            neck = h * (1 - LiquidFlow.smoothstep(0.45, 0.9, p))
        }
        if case .back(let start, _) = motion {
            let q = CGFloat(progress(LiquidFlow.back, since: start, at: date))
            neck = h * LiquidFlow.smoothstep(0.2, 0.6, q)
            // The notch takes the drop in, swelling and settling before the window goes.
            swell = LiquidFlow.bump(CGFloat(date.timeIntervalSince(start)) - 0.2, over: Self.absorb)
        }
        var shapes = [LiquidFlow.notch(notch, swell: swell, overdraw: Self.overdraw), LiquidFlow.path(drop)]
        if let bridge = LiquidFlow.neck(notch: notch, to: drop.rect, thickness: neck) { shapes.append(bridge) }
        return shapes
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

/// The liquid, blurred and cut at half alpha so its shapes flow into each other; the island's
/// surface the landed card becomes, in the card's own outline; and what the card shows.
struct LiquidCardView: View {
    let state: LiquidCardState

    @Environment(AppModel.self) private var model

    var body: some View {
        let overdraw = LiquidCardState.overdraw
        ZStack(alignment: .topLeading) {
            if let target = state.target {
                let rect = state.windowRect(target)
                LiquidCardSurface(radius: target.radius, style: model.effectiveGlassStyle, isShown: state.surfaceShown)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .opacity(state.surfaceShown ? 1 : 0)
            }
            TimelineView(.animation(paused: !state.isAnimating)) { timeline in
                let shapes = state.shapes(at: timeline.date)
                let transform = state.canvasTransform
                Canvas { context, _ in
                    context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    context.addFilter(.blur(radius: LiquidFlow.blur))
                    context.drawLayer { layer in
                        for shape in shapes { layer.fill(shape.applying(transform), with: .color(.black)) }
                    }
                }
            }
            .frame(width: state.frame.width, height: state.frame.height + overdraw)
            .offset(y: -overdraw)
            .opacity(state.liquidShown ? 1 : 0)
            .animation(.easeInOut(duration: state.liquidShown ? LiquidCard.toLiquid : LiquidCard.toSurface), value: state.liquidShown)
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

    @State private var hasAppeared = false

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
                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: hasAppeared)
                .position(Self.iconCenter)
            Text(info.name)
                .font(Self.nameFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 150)
                .position(x: Self.textCenterX, y: Self.center(baseline: Self.nameBaseline, size: 11.5, weight: .semibold))
            Text("Connected")
                .font(Self.statusFont)
                .foregroundStyle(.secondary)
                .position(x: Self.textCenterX, y: Self.center(baseline: Self.statusBaseline, size: 11.5, weight: .regular))
            if let level {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: Self.ringWidth)
                    Circle()
                        .trim(from: 0, to: hasAppeared ? CGFloat(level) / 100 : 0)
                        .stroke(level <= 20 ? Color.red : Color.green, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6).delay(0.1), value: hasAppeared)
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
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            hasAppeared = true
        }
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
