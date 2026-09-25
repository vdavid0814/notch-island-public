import AppKit
// A still checkerboard with a few colour blocks over the top 800 pt of the main screen, just under
// the island (status-bar level, clicks pass through), so screenshots of the island compare exactly.
final class Checker: NSView {
    override func draw(_ r: NSRect) {
        NSColor.white.setFill(); bounds.fill(); NSColor.black.setFill()
        let s: CGFloat = 16
        for y in stride(from: 0, to: bounds.height, by: s) { for x in stride(from: 0, to: bounds.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 { NSRect(x: x, y: y, width: s, height: s).fill() } }
        NSColor.systemPink.setFill(); NSRect(x: bounds.midX - 260, y: bounds.maxY - 120, width: 520, height: 30).fill()
        NSColor.systemBlue.setFill(); NSRect(x: bounds.midX - 340, y: bounds.maxY - 230, width: 80, height: 200).fill()
        NSColor.systemYellow.setFill(); NSRect(x: bounds.midX + 200, y: bounds.maxY - 60, width: 120, height: 50).fill()
    }
}
final class App: NSObject, NSApplicationDelegate {
    var w: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let s = NSScreen.screens[0].frame
        w = NSWindow(contentRect: NSRect(x: s.minX, y: s.maxY - 800, width: s.width, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .statusBar; w.contentView = Checker(); w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.orderFrontRegardless()
    }
}
let app = NSApplication.shared; let d = App(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()
