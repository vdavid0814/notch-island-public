import AppKit
import QuartzCore
import SwiftUI

// freeze.swift <mode: freeze|static> <fraction 0…1>
// freeze: a linear Core Animation of the glass view's layer from small to large, stopped at `fraction`.
// static: the glass view simply laid out at the interpolated frame (the reference).
let mode = CommandLine.arguments[1]
let t = Double(CommandLine.arguments[2])!

final class Checker: NSView {
    override func draw(_ r: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setFill()
        let s: CGFloat = 16
        for y in stride(from: 0, to: bounds.height, by: s) { for x in stride(from: 0, to: bounds.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 { NSRect(x: x, y: y, width: s, height: s).fill() } }
        NSColor.systemPink.setFill(); NSRect(x: 100, y: 60, width: 520, height: 40).fill()
    }
}

final class App: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ n: Notification) {
        let screen = NSScreen.main!.frame
        let frame = NSRect(x: screen.midX - 360, y: screen.maxY - 300, width: 720, height: 260)
        let back = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        back.level = .statusBar; back.contentView = Checker(); back.orderFrontRegardless()
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        win.backgroundColor = .clear; win.isOpaque = false; win.hasShadow = false
        win.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size)); root.wantsLayer = true
        win.contentView = root
        windows = [back, win]
        let small = NSRect(x: 260, y: 160, width: 200, height: 100 + 24)
        let large = NSRect(x: 40, y: 20, width: 640, height: 240 + 24)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let mid = NSRect(x: lerp(small.minX, large.minX), y: lerp(small.minY, large.minY),
                         width: lerp(small.width, large.width), height: lerp(small.height, large.height))
        if mode == "full" || mode == "hybrid" || mode == "hybridIn" {
            // Island-like content: a big readout, a line of text and two glass buttons.
            let content = VStack(alignment: .leading, spacing: 10) {
                Text("5:00").font(.system(size: 44, weight: .regular, design: .rounded)).foregroundStyle(.orange)
                Text("Secondary label").foregroundStyle(.secondary)
                HStack {
                    Button("Start Timer") {}.buttonStyle(.glassProminent).tint(.orange)
                    Button { } label: { Image(systemName: "xmark") }.buttonStyle(.glass).buttonBorderShape(.circle)
                }
            }
            .padding(24)
            .frame(width: mid.width, height: mid.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            if mode == "full" {
                // Today: the content inside the surface's glass, one container for everything.
                let host = NSHostingView(rootView: GlassEffectContainer {
                    content.glassEffect(.clear.tint(Color.black.opacity(0.62)), in: .rect(cornerRadius: 30, style: .continuous))
                })
                host.frame = mid
                root.addSubview(host)
            } else {
                let glass = NSGlassEffectView(frame: mid)
                glass.style = .clear
                glass.tintColor = NSColor.black.withAlphaComponent(0.62)
                glass.cornerRadius = 30
                let host = NSHostingView(rootView: GlassEffectContainer { content })
                if mode == "hybridIn" {
                    // The content as the glass view's own content.
                    host.frame = glass.bounds
                    glass.contentView = host
                    root.addSubview(glass)
                } else {
                    // The content above the glass, a sibling.
                    host.frame = mid
                    root.addSubview(glass)
                    root.addSubview(host)
                }
            }
            win.orderFrontRegardless()
            return
        }
        if mode == "swiftui" {
            // The same glass the island draws: SwiftUI's clear glass with the island's smoke.
            let host = NSHostingView(rootView: Color.clear
                .glassEffect(.clear.tint(Color.black.opacity(0.62)), in: .rect(cornerRadius: 30, style: .continuous))
                .frame(width: mid.width, height: mid.height))
            host.frame = mid
            root.addSubview(host)
            win.orderFrontRegardless()
            return
        }
        let glass = NSGlassEffectView(frame: mode == "static" ? mid : large)
        glass.style = .clear
        glass.tintColor = NSColor.black.withAlphaComponent(0.62)
        glass.cornerRadius = 30
        root.addSubview(glass)
        win.orderFrontRegardless()
        if mode == "mask" {
            // The glass stays at its largest; a mask cut to the in-between outline shows only that much.
            let mask = CAShapeLayer()
            let local = NSRect(x: mid.minX - large.minX, y: mid.minY - large.minY, width: mid.width, height: mid.height)
            mask.path = CGPath(roundedRect: local, cornerWidth: 30, cornerHeight: 30, transform: nil)
            glass.wantsLayer = true
            glass.layer!.mask = mask
        }
        if mode == "freeze" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let layer = glass.layer!
                for (key, from, to) in [("bounds", NSValue(rect: NSRect(origin: .zero, size: small.size)), NSValue(rect: NSRect(origin: .zero, size: large.size))),
                                        ("position", NSValue(point: small.origin), NSValue(point: large.origin))] {
                    let a = CABasicAnimation(keyPath: key)
                    a.fromValue = from; a.toValue = to; a.duration = 1
                    a.fillMode = .both; a.isRemovedOnCompletion = false
                    a.speed = 0; a.timeOffset = t
                    layer.add(a, forKey: key)
                }
            }
        }
    }
}
let app = NSApplication.shared
let d = App(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()
