import AppKit
import AVFoundation

/// The movie just saved, as macOS shows its own recordings: a small picture of its first frame in
/// the screen's lower-right corner that slides in, stays a few seconds (as long as the pointer is
/// on it) and slides out. A click opens the movie; dragged to the right it goes at once; dragged
/// anywhere else it is the file, to drop in a folder or a message. Its menu is the native one's:
/// Save to Desktop or Documents (moved there), Open in Mail, QuickTime Player or Photos, Show in
/// Finder, Delete (to the Trash), Markup (QuickTime Player's Trim: macOS offers no editor of its own
/// to other apps) and Close.
///
/// A panel of its own that never takes the keyboard (the app in front keeps it), above the windows,
/// on every Space. macOS draws its own only for what its Screenshot app records.
@MainActor final class RecordingThumbnail {
    /// How long it stays without the pointer on it.
    static let duration: Duration = .seconds(5)
    nonisolated static let width: CGFloat = 240
    /// From the screen's visible edges (above the Dock).
    static let margin: CGFloat = 18

    private var panel: NSPanel?
    private var view: ThumbnailView?
    private var url: URL?
    private var timeout: Task<Void, Never>?
    private var generation = 0

    /// Shows `url`'s first frame on `display`'s screen (the main one when unknown).
    func show(_ url: URL, display: CGDirectDisplayID?) {
        generation += 1
        let generation = generation
        Task { [weak self] in
            guard let image = await Self.firstFrame(of: url) else {
                Log.recording.notice("no picture of \(url.lastPathComponent, privacy: .public)")
                return
            }
            guard let self, self.generation == generation else { return }
            self.present(image, url: url, screen: Self.screen(for: display))
        }
    }

