import AppKit
import Contacts
import CoreServices
import Foundation

// What Spotlight reaches beyond apps, files and commands: a word's definition, the user's people
// and coming events (⌘8), and their browsers' bookmarks. Every source here runs only while
// Spotlight is open and only when its row could show; nothing is read at rest, and the people and
// the calendar only after the user allowed them from a row of their own.

// MARK: - Dictionary

/// A word defined by the system's dictionaries.
nonisolated struct AssistantDefinition: Sendable, Hashable {
    var word: String
    var text: String

    /// The first line of it, for a row.
    /// The entry opens with the headword and its pronunciation ("island | ˈʌɪlənd | noun 1 a
    /// piece…"); the row already names the word, so it starts at the part of speech.
    var summary: String {
        var line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        if line.lowercased().hasPrefix(word.lowercased()) { line = String(line.dropFirst(word.count)) }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") {
            let rest = line.dropFirst()
            line = String(rest.firstIndex(of: "|").map { rest[rest.index(after: $0)...] } ?? rest)
        }
        line = line.trimmingCharacters(in: .whitespaces)
        return String((line.isEmpty ? text : line).prefix(140))
    }
}

nonisolated enum DictionaryLookup {
    /// One word of letters (and an apostrophe or a hyphen), three to thirty long: what a
    /// dictionary is asked about. "safari" is; "12 km", "new york" and "a" are not.
    static func isWord(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...30).contains(text.count) else { return false }
        return text.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" } && text.contains(where: \.isLetter)
    }

    /// The active dictionaries' entry for the word (Dictionary's own order of sources); nil when
    /// none has it. A few milliseconds, off the main thread.
    @concurrent static func define(_ word: String) async -> AssistantDefinition? {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWord(word) else { return nil }
        let text = word as CFString
        let range = DCSGetTermRangeInString(nil, text, 0)
        guard range.location != kCFNotFound, range.length >= CFStringGetLength(text) - 1,
              let definition = DCSCopyTextDefinition(nil, text, range)?.takeRetainedValue() as String?, !definition.isEmpty else { return nil }
        return AssistantDefinition(word: word, text: definition)
    }

    static func url(for word: String) -> URL? {
        word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "dict://\($0)") }
    }
}

// MARK: - People

/// One of the user's contacts, with the ways to reach them.
nonisolated struct AssistantContact: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var organization: String?
    var phones: [String]
    var emails: [String]

    /// Under the name in a row: the first number, else the first address.
    var detail: String? { phones.first ?? emails.first ?? organization }

    /// What can be done with it, in order: call and message each number, write to each address,
    /// copy them, open the card.
    var actions: [ContactAction] {
        phones.flatMap { [ContactAction(kind: .call, value: $0, contactID: id), ContactAction(kind: .message, value: $0, contactID: id)] }
            + emails.map { ContactAction(kind: .email, value: $0, contactID: id) }
            + (phones + emails).map { ContactAction(kind: .copy, value: $0, contactID: id) }
            + [ContactAction(kind: .openCard, value: name, contactID: id)]
    }
}

nonisolated struct ContactAction: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: String, Sendable { case call, message, email, copy, openCard }

    var kind: Kind
    /// The number or the address (the name for the card).
    var value: String
    var contactID: String

    var id: String { "\(contactID):\(kind.rawValue):\(value)" }

    var title: String {
        switch kind {
        case .call: String(localized: "Call \(value)")
        case .message: String(localized: "Message \(value)")
        case .email: String(localized: "Email \(value)")
        case .copy: String(localized: "Copy \(value)")
        case .openCard: String(localized: "Show in Contacts")
        }
    }

    var symbol: String {
        switch kind {
        case .call: "phone.fill"
        case .message: "message.fill"
        case .email: "envelope.fill"
        case .copy: "doc.on.doc.fill"
        case .openCard: "person.crop.circle.fill"
        }
    }

    /// What opening it hands to the system; nil for copying.
    var url: URL? {
        let digits = value.filter { $0.isNumber || $0 == "+" }
        switch kind {
        case .call: return URL(string: "tel:\(digits)")
        case .message: return URL(string: "sms:\(digits)")
        case .email: return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "mailto:\($0)") }
        case .openCard: return URL(string: "addressbook://\(contactID)")
        case .copy: return nil
        }
    }
}

/// What Spotlight must be allowed before it can list something.
nonisolated enum AssistantPermission: String, Sendable, Hashable {
    case contacts, calendar

    var title: String {
        switch self {
        case .contacts: String(localized: "Show My Contacts…")
        case .calendar: String(localized: "Show My Events…")
        }
    }

    var symbol: String { self == .contacts ? "person.2.fill" : "calendar" }
}

