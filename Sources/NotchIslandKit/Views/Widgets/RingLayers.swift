import SwiftUI

/// `ProgressRing` as Core Animation layers, for a ring that moves at every reading (Fan Control's
/// dials): the track and the fill are one arc each (`strokeEnd` is how far it is filled), the bead
/// or the knob a layer of its own — and a new value glides there on the render server, its colour
/// too, nothing done on the main thread between readings. As SwiftUI's animation the fill's glide
/// was 600 ms of the main thread in 0.8 s for one change (a debug build); on the island, Fan Control
/// open: the app 16.9 → 4.1 mW, 55 → 21 ms of CPU a second (ENERGY-LOG, Oct 13).
///
/// Drawn as `ProgressRing` draws the same look: its metrics, its round or sharp ends, its knob.
/// Rounded ends (corners of their own) cannot be a stroke's: `supports` says which looks it draws,
/// and the others stay `ProgressRing`'s. Live rings only — a picture (`ImageRenderer`) draws no
/// layers of a view.
struct RingLayers: NSViewRepresentable {
    let fraction: Double
    let diameter: CGFloat
    let line: CGFloat
    var look: ProgressLook = .plain
    var start: Double = -90
    var sweep: Double = 360
    var automaticTrack: Color = .white.opacity(0.16)
    var minimumFill: Double = 0
    var automaticFill: Color
    var knobAt: Double?
    var forcesKnob = false
    var animatesKnob = true
    var bead: Color?
    /// How long a new value takes to glide there.
    var duration: Double = 0.6

    @Environment(AppModel.self) private var model: AppModel?

    /// The looks drawn as layers: all but rounded ends.
    static func supports(_ look: ProgressLook) -> Bool { look.ends != .rounded }

    func makeNSView(context: Context) -> RingLayerView { RingLayerView() }

    func updateNSView(_ view: RingLayerView, context: Context) {
        let metrics = ProgressRing.metrics(diameter: diameter, line: line, look: look)
        let filled = min(max(fraction, 0), 1)
        let knob = look.knob.size(height: metrics.line) ?? (forcesKnob ? ProgressLook.Knob.circle.size(height: metrics.line) : nil)
        view.show(RingLayerView.Ring(
            box: diameter, drawn: metrics.diameter, thickness: metrics.line,
            offset: CGPoint(x: look.barOffset.x, y: look.barOffset.y), start: start, sweep: sweep, round: look.ends == .round,
            track: cgColor(look.trackColor, automaticTrack), fill: cgColor(look.fillColor, automaticFill),
            filled: look.ends == .round ? max(filled, minimumFill) : filled,
            bead: knob == nil ? bead.map { NSColor($0).cgColor } : nil, beadAt: filled,
            knob: knob, knobRadius: knob.map { (forcesKnob && look.knob == .base ? .circle : look.knob).radius(size: $0) } ?? 0,
            knobAt: min(max(knobAt ?? filled, 0), 1), animatesKnob: animatesKnob), duration: duration)
    }

    /// The look's colour where it picked one, else the ring's own.
    private func cgColor(_ color: TextStyle.TextColor, _ automatic: Color) -> CGColor {
        switch color {
        case .automatic: NSColor(automatic).cgColor
        case .custom(let rgb): NSColor(rgb.color).cgColor
        case .artwork: NSColor(model?.media.artworkColor.map { Color($0) } ?? .islandAccent).cgColor
        }
    }
}

