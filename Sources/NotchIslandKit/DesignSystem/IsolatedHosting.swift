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
///
/// Like `IsolatedFillHosting`, the content is handed to its graph again only when `input` (all it
/// takes from outside besides the models it observes itself) changes: every other update of the
/// view around it had the whole nested graph compared and updated for nothing.
struct IsolatedHosting<Input: Equatable, Content: View>: NSViewRepresentable {
    let size: CGSize
    let input: Input
    let content: Content

    init(size: CGSize, input: Input, @ViewBuilder content: () -> Content) {
        self.size = size
        self.input = input
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        context.coordinator.input = input
        let view = DeferringHostingView(rootView: content)
        // Its size comes from here, never from its content.
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
    /// Fades in over this long as it first appears (`fadeInOnRenderServer`).
    var fadeIn: TimeInterval?
    /// A picture: clicks, hover and tooltips go to the view around it.
    var isPicture = false
    let content: Content

    init(input: Input, fadeIn: TimeInterval? = nil, isPicture: Bool = false, @ViewBuilder content: () -> Content) {
        self.input = input
        self.fadeIn = fadeIn
        self.isPicture = isPicture
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        context.coordinator.input = input
        let view = isPicture ? PictureHostingView(rootView: content) : DeferringHostingView(rootView: content)
        view.sizingOptions = []
        view.safeAreaRegions = []
        if let fadeIn { view.fadeInOnRenderServer(duration: fadeIn) }
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

/// A hosting view that is only looked at: hit testing passes it by, so the view around it keeps its
/// clicks, hover and tooltips.
private final class PictureHostingView<Content: View>: DeferringHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A hosting view that lays nothing out while it is not seen: hidden (it or a view around it), or
/// in a window that is ordered out. Settings keeps its pages (`SettingsWindow`), and what they show
/// live — the widget gallery's previews and the stage read the volume, the brightness, the battery,
/// the music — was laid out again at every change while Settings was closed (a volume banner cost
/// ~70 ms more of main thread, measured). The layout it put off runs once it is seen again.
class DeferringHostingView<Content: View>: NSHostingView<Content> {
    private var deferredLayout = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Laid out even while unseen (building a page ahead of its first showing).
    var forcesLayout = false

    override func layout() {
        if !forcesLayout, let window, isHiddenOrHasHiddenAncestor || !window.isVisible {
            deferredLayout = true
            DeferredLayouts.views.add(self)
            return
        }
        deferredLayout = false
        super.layout()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        if deferredLayout { needsLayout = true }
    }
}

/// The hosting views that put a layout off while their window was ordered out.
@MainActor enum DeferredLayouts {
    static let views = NSHashTable<NSView>.weakObjects()

    /// `window` is about to be ordered in: whatever was put off in it is laid out with it.
    static func resume(in window: NSWindow) {
        for view in views.allObjects where view.window === window {
            view.needsLayout = true
            views.remove(view)
        }
    }
}

extension NSView {
    /// Fades the view in from the frame it is first shown in, on the render server: the ease-out
    /// of SwiftUI's `.easeOut(duration:)` (the same curve), with nothing to do on the main thread.
    /// A SwiftUI opacity transition on a nested host updated the whole view around it at every
    /// frame of the fade, and the sixteen staggered previews of the widget gallery kept Settings
    /// redrawing for most of a second (measured: about half the CPU of opening Widgets).
    func fadeInOnRenderServer(duration: TimeInterval) {
        wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // `demo/freeze`: held at that moment of the fade.
        if let frozen = LeanSpring.frozenTime {
            fade.speed = 0
            fade.timeOffset = min(frozen, duration)
            fade.fillMode = .both
            fade.isRemovedOnCompletion = false
        }
        layer?.add(fade, forKey: Self.fadeInKey)
    }

    static let fadeInKey = "fadeIn"
}
