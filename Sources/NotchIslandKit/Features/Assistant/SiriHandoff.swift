import AppKit

/// An Accessibility element handed to a background read (the AX calls are safe from any thread;
/// the type is not marked so).
nonisolated struct AXRef: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

/// "Use Siri AI": the question asked of the system's Siri AI and its answer shown in the island,
/// without the Siri app coming up — its features working: sending a message, changing a setting,
/// opening an app (asked for).
///
/// All through Accessibility, Siri AI hidden and never brought forward: in its conversation window
/// the New Conversation button is pressed, the question set into the Ask Siri field (read back to
/// be sure) and confirmed (`AXConfirm`, the field's own Return); Siri's reply is then read from the
/// window as it comes. Tried first and dropped: neither `siri://` nor `spotlight://` carries a
/// question; the system's Spotlight bar takes no synthetic keys or Return; typing into Siri AI's
/// window needed it in front, and coming forward AppKit pulled its window onto the screen for a
/// moment however far away it had been moved (seen), and handed the front to another app after.
@MainActor enum SiriHandoff {
    /// Siri AI.
    static let bundleIdentifier = "com.apple.campo"

    /// When the last question was handed over: a "reopen" macOS sends NotchIsland right after is
    /// not the user coming back to it (`AppDelegate`; seen while Siri AI was opened by URL).
    private(set) static var lastHandoff: Date?

    /// A question is being handed over.
    private static var isAsking = false

    /// A reopen now most likely comes from the handoff, not from the user: during it (reopening
    /// Siri AI in the background sent NotchIsland a string of them, seen) and for a while after.
    static var isSettling: Bool { isAsking || lastHandoff.map { Date().timeIntervalSince($0) < 6 } ?? false }

    /// Siri AI is installed and the island may use Accessibility.
    static var isAvailable: Bool {
        AXIsProcessTrusted() && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// The conversation's window, for a reply typed in the island and for Siri's buttons.
    private static var conversation: AXUIElement?

    /// Asks Siri AI `text` (`continuing`: in the conversation already open, a reply to Siri).
    /// `onReply` at each change of Siri's answer. False when it could not be asked: nothing is
    /// confirmed unless the field holds exactly the question.
    static func ask(_ text: String, continuing: Bool, onReply: @escaping @MainActor (SiriReply) -> Void) async -> Bool {
        let line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return false }
        isAsking = true
        defer {
            isAsking = false
            lastHandoff = Date()
        }
        var window: AXUIElement?
        let app = await siriApp()
        // Its window list is empty for a moment now and then (seen): once more after a pause.
        for attempt in 0..<2 where window == nil {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            if let app { window = await conversationWindow(of: app) }
        }
        guard let window else {
            Log.app.notice("siri handoff: no Siri AI window")
            return false
        }
        let continues = continuing && conversation.map { CFEqual($0, window) } == true
        conversation = window
        var before = await submit(line, in: window, newConversation: !continues)
        if before == nil {
            // A window just built unseen drops its first question (seen): once more, anew.
            before = await submit(line, in: window, newConversation: true)
        }
        Log.app.notice("siri handoff: asked \(before != nil, privacy: .public)")
        guard let before else { return false }
        await follow(window, after: before, previous: nil, onReply: onReply)
        return true
    }

    /// The question set into the Ask Siri field (`newConversation`: after New Conversation), read
    /// back, confirmed, and seen in the conversation as the user's prompt: Siri's replies there were
    /// before it. Nil when any of it did not happen.
    private static func submit(_ line: String, in window: AXUIElement, newConversation: Bool) async -> Int? {
        let old = descendants(of: window, where: { identifier($0) == "promptViewTextField" }).first
        if newConversation, let button = descendants(of: window, where: { identifier($0) == "newChatButton" }).first {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            // The new conversation builds its field anew: the old one, still there a moment, took
            // the question and dropped it (seen). Waited for the new one, then a little longer.
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(50))
                if let now = descendants(of: window, where: { identifier($0) == "promptViewTextField" }).first,
                   old.map({ !CFEqual($0, now) }) ?? true { break }
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        guard let field = await promptField(in: window) else { return nil }
        let prompts = descendants(of: window, where: { identifier($0) == "userPrompt" }).count
        let replied = replies(in: window).count
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, line as CFString)
        var held = false
        for _ in 0..<10 {
            if (attribute(field, kAXValueAttribute) as? String)?.trimmingCharacters(in: .whitespaces) == line { held = true; break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        guard held else { return nil }
        // The field's binding takes the value a moment after it is set.
        try? await Task.sleep(for: .milliseconds(300))
        guard AXUIElementPerformAction(field, kAXConfirmAction as CFString) == .success else { return nil }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if descendants(of: window, where: { identifier($0) == "userPrompt" }).count > prompts { return replied }
        }
        return nil
    }

