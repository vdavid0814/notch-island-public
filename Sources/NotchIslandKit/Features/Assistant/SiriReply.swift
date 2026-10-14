import AppKit

/// A stretch of Siri's text as it draws it: semibold where it stresses a figure or a name, a link
/// where it offers more about something (Siri's own tap asks about it).
nonisolated struct SiriRun: Sendable, Equatable {
    var text: String
    var bold = false
    var link = false
}

/// One of Siri's result cards: a file (name, the start of what it says, its size) or an app, with
/// the icon Siri drew for it (PNG, read through Accessibility).
nonisolated struct SiriCard: Sendable, Equatable, Identifiable {
    var id: Int
    var title: String
    var detail: String
    var size: String
    var icon: Data?
}

/// A photo Siri found: what it says about it ("2026. Jul 8. at 20:20, Duration 0:10, is
/// favourite") — the picture itself is not readable, it is looked up in the library by that date.
nonisolated struct SiriPhoto: Sendable, Equatable, Identifiable {
    var id: Int
    var label: String

    var isVideo: Bool { label.contains("Duration") }
    var duration: String? {
        guard let range = label.range(of: #"Duration \d+:\d+"#, options: .regularExpression) else { return nil }
        return String(label[range].dropFirst("Duration ".count))
    }
    var isFavourite: Bool { label.contains("favourit") || label.contains("favorit") }
}

/// Siri's message card: who to, the text so far, and its buttons (Cancel, Send).
nonisolated struct SiriComposer: Sendable, Equatable {
    var recipient: String
    var text: String
    var actions: [String]
}

/// Siri's reply in the order it shows it.
nonisolated enum SiriBlock: Sendable, Equatable {
    case paragraph([SiriRun], heading: Bool)
    /// "nasa.gov", "+4 sources".
    case sources([String])
    /// A picture Siri shows (the Moon): its title; the picture is looked up by it.
    case image(String)
    case cards([SiriCard])
    case photos([SiriPhoto])
    case composer(SiriComposer)
    /// "Show More" and the like.
    case buttons([String])
}

/// What Siri said last in the conversation, read from its window through Accessibility.
nonisolated struct SiriReply: Sendable, Equatable {
    var blocks: [SiriBlock] = []

    /// Its words, for Copy and for telling whether it said anything.
    var text: String {
        blocks.compactMap { block -> String? in
            if case .paragraph(let runs, _) = block { return runs.map(\.text).joined() }
            return nil
        }.joined(separator: "\n\n")
    }

    var isEmpty: Bool { blocks.isEmpty }
}

extension SiriReply {
    /// Every kind of part, for `demo/sirisample`.
    static let sample = SiriReply(blocks: [
        .paragraph([SiriRun(text: "The "), SiriRun(text: "Moon", link: true), SiriRun(text: " is on average "),
                    SiriRun(text: "384 400 km", bold: true), SiriRun(text: " away from "), SiriRun(text: "Earth", link: true), SiriRun(text: ".")], heading: false),
        .sources(["nasa.gov", "+3"]),
        .cards([SiriCard(id: 0, title: "i1.3 Vallások — A zsidó monoteizmus.md", detail: "# i1.3 Vallások — A zsidó monoteizmus és a kereszténység", size: "15 KB"),
                SiriCard(id: 1, title: "6. tétel A 18. századi magyar társadalom.pdf", detail: "1 6. tétel A 18. századi magyar társadalom — népesség", size: "169 KB")]),
        .photos((0..<8).map { SiriPhoto(id: $0, label: $0 == 2 ? "2025. Oct 21. at 16:25, Duration 0:10, is favourite" : "2026. Jul 8. at 20:20") }),
        .composer(SiriComposer(recipient: "Gergő Varga, Messages", text: "", actions: ["Cancel", "Send"])),
        .buttons(["Show More"]),
    ])
}

/// Something done to Siri's reply from the island, done in Siri AI.
nonisolated enum SiriAction: Sendable, Equatable {
    /// A button by its name: Show More, Cancel, Send, a source.
    case button(String)
    /// A link in the text (Moon): Siri tells about it.
    case link(String)
    /// The message card's text.
    case composerText(String)
}

/// Reads Siri's replies from its conversation window. Off the main thread: every attribute is a
/// round trip to Siri AI.
nonisolated enum SiriReplyReader {
    static func read(_ reply: AXUIElement) -> SiriReply {
        var blocks: [SiriBlock] = []
        func appendSource(_ name: String) {
            if case .sources(let names)? = blocks.last { blocks[blocks.count - 1] = .sources(names + [name]) } else { blocks.append(.sources([name])) }
        }
        func appendButton(_ name: String) {
            if case .buttons(let names)? = blocks.last { blocks[blocks.count - 1] = .buttons(names + [name]) } else { blocks.append(.buttons([name])) }
        }
        for part in AX.children(of: reply) {
            let id = AX.identifier(part) ?? ""
            let role = AX.role(part)
            switch id {
            case "modelResponse-richTextParagraph":
                let runs = runs(of: part)
                if !runs.isEmpty { blocks.append(.paragraph(runs, heading: isHeading(part))) }
            case "modelResponse-richTextSourceAttribution":
                if let name = AX.description(part) ?? AX.attributedDescription(part), !name.isEmpty { appendSource(name) }
            case "modelResponse-richTextImage" where role == kAXButtonRole as String:
                if let title = AX.description(part) ?? AX.attributedDescription(part), !title.isEmpty { blocks.append(.image(title)) }
            case "modelResponse-richTextImage":
                break // the picture's caption: its title, shown with it
            case "modelResponse-richTextCustomView":
                blocks += custom(part)
            default:
                if role == kAXButtonRole as String, let name = AX.description(part), !name.isEmpty { appendButton(name) }
                else if role == kAXStaticTextRole as String, let text = AX.value(part), !text.isEmpty {
                    blocks.append(.paragraph([SiriRun(text: text)], heading: false))
                }
            }
        }
        return SiriReply(blocks: blocks)
    }

    /// The paragraph as Siri draws it: semibold runs and links from its attributed string.
    private static func runs(of paragraph: AXUIElement) -> [SiriRun] {
        let plain = AX.value(paragraph) ?? ""
        guard !plain.isEmpty else { return [] }
        var range = CFRange(location: 0, length: (plain as NSString).length)
        guard let value = AXValueCreate(.cfRange, &range) else { return [SiriRun(text: plain)] }
        var out: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(paragraph, kAXAttributedStringForRangeParameterizedAttribute as CFString, value, &out) == .success,
              let attributed = out as? NSAttributedString else { return [SiriRun(text: plain)] }
        var runs: [SiriRun] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let text = (attributed.string as NSString).substring(with: range)
            let font = attributes[NSAttributedString.Key("AXFont")] as? [String: Any]
            let name = font?["AXFontName"] as? String ?? ""
            let bold = ["Semibold", "Bold", "Heavy", "Black"].contains { name.contains($0) }
            let link = attributes[NSAttributedString.Key("AXLink")] != nil
            if var last = runs.last, last.bold == bold, last.link == link, !link {
                last.text += text
                runs[runs.count - 1] = last
            } else {
                runs.append(SiriRun(text: text, bold: bold, link: link))
            }
        }
        return runs
    }

    /// Larger than Siri's body text (15 pt): a heading.
    private static func isHeading(_ paragraph: AXUIElement) -> Bool {
        var range = CFRange(location: 0, length: 1)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        var out: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(paragraph, kAXAttributedStringForRangeParameterizedAttribute as CFString, value, &out) == .success,
              let attributed = out as? NSAttributedString, attributed.length > 0,
              let font = attributed.attribute(NSAttributedString.Key("AXFont"), at: 0, effectiveRange: nil) as? [String: Any],
              let size = font["AXFontSize"] as? Double else { return false }
        return size > 16
    }

    /// Siri's own views: a photo grid, result cards (files, apps), a message card, and the buttons
    /// under them.
    private static func custom(_ view: AXUIElement) -> [SiriBlock] {
        var blocks: [SiriBlock] = []
        if let grid = AX.descendants(of: view, where: { AX.identifier($0) == "photos_collection_view" }).first {
            let photos = AX.descendants(of: grid, where: { AX.identifier($0) == "mediaKind_asset" })
                .enumerated().map { SiriPhoto(id: $0.offset, label: AX.description($0.element) ?? "") }
            if !photos.isEmpty { blocks.append(.photos(photos)) }
        }
        let cells = AX.descendants(of: view, where: { AX.identifier($0)?.hasPrefix("Identifier:ResultCell") == true })
        let cards = cells.enumerated().compactMap { index, cell -> SiriCard? in
            let texts = AX.descendants(of: cell, where: { AX.role($0) == kAXStaticTextRole as String }).compactMap(AX.value)
            guard let title = texts.first, !title.isEmpty else { return nil }
            let icon = AX.descendants(of: cell, where: { AX.role($0) == kAXImageRole as String }).lazy.compactMap(AX.imageData).first
            return SiriCard(id: index, title: title, detail: texts.count > 1 ? texts[1] : "",
                            size: texts.count > 2 ? texts[2] : "", icon: icon)
        }
        if !cards.isEmpty { blocks.append(.cards(cards)) }
        let buttons = AX.children(of: view).flatMap { child -> [AXUIElement] in
            AX.role(child) == kAXButtonRole as String ? [child] : []
        }
        if let field = AX.descendants(of: view, where: { AX.role($0) == kAXTextFieldRole as String }).first {
            let named = AX.descendants(of: view, where: { AX.role($0) == kAXButtonRole as String }).compactMap(AX.description)
            // "Gergő Varga, Messages": the recipient; the rest its buttons.
            let recipient = named.first { $0.contains(",") } ?? ""
            blocks.append(.composer(SiriComposer(recipient: recipient, text: AX.value(field) ?? "",
                                                 actions: named.filter { $0 != recipient })))
        } else {
            let names = buttons.compactMap(AX.description).filter { !$0.isEmpty }
            if !names.isEmpty { blocks.append(.buttons(names)) }
        }
        return blocks
    }
}

/// The Accessibility reads Siri's replies need.
nonisolated enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func descendants(of element: AXUIElement, where matches: (AXUIElement) -> Bool, depth: Int = 0) -> [AXUIElement] {
        guard depth < 30 else { return [] }
        var found: [AXUIElement] = matches(element) ? [element] : []
        for child in children(of: element) { found += descendants(of: child, where: matches, depth: depth + 1) }
        return found
    }

    static func role(_ element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute) as? String }
    static func identifier(_ element: AXUIElement) -> String? { attribute(element, kAXIdentifierAttribute) as? String }
    static func description(_ element: AXUIElement) -> String? { attribute(element, kAXDescriptionAttribute) as? String }
    static func value(_ element: AXUIElement) -> String? { attribute(element, kAXValueAttribute) as? String }

    static func attributedDescription(_ element: AXUIElement) -> String? {
        (attribute(element, "AXAttributedDescription") as? NSAttributedString)?.string
    }

    /// The picture an image element carries (PNG), where Siri gives it.
    static func imageData(_ element: AXUIElement) -> Data? {
        (attribute(element, "AXImageData") as? [Any])?.first as? Data
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}
