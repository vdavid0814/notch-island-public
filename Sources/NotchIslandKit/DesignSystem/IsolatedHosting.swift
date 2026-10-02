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
    /// In Settings: out of the window while Settings is closed (`DeferringHostingView`).
    var pausesWithSettings = false
    let content: Content

    init(size: CGSize, input: Input, pausesWithSettings: Bool = false, @ViewBuilder content: () -> Content) {
        self.size = size
        self.input = input
        self.pausesWithSettings = pausesWithSettings
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        context.coordinator.input = input
        let view = DeferringHostingView(rootView: content)
        view.pausesWithSettings = pausesWithSettings
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
    /// In Settings: out of the window while Settings is closed (`DeferringHostingView`).
    var pausesWithSettings = false
    let content: Content

    init(input: Input, fadeIn: TimeInterval? = nil, isPicture: Bool = false, pausesWithSettings: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.input = input
        self.fadeIn = fadeIn
        self.isPicture = isPicture
        self.pausesWithSettings = pausesWithSettings
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        context.coordinator.input = input
        let view: DeferringHostingView<Content> = isPicture ? PictureHostingView(rootView: content) : DeferringHostingView(rootView: content)
        view.pausesWithSettings = pausesWithSettings
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

/// A hosting view that lays nothing out while it is hidden (it or a view around it): Settings keeps
/// the pages not shown hidden (`SettingsPageDeckView`), and a change around them laid them out —
/// their nested previews too — for nothing. The layout it put off runs once it shows again.
class DeferringHostingView<Content: View>: NSHostingView<Content> {
    private var deferredLayout = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Laid out even while hidden (building a page ahead of its first showing).
    var forcesLayout = false

    override func layout() {
        if !forcesLayout, window != nil, isHiddenOrHasHiddenAncestor {
            deferredLayout = true
            return
        }
        deferredLayout = false
        super.layout()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        if deferredLayout { needsLayout = true }
    }

    /// Taken out of its superview while Settings is closed and put back as it opens
    /// (`SettingsPresence`): Settings is kept, and a live picture in it (the widget gallery's
    /// previews, the studio's island) followed the models it reads unseen — a volume change, a
    /// timer finishing — and redrew. Out of the window, it does nothing.
    var pausesWithSettings = false {
        didSet {
            guard pausesWithSettings != oldValue else { return }
            presenceObserver = pausesWithSettings ? NotificationCenter.default.addObserver(
                forName: SettingsPresence.didChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.followPresence() }
            } : nil
        }
    }

    private var presenceObserver: (any NSObjectProtocol)?
    private weak var pausedIn: NSView?

    private func followPresence() {
        if SettingsPresence.shared.isShown {
            guard let container = pausedIn, superview == nil else { return }
            pausedIn = nil
            frame = container.bounds
            container.addSubview(self)
            container.needsLayout = true
        } else {
            guard let container = superview, pausedIn == nil else { return }
            pausedIn = container
            removeFromSuperview()
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
