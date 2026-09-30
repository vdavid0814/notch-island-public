import Foundation

/// An emoji and the words it is found by (Emoji, ⌘7).
nonisolated struct AssistantEmoji: Hashable, Sendable, Identifiable {
    let character: String
    /// Its Unicode name, in lower case ("face with tears of joy").
    let name: String
    /// Short words people type for it ("laugh", "lol").
    var aliases: [String] = []

    var id: String { character }

    /// "Face with tears of joy".
    var title: String { name.prefix(1).uppercased() + name.dropFirst() }

    /// The names it answers to, best first: an alias typed exactly ("ok", "fire") comes first.
    func rank(for query: String) -> Int? {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return 0 }
        if aliases.contains(query) || name == query { return 0 }
        if aliases.contains(where: { $0.hasPrefix(query) }) || name.hasPrefix(query) { return 1 }
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let words = (aliases + [name]).flatMap { $0.split { !$0.isLetter && !$0.isNumber } }
        return tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } } ? 2 : nil
    }
}

/// The emoji table with where its names start, built with the table off the main thread: a
/// keystroke ranks only the emoji a name, an alias or a word of theirs could match, instead of
/// every one of them (0.5 ms on the main thread per keystroke instead of 4.7, measured in a debug
/// build).
nonisolated struct EmojiIndex: Sendable {
    let all: [AssistantEmoji]
    /// Positions in `all`, in order, by the first character and by the first two of every alias,
    /// the name, and each of their words. A match starts with the query (its tokens, for a match by
    /// words), so it is under the query's own start: the rank of those alone gives the same list.
    private let starts: [String: [Int32]]

    @concurrent static func build(_ emoji: @Sendable () async -> [AssistantEmoji]) async -> EmojiIndex {
        EmojiIndex(await emoji())
    }

    init(_ all: [AssistantEmoji]) {
        self.all = all
        var starts: [String: [Int32]] = [:]
        for (index, item) in all.enumerated() {
            let position = Int32(index)
            let names = item.aliases + [item.name]
            for text in names + names.flatMap({ $0.split { !$0.isLetter && !$0.isNumber }.map(String.init) }) {
                for key in [String(text.prefix(1)), String(text.prefix(2))] where !key.isEmpty && starts[key]?.last != position {
                    starts[key, default: []].append(position)
                }
            }
        }
        self.starts = starts
    }

    /// `AssistantEmoji.rank`'s order: an alias typed exactly first, then names that start with the
    /// query, then the rest, each in the table's order.
    func matching(_ text: String) -> [AssistantEmoji] {
        let query = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        func start(_ text: some StringProtocol) -> [Int32] { starts[String(text.prefix(2))] ?? [] }
        // Names and aliases that start with the query, and emoji every token starts a word of.
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let byWords = tokens.dropFirst().reduce(Set(start(tokens.first ?? ""))) { $0.intersection(start($1)) }
        let candidates = Set(start(query)).union(byWords).sorted()
        return candidates.compactMap { index in all[Int(index)].rank(for: text).map { (all[Int(index)], $0) } }
            .enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
    }
}