final class RingLayerView: NSView {
    struct Ring: Equatable {
        /// The room's side, and the ring's own diameter and thickness in it.
        var box: CGFloat
        var drawn: CGFloat
        var thickness: CGFloat
        var offset: CGPoint
        var start: Double
        var sweep: Double
        var round: Bool
        var track: CGColor
        var fill: CGColor
        var filled: Double
        var bead: CGColor?
        var beadAt: Double
        var knob: CGSize?
        var knobRadius: CGFloat
        var knobAt: Double
        var animatesKnob: Bool
    }

    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let bead = CAShapeLayer()
    private let knob = CALayer()
    private var ring: Ring?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        for shape in [track, fill] {
            shape.fillColor = nil
            shape.strokeStart = 0
        }
        bead.strokeColor = CGColor(gray: 0, alpha: 0.85)
        knob.backgroundColor = CGColor(gray: 1, alpha: 1)
        knob.shadowColor = CGColor(gray: 0, alpha: 1)
        knob.shadowOpacity = 0.3
        knob.shadowRadius = 1.5
        knob.shadowOffset = CGSize(width: 0, height: 0.5)
        for sublayer in [track, fill, bead, knob] as [CALayer] {
            sublayer.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "path": NSNull(), "strokeEnd": NSNull(),
                                "strokeColor": NSNull(), "fillColor": NSNull(), "lineWidth": NSNull(), "lineCap": NSNull(),
                                "transform": NSNull(), "hidden": NSNull(), "cornerRadius": NSNull()]
            layer?.addSublayer(sublayer)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// Drags and clicks go to the dial around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The ring's middle and radius (the stroke's middle line) in the view.
    private func circle(_ ring: Ring) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: ring.box / 2 + ring.offset.x, y: ring.box / 2 + ring.offset.y), (ring.drawn - ring.thickness) / 2)
    }

    private func point(_ ring: Ring, at fraction: Double) -> CGPoint {
        let (center, radius) = circle(ring)
        let angle = (ring.start + ring.sweep * fraction) * .pi / 180
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    /// The arc from `from` to `to` of the sweep (either way round), for a glide along it.
    private func arc(_ ring: Ring, from: Double, to: Double) -> CGPath {
        let (center, radius) = circle(ring)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: (ring.start + ring.sweep * from) * .pi / 180,
                    endAngle: (ring.start + ring.sweep * to) * .pi / 180, clockwise: to < from)
        return path
    }

    func show(_ new: Ring, duration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let old = ring
        ring = new
        let geometryChanged = old.map { $0.box != new.box || $0.drawn != new.drawn || $0.thickness != new.thickness
            || $0.offset != new.offset || $0.start != new.start || $0.sweep != new.sweep || $0.round != new.round } ?? true

        if geometryChanged {
            let whole = arc(new, from: 0, to: 1)
            for shape in [track, fill] {
                shape.frame = bounds
                shape.path = whole
                shape.lineWidth = new.thickness
                shape.lineCap = new.round ? .round : .butt
            }
            track.strokeEnd = 1
        }
        track.strokeColor = new.track

        // The fill: from where it is now (a glide under way too) to the new value, its colour with it.
        let glides = !geometryChanged && duration > 0
        if glides, old?.filled != new.filled {
            let was = Double(fill.presentation()?.strokeEnd ?? fill.strokeEnd)
            let glide = CABasicAnimation(keyPath: "strokeEnd")
            glide.fromValue = was
            glide.toValue = new.filled
            glide.duration = duration
            glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fill.add(glide, forKey: "glide")
        }
        if glides, let old, old.fill != new.fill {
            let tint = CABasicAnimation(keyPath: "strokeColor")
            tint.fromValue = fill.presentation()?.strokeColor ?? old.fill
            tint.toValue = new.fill
            tint.duration = duration
            fill.add(tint, forKey: "tint")
        }
        fill.strokeEnd = new.filled
        fill.strokeColor = new.fill
        // Nothing filled: no stroke at all (a round end would leave a dot).
        fill.isHidden = new.filled <= 0

        // The bead at the fill's end, gliding along the arc with it.
        if let color = new.bead, new.beadAt > 0.005 {
            let side = new.thickness * 1.43
            bead.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            bead.path = CGPath(ellipseIn: bead.bounds, transform: nil)
            bead.lineWidth = new.thickness * 0.29
            bead.fillColor = color
            let wasShown = !bead.isHidden
            bead.isHidden = false
            bead.position = point(new, at: new.beadAt)
            if glides, wasShown, let old, old.beadAt != new.beadAt {
                let from = Double(fill.presentation()?.strokeEnd ?? CGFloat(old.beadAt))
                glide(bead, along: arc(new, from: from, to: new.beadAt), duration: duration)
            }
        } else {
            bead.isHidden = true
        }

        // The knob: where the fans are held (or the look's, at the fill's end), white, lying on the ring.
        if let size = new.knob {
            knob.bounds = CGRect(origin: .zero, size: size)
            knob.cornerRadius = new.knobRadius
            let wasShown = !knob.isHidden
            knob.isHidden = false
            let angle = (new.start + new.sweep * new.knobAt + 90) * .pi / 180
            knob.position = point(new, at: new.knobAt)
            knob.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            if new.animatesKnob, wasShown, !geometryChanged, let old, old.knobAt != new.knobAt {
                glide(knob, along: arc(new, from: old.knobAt, to: new.knobAt), duration: 0.3)
                // Turned with it, to lie on the ring all the way.
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = (old.start + old.sweep * old.knobAt + 90) * .pi / 180
                turn.toValue = angle
                turn.duration = 0.3
                turn.timingFunction = CAMediaTimingFunction(name: .easeOut)
                knob.add(turn, forKey: "turn")
            } else {
                knob.removeAnimation(forKey: "glide")
                knob.removeAnimation(forKey: "turn")
            }
        } else {
            knob.isHidden = true
        }
    }

    /// `layer` moved along `path` on the render server, easing out.
    private func glide(_ layer: CALayer, along path: CGPath, duration: Double) {
        let glide = CAKeyframeAnimation(keyPath: "position")
        glide.path = path
        glide.calculationMode = .paced
        glide.duration = duration
        glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(glide, forKey: "glide")
    }
}
