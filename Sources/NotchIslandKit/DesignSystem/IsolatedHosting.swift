import AppKit
import SwiftUI

/// A fixed-size piece of SwiftUI in a view graph of its own (a nested `NSHostingView`).
///
/// For a live view (ticking clocks, readings) inside a large, otherwise still one — Settings'
/// widget studio: in one graph, every tick of a clock in the studio ran an update and layout pass
/// over all of Settings (measured: ~2.5 % CPU while the Widgets pane sat open); in its own graph,
/// a tick updates only the studio.
///
/// The nested graph does not inherit the SwiftUI environment around it (the window's appearance
/// still applies): its content brings what it needs.
struct IsolatedHosting<Content: View>: NSViewRepresentable {
    let size: CGSize
    let content: Content

    init(size: CGSize, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        // Its size comes from here, never from its content.
        view.sizingOptions = []
        view.safeAreaRegions = []
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<Content>, context: Context) -> CGSize? {
        size
    }
}

/// SwiftUI in a view graph of its own that fills whatever it is given: a large surface (Settings)
/// whose graph — and every cache in it — goes when the surface closes.
struct IsolatedFillHosting<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.sizingOptions = []
        view.safeAreaRegions = []
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