/// The emoji Spotlight can paste, built from the Unicode names of this Mac's own tables (no list
/// to keep up to date, no download), with the common sequences that have no single name and the
/// flags. Built on first use off the main thread and dropped a while after Spotlight closes.
nonisolated enum EmojiTable {
    @concurrent static func build() async -> [AssistantEmoji] {
        var emoji: [AssistantEmoji] = []
        var seen = Set<String>()
        func add(_ character: String, _ name: String) {
            guard seen.insert(character).inserted else { return }
            emoji.append(AssistantEmoji(character: character, name: name, aliases: aliases[character] ?? []))
        }
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let properties = scalar.properties
                guard properties.isEmoji, !properties.isEmojiModifier, let name = properties.name,
                      !name.hasPrefix("EMOJI COMPONENT"), !(0x1F1E6...0x1F1FF).contains(value) else { continue }
                // A symbol that is text by default ("❤") is asked for as an emoji ("❤️").
                let character = properties.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}"
                add(character, name.lowercased())
            }
        }
        for (character, name) in sequences { add(character, name) }
        // Flags from the regions' letters ("🇭🇺", "Hungary flag").
        let english = Locale(identifier: "en_US")
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isUppercase }),
                  let country = english.localizedString(forRegionCode: code) else { continue }
            let flag = code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }.map(String.init).joined()
            add(flag, "\(country.lowercased()) flag")
        }
        return emoji
    }

    /// Where emoji live in Unicode (a few thousand code points to look at, once).
    static let ranges: [ClosedRange<UInt32>] = [
        0x00A9...0x00AE, 0x203C...0x2049, 0x2122...0x2139, 0x2194...0x21AA, 0x231A...0x23FF, 0x24C2...0x24C2,
        0x25AA...0x27BF, 0x2934...0x2935, 0x2B05...0x2B55, 0x3030...0x303D, 0x3297...0x3299,
        0x1F004...0x1F251, 0x1F300...0x1F6FF, 0x1F7E0...0x1F7F0, 0x1F90C...0x1FAFF,
    ]

    /// Joined sequences people use, which have a name only in CLDR.
    static let sequences: [(String, String)] = [
        ("❤️‍🔥", "heart on fire"), ("❤️‍🩹", "mending heart"), ("😶‍🌫️", "face in clouds"), ("😮‍💨", "face exhaling"),
        ("😵‍💫", "face with spiral eyes"), ("🙂‍↔️", "head shaking horizontally"), ("🙂‍↕️", "head shaking vertically"),
        ("🧑‍💻", "technologist"), ("👨‍💻", "man technologist"), ("👩‍💻", "woman technologist"), ("🧑‍🚀", "astronaut"),
        ("🧑‍🍳", "cook"), ("🧑‍🎨", "artist"), ("🧑‍🔬", "scientist"), ("🧑‍🏫", "teacher"), ("🧑‍⚕️", "health worker"),
        ("🤷‍♂️", "man shrugging"), ("🤷‍♀️", "woman shrugging"), ("🤦‍♂️", "man facepalming"), ("🤦‍♀️", "woman facepalming"),
        ("🙋‍♂️", "man raising hand"), ("🙋‍♀️", "woman raising hand"), ("🏃‍♂️", "man running"), ("🏃‍♀️", "woman running"),
        ("👨‍👩‍👧‍👦", "family"), ("🐈‍⬛", "black cat"), ("🐕‍🦺", "service dog"), ("🐻‍❄️", "polar bear"), ("🐦‍🔥", "phoenix"),
        ("🍋‍🟩", "lime"), ("🏳️‍🌈", "rainbow flag"), ("🏳️‍⚧️", "transgender flag"), ("🏴‍☠️", "pirate flag"),
        ("👁️‍🗨️", "eye in speech bubble"),
    ]

    /// What people type rather than the Unicode name.
    static let aliases: [String: [String]] = [
        "👍": ["thumbs up", "like", "yes", "+1"], "👎": ["thumbs down", "dislike", "no", "-1"], "👌": ["ok", "okay", "perfect"],
        "❤️": ["heart", "love"], "💔": ["broken heart"], "🔥": ["fire", "lit", "hot"], "😂": ["laugh", "lol", "joy"],
        "🤣": ["laugh", "rofl", "lmao"], "😀": ["smile", "happy", "grin"], "🙂": ["smile"], "😊": ["smile", "blush", "happy"],
        "😉": ["wink"], "😍": ["love", "heart eyes"], "😘": ["kiss"], "😎": ["cool", "sunglasses"], "🤔": ["thinking", "hmm"],
        "😅": ["sweat", "phew"], "😢": ["sad", "cry"], "😭": ["cry", "sob"], "😡": ["angry", "mad"], "😱": ["scream", "shock"],
        "😴": ["sleep", "tired"], "🙄": ["eye roll"], "🥳": ["party"], "🎉": ["party", "tada", "celebrate", "congrats"],
        "🙏": ["please", "thanks", "pray"], "👏": ["clap", "applause", "bravo"], "🙌": ["hooray", "yay"], "👋": ["wave", "hi", "hello", "bye"],
        "💪": ["strong", "muscle"], "🤝": ["handshake", "deal"], "🤷": ["shrug"], "🤦": ["facepalm"], "👀": ["eyes", "look"],
        "✅": ["check", "done", "yes"], "❌": ["cross", "no", "wrong"], "⚠️": ["warning"], "💯": ["hundred", "100"],
        "✨": ["sparkles", "magic"], "⭐": ["star"], "🚀": ["rocket", "launch", "ship it"], "💡": ["idea"], "🐛": ["bug"],
        "📌": ["pin"], "🔒": ["lock"], "☕": ["coffee"], "🍺": ["beer"], "🍕": ["pizza"], "🎂": ["birthday", "cake"],
        "☀️": ["sun", "sunny"], "🌙": ["moon", "night"], "❄️": ["snow", "cold"], "🌈": ["rainbow"], "💀": ["dead", "skull"],
        "💩": ["poop"], "🤖": ["robot", "bot"], "🍎": ["apple"], "💻": ["laptop", "mac"], "📱": ["phone", "iphone"],
        "🎵": ["music", "note"], "📅": ["calendar", "date"], "⏰": ["alarm"], "🏠": ["home", "house"], "🐶": ["dog"], "🐱": ["cat"],
    ]
}
