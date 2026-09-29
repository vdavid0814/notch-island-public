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
///
/// The content is handed to its graph again only when `input` (all it takes from outside besides
/// the model it observes itself) changes: the view around it updates with every change of the
/// island (its presentation, its layout), and each new root view had the whole nested graph
/// compared and updated.
struct IsolatedFillHosting<Input: Equatable, Content: View>: NSViewRepresentable {
    let input: Input
    let content: Content

    init(input: Input, @ViewBuilder content: () -> Content) {
        self.input = input
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        context.coordinator.input = input
        let view = NSHostingView(rootView: content)
        view.sizingOptions = []
        view.safeAreaRegions = []
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        guard context.coordinator.input != input else { return }
        context.coordinator.input = input
        view.rootView = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The input the content was last built from.
    final class Coordinator {
        var input: Input?
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
