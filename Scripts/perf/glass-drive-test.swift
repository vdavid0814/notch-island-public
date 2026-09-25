import AppKit
import QuartzCore
import SwiftUI

// drive.swift <duration>: the glass resized every frame by our own display link along SwiftUI's own
// spring (Spring.value), its SwiftUI content kept at a fixed size and place.
let duration = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "0.4")!
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "frame"

final class Driver: NSObject {
    let glass: NSGlassEffectView, host: NSView, root: NSView
    var from = CGSize(width: 200, height: 32), to = CGSize(width: 200, height: 32)
    var start: CFTimeInterval = 0, spring = Spring(duration: 0.4, bounce: 0.22)
    var link: CADisplayLink?
    init(glass: NSGlassEffectView, host: NSView, root: NSView) { self.glass = glass; self.host = host; self.root = root }

    func go(to size: CGSize, opening: Bool) {
        from = current(); to = size
        spring = Spring(duration: duration, bounce: opening ? 0.22 : 0)
        start = CACurrentMediaTime()
        if link == nil { link = root.displayLink(target: self, selector: #selector(tick(_:))); link?.add(to: .main, forMode: .common) }
    }
    var shown = CGSize(width: 200, height: 32)
    func current() -> CGSize { shown }
    @objc func tick(_ l: CADisplayLink) {
        let t = CACurrentMediaTime() - start
        let delta = AnimatablePair(to.width - from.width, to.height - from.height)
        let v = spring.value(target: delta, time: t)
        shown = CGSize(width: from.width + v.first, height: from.height + v.second)
        let b = root.bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glass.frame = NSRect(x: b.midX - shown.width / 2, y: b.maxY - shown.height, width: shown.width, height: shown.height + 24)
        // The content stays where it is on screen: move it against the glass's origin.
        if mode == "bounds" {
            glass.contentView?.setBoundsOrigin(NSPoint(x: glass.frame.minX, y: glass.frame.minY - (b.maxY - host.frame.height)))
        } else {
            host.setFrameOrigin(NSPoint(x: -glass.frame.minX, y: b.maxY - host.frame.height - glass.frame.minY))
        }
        CATransaction.commit()
        // As the app's LeanSpring: done once within 0.3 % of the distance travelled.
        let distance = (delta.first * delta.first + delta.second * delta.second).squareRoot()
        let end = min(spring.settlingDuration(target: delta, epsilon: max(distance, 0.0001) * 0.003), spring.duration * 4)
        if t > end { l.invalidate(); link = nil }
    }
}

final class App: NSObject, NSApplicationDelegate {
    var win: NSWindow!, driver: Driver!
    func applicationDidFinishLaunching(_ n: Notification) {
        let screen = NSScreen.main!.frame
        let frame = NSRect(x: screen.midX - 360, y: screen.maxY - 300, width: 720, height: 260)
        win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar; win.backgroundColor = .clear; win.isOpaque = false; win.hasShadow = false
        win.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size)); root.wantsLayer = true
        win.contentView = root
        let glass = NSGlassEffectView(frame: .zero)
        glass.style = .clear; glass.tintColor = NSColor.black.withAlphaComponent(0.62); glass.cornerRadius = 30
        let container = NSView()
        let host = NSHostingView(rootView: GlassEffectContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("5:00").font(.system(size: 44, design: .rounded)).foregroundStyle(.orange)
                Text("Secondary label").foregroundStyle(.secondary)
                HStack { Button("Start Timer") {}.buttonStyle(.glassProminent); Button {} label: { Image(systemName: "xmark") }.buttonStyle(.glass) }
            }.padding(24).frame(width: 720, height: 240, alignment: .topLeading)
        }.environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 240)
        host.autoresizingMask = []
        host.sizingOptions = []
        container.autoresizesSubviews = false
        container.addSubview(host)
        glass.contentView = container
        root.addSubview(glass)
        driver = Driver(glass: glass, host: host, root: root)
        win.orderFrontRegardless()
        var open = false
        Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
            MainActor.assumeIsolated {
                open.toggle()
                self.driver.go(to: open ? CGSize(width: 640, height: 200) : CGSize(width: 200, height: 32), opening: open)
            }
        }
    }
}
let app = NSApplication.shared
let d = App(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()
