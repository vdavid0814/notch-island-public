import AppKit
import Quartz

/// Quick Look for a file picked in Spotlight (Space or ⌘Y): the system's own preview panel, shown
/// over the island; `closed` is called when it goes.
@MainActor final class QuickLookPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreview()

    private var url: URL?
    private var closed: (() -> Void)?
    private var observer: (any NSObjectProtocol)?

    func show(_ url: URL, closed: @escaping () -> Void) {
        guard let panel = QLPreviewPanel.shared() else { return closed() }
        self.url = url
        self.closed = closed
        panel.dataSource = self
        panel.delegate = self
        // Above the island's panel, which floats over everything.
        panel.level = .popUpMenu
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished() }
            }
        }
    }

    private func finished() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        url = nil
        let closed = closed
        self.closed = nil
        closed?()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    /// Space and Esc close the preview, as in Finder.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Read here: an event is not handed across to the main actor's closure.
        let closes = event.type == .keyDown && (event.keyCode == 49 || event.keyCode == 53)
        guard closes else { return false }
        MainActor.assumeIsolated { QLPreviewPanel.shared()?.close() }
        return true
    }
}