    /// Does `action` to Siri's last reply in Siri AI (a button, a link, the message's text) and
    /// follows what Siri says to it. False when the part was not there or would not do it.
    static func perform(_ action: SiriAction, after previous: SiriReply,
                        onReply: @escaping @MainActor (SiriReply) -> Void) async -> Bool {
        guard let window = conversation else { return false }
        let ref = AXRef(window)
        let done = await Task.detached { () -> (Bool, Int) in
            let all = replies(in: ref.element)
            guard let last = all.last else { return (false, all.count) }
            switch action {
            case .button(let title):
                guard let button = AX.descendants(of: last, where: {
                    AX.role($0) == kAXButtonRole as String && (AX.description($0) ?? AX.attributedDescription($0)) == title
                }).last else { return (false, all.count) }
                return (AX.press(button), all.count)
            case .link(let title):
                guard let link = AX.descendants(of: last, where: { AX.role($0) == "AXLink" && AX.description($0) == title }).first
                else { return (false, all.count) }
                return (AX.press(link), all.count)
            case .composerText(let text):
                guard let field = AX.descendants(of: last, where: { AX.role($0) == kAXTextFieldRole as String }).first
                else { return (false, all.count) }
                return (AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success, all.count)
            }
        }.value
        guard done.0 else { return false }
        if case .composerText = action { return true }
        await follow(window, after: done.1 - 1, previous: previous, onReply: onReply)
        return true
    }

    /// The conversation in Siri AI itself, on the screen.
    static func reveal() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else { return }
        app.unhide()
        if let conversation { AXUIElementPerformAction(conversation, kAXRaiseAction as CFString) }
        app.activate()
    }

    /// Siri AI running, launched hidden and in the background if it was not.
    private static func siriApp() async -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first { return app }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        for _ in 0..<60 {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
               attribute(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute) != nil { return app }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// The conversation window: the one used last, or Siri AI's first. With none, one is opened
    /// unseen: a hidden Siri AI opens none (File ▸ New Conversation did nothing, seen), so it is
    /// reopened in the background, the menu item with ⌘N pressed, and it is hidden again as soon as
    /// the window is there (nothing seen on the screen, measured).
    private static func conversationWindow(of app: NSRunningApplication) async -> AXUIElement? {
        if let conversation, attribute(conversation, kAXRoleAttribute) != nil { return conversation }
        if let window = standardWindows(of: app).first { return window }
        // Reopened in the background (it has no window to show), not brought forward: hidden, or
        // only shown, it opened none for New Conversation (seen).
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try? await Task.sleep(for: .milliseconds(300))
        }
        if let window = standardWindows(of: app).first {
            app.hide()
            return window
        }
        guard newConversationFromMenu(of: app) else { return nil }
        for _ in 0..<120 {
            if let window = standardWindows(of: app).first {
                app.hide()
                return window
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        app.hide()
        return nil
    }

    private static func standardWindows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return ((attribute(element, kAXWindowsAttribute) as? [AXUIElement]) ?? [])
            .filter { attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole as String }
    }

    /// Presses the menu item with ⌘N (New Conversation), whatever the language.
    private static func newConversationFromMenu(of app: NSRunningApplication) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = attribute(element, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        for menuTitle in children(of: bar as! AXUIElement) {
            for menu in children(of: menuTitle) {
                for item in children(of: menu)
                where attribute(item, kAXMenuItemCmdCharAttribute) as? String == "N"
                    && (attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int) == 0 {
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    /// The Ask Siri field (a new conversation builds it anew: waited for).
    private static func promptField(in window: AXUIElement) async -> AXUIElement? {
        for _ in 0..<20 {
            if let field = descendants(of: window, where: { identifier($0) == "promptViewTextField" }).first { return field }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Siri's answer as it comes: reported at each change, done once it has stood still a while
    /// (Siri streams it), or after `limit`. A reply counts only past the `after` ones there were,
    /// and once it differs from `previous`.
    private static func follow(_ window: AXUIElement, after count: Int, previous: SiriReply?,
                               onReply: @escaping @MainActor (SiriReply) -> Void,
                               limit: Duration = .seconds(45)) async {
        let clock = ContinuousClock()
        let start = clock.now
        var last = previous
        var changed = clock.now
        var heard = false
        let ref = AXRef(window)
        // Stopped by a new question (the island cancels the one before).
        while clock.now - start < limit, !Task.isCancelled {
            let reply = await Task.detached { () -> SiriReply? in
                let all = replies(in: ref.element)
                guard all.count > count, let newest = all.last else { return nil }
                return SiriReplyReader.read(newest)
            }.value
            if let reply, reply != last, !reply.isEmpty {
                last = reply
                changed = clock.now
                heard = true
                onReply(reply)
            }
            if heard, clock.now - changed > .milliseconds(2500) { return }
            // Nothing new after a button (Cancel may say nothing): done.
            if !heard, previous != nil, clock.now - start > .seconds(6) { return }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// Siri's replies in the conversation, oldest first.
    nonisolated private static func replies(in window: AXUIElement) -> [AXUIElement] {
        AX.descendants(of: window, where: { AX.identifier($0) == "modelResponse" })
    }

    nonisolated private static func descendants(of element: AXUIElement, where matches: (AXUIElement) -> Bool) -> [AXUIElement] {
        AX.descendants(of: element, where: matches)
    }

    nonisolated private static func identifier(_ element: AXUIElement) -> String? { AX.identifier(element) }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] { AX.children(of: element) }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? { AX.attribute(element, name) }
}