    /// Goes at once (a new recording starts, the movie was taken elsewhere).
    func dismiss(animated: Bool = true) {
        timeout?.cancel()
        timeout = nil
        guard let panel else { return }
        self.panel = nil
        view = nil
        url = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        var gone = panel.frame
        gone.origin.x = (panel.screen ?? NSScreen.main)?.frame.maxX ?? gone.maxX
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(gone, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func present(_ image: CGImage, url: URL, screen: NSScreen?) {
        dismiss(animated: false)
        guard let screen else { return }
        let ratio = CGFloat(image.height) / CGFloat(max(image.width, 1))
        let size = CGSize(width: Self.width, height: (Self.width * ratio).rounded())
        let visible = screen.visibleFrame
        let rest = CGRect(x: visible.maxX - Self.margin - size.width, y: visible.minY + Self.margin,
                          width: size.width, height: size.height)
        let panel = NSPanel(contentRect: rest, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = ThumbnailView(frame: CGRect(origin: .zero, size: size), image: image, url: url)
        view.onAction = { [weak self] action in self?.perform(action) }
        view.onDragEnded = { [weak self] dropped in
            guard let self else { return }
            if dropped {
                self.dismiss(animated: false)
            } else {
                self.panel?.alphaValue = 1
                self.scheduleTimeout()
            }
        }
        view.onDragBegan = { [weak self] in
            self?.timeout?.cancel()
            self?.panel?.alphaValue = 0
        }
        view.onHover = { [weak self] inside in
            if inside { self?.timeout?.cancel() } else { self?.scheduleTimeout() }
        }
        panel.contentView = view
        self.panel = panel
        self.view = view
        self.url = url
        // In from the screen's right edge.
        var start = rest
        start.origin.x = screen.frame.maxX
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(rest, display: true)
        }
        scheduleTimeout()
    }

    // MARK: The menu

    nonisolated enum Action: Sendable {
        case open, saveToDesktop, saveToDocuments, mail, quickTime, photos, showInFinder, delete, markup, close
    }

    static let quickTimeApp = URL(fileURLWithPath: "/System/Applications/QuickTime Player.app")
    static let photosApp = URL(fileURLWithPath: "/System/Applications/Photos.app")

    private func perform(_ action: Action) {
        guard let url else { return }
        switch action {
        case .open:
            NSWorkspace.shared.open(url)
        case .saveToDesktop, .saveToDocuments:
            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(action == .saveToDesktop ? "Desktop" : "Documents", isDirectory: true)
            if Self.move(url, to: folder) == nil {
                // Not allowed to the app itself (the movie was written by the system for it, in a
                // folder macOS keeps from the app): Finder moves it.
                Self.finder("move (POSIX file \(Self.quoted(url.path)) as alias) to (POSIX file \(Self.quoted(folder.path)) as alias)")
            }
        case .mail:
            NSSharingService(named: .composeEmail)?.perform(withItems: [url])
        case .quickTime:
            Self.open(url, with: Self.quickTimeApp)
        case .photos:
            Self.open(url, with: Self.photosApp)
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .delete:
            // The file manager's own move to the Trash: `NSWorkspace.recycle` was refused for a movie
            // the app had just written to the Desktop ("no permission to move it to the Trash").
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                Log.recording.notice("moved to the Trash")
            } catch {
                // macOS keeps the folder from the app (the movie was written by the system for it):
                // Finder puts it in the Trash.
                Log.recording.notice("trash refused (\(error.localizedDescription, privacy: .public)): asking Finder")
                Self.finder("delete (POSIX file \(Self.quoted(url.path)) as alias)")
            }
        case .markup:
            Self.trimInQuickTime(url)
        case .close:
            break
        }
        dismiss()
    }

    /// Into `folder` under its own name ("… 2" if one is there already); where it is, it stays.
    static func move(_ url: URL, to folder: URL) -> URL? {
        guard url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { return url }
        let name = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var target = folder.appendingPathComponent(url.lastPathComponent)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(name) \(number).\(ext)")
            number += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            Log.recording.notice("moved to \(folder.lastPathComponent, privacy: .public)")
            return target
        } catch {
            Log.recording.error("could not move: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `command` sent to Finder (`tell application "Finder" to …`), off the main thread: macOS asks
    /// once whether the app may control Finder.
    private static func finder(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to \(command)"]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            let why = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Log.recording.error("Finder could not: \(why, privacy: .public)")
        }
        do { try process.run() } catch {
            Log.recording.error("could not ask Finder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `text` as an AppleScript string.
    nonisolated static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func open(_ url: URL, with app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
            if let error { Log.recording.error("could not open: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Opens the movie in QuickTime Player and, once it is in front, its Trim (⌘T) — with
    /// Accessibility, which posting the keystroke needs; without it the movie only opens.
    private static func trimInQuickTime(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: quickTimeApp, configuration: configuration) { app, _ in
            guard let pid = app?.processIdentifier, AXIsProcessTrusted() else { return }
            Task { @MainActor in
                // The document window takes a moment to open.
                try? await Task.sleep(for: .milliseconds(900))
                let source = CGEventSource(stateID: .hidSystemState)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0x11, keyDown: down) // T
                    event?.flags = .maskCommand
                    event?.postToPid(pid)
                }
            }
        }
    }

    private func scheduleTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private static func screen(for display: CGDirectDisplayID?) -> NSScreen? {
        let match = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }
        return match ?? NSScreen.main
    }

    /// The movie's first frame, as large as the thumbnail needs on a Retina screen.
    nonisolated private static func firstFrame(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width * 2, height: width * 2)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        return try? await generator.image(at: .zero).image
    }
}

/// The picture with the native thumbnail's rounded corners and faint rim; it reads the pointer
/// itself: a click opens, a drag to the right dismisses, any other drag is the file.
private final class ThumbnailView: NSView, NSDraggingSource {
    var onAction: ((RecordingThumbnail.Action) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    var onHover: ((Bool) -> Void)?

    private let image: CGImage
    private let url: URL
    private var pressedAt: CGPoint?
    private var restingX: CGFloat = 0
    private var isSwiping = false
    private var isDraggingFile = false

    /// Past this many points a press is a drag.
    static let dragThreshold: CGFloat = 4
    /// Dragged this far to the right, it is let go.
    static let swipeDistance: CGFloat = 40

    init(frame: CGRect, image: CGImage, url: URL) {
        self.image = image
        self.url = url
        super.init(frame: frame)
        wantsLayer = true
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resizeAspectFill
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        self.layer = layer
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(url.deletingPathExtension().lastPathComponent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { if !isDraggingFile { onHover?(false) } }

    override func mouseDown(with event: NSEvent) {
        pressedAt = NSEvent.mouseLocation
        restingX = window?.frame.minX ?? 0
        isSwiping = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressedAt, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - pressedAt.x, dy = now.y - pressedAt.y
        if !isSwiping, !isDraggingFile, hypot(dx, dy) >= Self.dragThreshold {
            if dx > 0, abs(dx) > abs(dy) {
                isSwiping = true
            } else {
                beginFileDrag(event)
                return
            }
        }
        if isSwiping {
            var frame = window.frame
            frame.origin.x = restingX + max(0, dx)
            window.setFrame(frame, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil }
        guard let pressedAt else { return }
        if isSwiping {
            isSwiping = false
            if NSEvent.mouseLocation.x - pressedAt.x >= Self.swipeDistance {
                onAction?(.close)
            } else if let window {
                var frame = window.frame
                frame.origin.x = restingX
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    window.animator().setFrame(frame, display: true)
                }
            }
            return
        }
        guard !isDraggingFile, event.clickCount >= 1 else { return }
        onAction?(.open)
    }

    /// A two-finger swipe to the right lets it go too.
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas, event.scrollingDeltaX < -6, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            onAction?(.close)
        }
    }

    /// As the native thumbnail's menu, in its order.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let groups: [[(String, RecordingThumbnail.Action)]] = [
            [(String(localized: "Save to Desktop"), .saveToDesktop), (String(localized: "Save to Documents"), .saveToDocuments)],
            [(String(localized: "Open in Mail"), .mail), (String(localized: "Open in QuickTime Player"), .quickTime),
             (String(localized: "Open in Photos"), .photos)],
            [(String(localized: "Show in Finder"), .showInFinder), (String(localized: "Delete"), .delete)],
            [(String(localized: "Markup"), .markup), (String(localized: "Close"), .close)],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for (title, action) in group {
                let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ActionBox(action)
                menu.addItem(item)
            }
        }
        onHover?(true)
        return menu
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        onHover?(false)
    }

    @objc private func choose(_ item: NSMenuItem) {
        if let box = item.representedObject as? ActionBox { onAction?(box.action) }
    }

    private func beginFileDrag(_ event: NSEvent) {
        isDraggingFile = true
        onDragBegan?()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Into a folder it moves, as the native thumbnail's file does; into an app it is copied.
        context == .outsideApplication ? [.copy, .move] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingFile = false
        pressedAt = nil
        onDragEnded?(operation != [])
    }
}

/// A menu item's action, as its `representedObject`.
private final class ActionBox: NSObject {
    let action: RecordingThumbnail.Action
    init(_ action: RecordingThumbnail.Action) { self.action = action }
}