nonisolated enum AccessState: Sendable, Equatable { case notDetermined, denied, granted }

nonisolated enum ContactsLookup {
    static func access() -> AccessState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// macOS's own prompt, once; decided before, the Privacy settings open instead.
    @concurrent static func request() async -> AccessState {
        if access() == .notDetermined { _ = try? await CNContactStore().requestAccess(for: .contacts) }
        return access()
    }

    /// The contacts whose name matches, at most `limit`: read only once access was given, off the
    /// main thread, a store per read (nothing is kept between openings).
    @concurrent static func search(_ query: String, limit: Int) async -> [AssistantContact] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard access() == .granted, !query.isEmpty else { return [] }
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey,
                    CNContactEmailAddressesKey, CNContactIdentifierKey] as [any CNKeyDescriptor]
            + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        guard let found = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys) else { return [] }
        return found.prefix(limit).compactMap { contact in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            guard !name.isEmpty else { return nil }
            return AssistantContact(id: contact.identifier, name: name,
                                    organization: contact.organizationName.isEmpty || contact.organizationName == name ? nil : contact.organizationName,
                                    phones: contact.phoneNumbers.map(\.value.stringValue),
                                    emails: contact.emailAddresses.map { $0.value as String })
        }
    }
}

// MARK: - Bookmarks

nonisolated struct AssistantBookmark: Sendable, Hashable, Identifiable {
    var title: String
    var url: URL
    /// The browser it is from ("Safari", "Chrome").
    var browser: String

    var id: String { url.absoluteString }
}

/// The bookmarks of the browsers on this Mac, read from their own files: Chrome's, Arc's and
/// Brave's are plain JSON; Safari's only where macOS lets the app read it (it needs Full Disk
/// Access on most Macs, and is never asked for). No history is ever read.
nonisolated enum BrowserBookmarks {
    static var sources: [(browser: String, path: String)] {
        let support = NSHomeDirectory() + "/Library/Application Support"
        return [("Chrome", support + "/Google/Chrome/Default/Bookmarks"),
                ("Arc", support + "/Arc/User Data/Default/Bookmarks"),
                ("Brave", support + "/BraveSoftware/Brave-Browser/Default/Bookmarks")]
    }

    static let safariPath = NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
    static let limit = 4000

    @concurrent static func all() async -> [AssistantBookmark] {
        var found: [AssistantBookmark] = []
        for source in sources {
            guard let data = FileManager.default.contents(atPath: source.path) else { continue }
            found += chromium(data, browser: source.browser)
        }
        if FileManager.default.isReadableFile(atPath: safariPath), let data = FileManager.default.contents(atPath: safariPath) {
            found += safari(data)
        }
        var seen = Set<String>()
        return Array(found.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    /// Chromium's `Bookmarks`: `roots` of folders (`children`) and links (`type: url`).
    static func chromium(_ data: Data, browser: String) -> [AssistantBookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = json["roots"] as? [String: Any] else { return [] }
        var found: [AssistantBookmark] = []
        func walk(_ node: [String: Any], depth: Int) {
            guard depth < 32 else { return }
            if node["type"] as? String == "url", let name = node["name"] as? String, let link = node["url"] as? String,
               let url = web(link) {
                found.append(AssistantBookmark(title: name.isEmpty ? link : name, url: url, browser: browser))
            }
            for child in node["children"] as? [[String: Any]] ?? [] { walk(child, depth: depth + 1) }
        }
        for root in roots.values { if let root = root as? [String: Any] { walk(root, depth: 0) } }
        return found
    }

    /// Safari's `Bookmarks.plist`: `Children` of lists and leaves (`URLString`, `URIDictionary.title`).
    /// The Reading List is left out.
    static func safari(_ data: Data) -> [AssistantBookmark] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        var found: [AssistantBookmark] = []
        func walk(_ node: [String: Any], depth: Int) {
            guard depth < 32, node["Title"] as? String != "com.apple.ReadingList" else { return }
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let link = node["URLString"] as? String, let url = web(link) {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
                found.append(AssistantBookmark(title: title.flatMap { $0.isEmpty ? nil : $0 } ?? link, url: url, browser: "Safari"))
            }
            for child in node["Children"] as? [[String: Any]] ?? [] { walk(child, depth: depth + 1) }
        }
        walk(plist, depth: 0)
        return found
    }

    /// A link a browser opens: http or https, nothing else (no `javascript:` bookmarklets).
    private static func web(_ link: String) -> URL? {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
