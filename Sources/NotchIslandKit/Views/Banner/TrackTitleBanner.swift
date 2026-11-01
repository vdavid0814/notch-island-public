import AppKit
import SwiftUI

/// A new track started (Live Activities ▸ New Track): the Now Playing pill, a little lower and
/// wider, with the title alone in one line under the notch, in the cover's colour. The cover and
/// the bars stay where the pill has them, so the pill only seems to drop. A title wider than its
/// row stands still for half a second, then glides through once, start to end.
struct TrackTitleBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let media = model.media
        let pill = IslandPresentation.compact(.nowPlaying)
        let split = NotchSplit(layout: layout, presentation: pill, outerInset: Metrics.Compact.inset,
                               clearance: Metrics.Compact.notchClearance)
        let glyphSide = max(0, layout.notch.height - 2 * Metrics.Compact.inset)
        let title = media.item?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(spacing: 0) {
            NowPlayingCompact(split: split, height: layout.notch.height, glyphSide: glyphSide)
                .frame(width: layout.size(for: pill).width)
            MarqueeTitle(text: title.isEmpty ? String(localized: "Unknown Title") : title,
                         fontSize: layout.trackTitleFont,
                         color: NSColor(media.artworkColor.map { Color($0) } ?? .islandAccent),
                         within: model.preferences.trackTitleDuration)
                .padding(.horizontal, IslandLayout.trackTitleSideInset * layout.trackTitleSize)
                // A little above the middle of its row: the lower corners take the rest.
                .frame(height: layout.trackTitleRow - (layout.trackTitleRow * 0.12).rounded())
                .frame(height: layout.trackTitleRow, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Now playing: \(title)"))
    }
}

/// A title in one line. It fits: centred, still. Wider than its room: from its start, still for
/// `hold`, then gliding once to its end at `speed`, with its edges fading where it goes on — one
/// animation on the render server, no frame of the app's own.
struct MarqueeTitle: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: NSColor
    /// Seconds it stands still first.
    var hold: Double = 0.5
    /// Points a second, at least.
    var speed: CGFloat = 32
    /// Seconds the glide must have ended within, from the start (the notice's time): faster where
    /// `speed` would not reach the end.
    var within: Double?

    func makeNSView(context: Context) -> MarqueeTitleView { MarqueeTitleView() }

    func updateNSView(_ view: MarqueeTitleView, context: Context) {
        view.update(MarqueeTitleView.Content(text: text, fontSize: fontSize, color: color),
                    timing: MarqueeTitleView.Timing(hold: hold, speed: speed, within: within))
    }
}

final class MarqueeTitleView: NSView {
    struct Content: Equatable {
        var text: String
        var fontSize: CGFloat
        var color: NSColor
    }

    struct Timing: Equatable {
        var hold: Double
        var speed: CGFloat
        var within: Double?

        /// Seconds the glide over `overflow` points takes.
        func glide(_ overflow: CGFloat) -> Double {
            let own = Double(overflow / max(speed, 1))
            guard let within else { return own }
            // Ended a little before the notice goes, so its end is read.
            return min(own, max(within - hold - Self.restAtEnd, 0.6))
        }

        static let restAtEnd: Double = 0.7
    }

    private let text = CALayer()
    private let fade = CAGradientLayer()
    private var content: Content?
    private var timing = Timing(hold: 0.5, speed: 32, within: nil)
    private var textSize: CGSize = .zero
    /// The width the glide was started for: a new title, or another width, starts it over.
    private var startedWidth: CGFloat?
    /// Starts its glide as it is laid out (the banner); off, only when told (`start(at:)`, Settings'
    /// looping picture).
    var startsByItself = true
    static let fadeWidth: CGFloat = 14
    static let animationKey = "glide"

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        text.anchorPoint = .zero
        text.contentsGravity = .resize
        layer?.addSublayer(text)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ new: Content, timing: Timing) {
        let restarts = new.text != content?.text || timing != self.timing
        self.timing = timing
        if new != content {
            content = new
            render()
        }
        if restarts { startedWidth = nil }
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render()
    }

    override func layout() {
        super.layout()
        guard startsByItself, startedWidth != bounds.width else { return }
        start()
    }

    /// The title drawn once into the layer, at the screen's scale.
    private func render() {
        guard let content else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let string = NSAttributedString(string: content.text, attributes: [
            .font: NSFont.systemFont(ofSize: content.fontSize, weight: .semibold),
            .foregroundColor: content.color,
        ])
        let measured = string.size()
        textSize = CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        text.contents = Self.image(of: string, size: textSize, scale: scale)
        text.contentsScale = scale
        CATransaction.commit()
        if startedWidth != nil, text.bounds.size != textSize { startedWidth = nil }
    }

    /// Lays the title out and starts its glide: at `begin` (media time), or `hold` from now.
    func start(at begin: CFTimeInterval? = nil) {
        startedWidth = bounds.width
        text.removeAnimation(forKey: Self.animationKey)
        fade.removeAnimation(forKey: Self.animationKey)
        let room = bounds.width
        let overflow = textSize.width - room
        let y = ((bounds.height - textSize.height) / 2).rounded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard overflow > 0.5, room > 2 * Self.fadeWidth else {
            layer?.mask = nil
            text.frame = CGRect(origin: CGPoint(x: ((room - textSize.width) / 2).rounded(), y: y), size: textSize)
            return
        }
        // Each edge fades while the title goes on past it: at first the end, at last the start.
        let edge = NSNumber(value: Double(Self.fadeWidth / room))
        let opaque = NSColor.black.cgColor, clear = NSColor.clear.cgColor
        let first = [opaque, opaque, opaque, clear], middle = [clear, opaque, opaque, clear], last = [clear, opaque, opaque, opaque]
        fade.frame = bounds
        fade.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        fade.colors = last
        layer?.mask = fade
        text.frame = CGRect(origin: CGPoint(x: -overflow, y: y), size: textSize)
        guard window != nil else { return }

        let begin = begin ?? CACurrentMediaTime() + timing.hold
        let glide = timing.glide(overflow)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = 0
        move.toValue = -overflow
        move.beginTime = begin
        move.duration = glide
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        move.fillMode = .backwards
        text.add(move, forKey: Self.animationKey)

        let edges = CAKeyframeAnimation(keyPath: "colors")
        edges.values = [first, middle, middle, last]
        let ease = min(0.25, glide / 4) / glide
        edges.keyTimes = [0, NSNumber(value: ease), NSNumber(value: 1 - ease), 1]
        edges.beginTime = begin
        edges.duration = glide
        edges.fillMode = .backwards
        fade.add(edges, forKey: Self.animationKey)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        render()
        startedWidth = nil
        needsLayout = true
    }

    /// Lets go of the glide where it is.
    func stop() {
        text.removeAnimation(forKey: Self.animationKey)
        fade.removeAnimation(forKey: Self.animationKey)
    }

    /// `string` drawn into a bitmap `scale` times as large as `size`.
    static func image(of string: NSAttributedString, size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
