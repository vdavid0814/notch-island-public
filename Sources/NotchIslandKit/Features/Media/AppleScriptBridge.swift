import AppKit

/// Runs the players' AppleScript libraries in-process (Music: plain Apple Events, `PlayerAppleEvents`).
///
/// * `NSAppleScript`, never `osascript`: a spawn costs ~28 ms of CPU before the event is even sent.
/// * An actor whose executor is its own serial dispatch queue: `NSAppleScript` must not run
///   concurrently, and a synchronous Apple Event can block for up to the 3 s script timeout, which
///   must stall this private thread, not the main thread or a cooperative-pool thread.
/// * One compiled library per player (see `AppleScriptLibrary`); compile failures are not cached, so a
///   transient failure is retried on the next call instead of failing forever.
/// * Never talks to a player that is not running: checked here right before execution and again
///   inside every handler.
actor AppleScriptBridge {
    private let queue = DispatchSerialQueue(label: "com.davidvarga.notchisland.applescript", qos: .utility)
    private var libraries: [String: NSAppleScript] = [:]

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Drops the compiled libraries (and with them the AppleScript component) while no pulls run;
    /// the next call compiles again, a few milliseconds.
    func purge() {
        libraries.removeAll()
    }

    func run(_ handler: ScriptHandler, for player: ScriptablePlayer, argument: Double? = nil) -> Result<ScriptValue, AppleScriptFailure> {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty else {
            return .failure(.notRunning)
        }
        // Music takes plain Apple Events: no script to compile, scan and keep in memory.
        if PlayerAppleEvents.bundleIDs.contains(player.bundleID) {
            return PlayerAppleEvents.run(handler, bundleID: player.bundleID, argument: argument)
        }
        let library: NSAppleScript
        if let cached = libraries[player.bundleID] {
            library = cached
        } else {
            guard let script = NSAppleScript(source: AppleScriptLibrary.source(for: player)) else {
                return .failure(.failed(code: 0, message: "could not create script"))
            }
            var errorInfo: NSDictionary?
            guard script.compileAndReturnError(&errorInfo) else {
                return .failure(AppleScriptFailure(errorInfo: errorInfo))
            }
            libraries[player.bundleID] = script
            library = script
        }
        var errorInfo: NSDictionary?
        let result = library.executeAppleEvent(Self.subroutineEvent(handler, argument: argument), error: &errorInfo)
        if errorInfo != nil { return .failure(AppleScriptFailure(errorInfo: errorInfo)) }
        return .success(ScriptValue(result))
    }

    /// A kASAppleScriptSuite/kASSubroutineEvent event that calls `handler` with its arguments. The codes
    /// come from the OpenScripting headers, which are not part of the linked frameworks.
    private static func subroutineEvent(_ handler: ScriptHandler, argument: Double?) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: FourCharCode(fourCC: "ascr"),
            eventID: FourCharCode(fourCC: "psbr"),
            targetDescriptor: .currentProcess(),
            returnID: AEReturnID(-1),          // kAutoGenerateReturnID
            transactionID: AETransactionID(0)  // kAnyTransactionID
        )
        event.setParam(NSAppleEventDescriptor(string: handler.rawValue), forKeyword: FourCharCode(fourCC: "snam"))
        let arguments = NSAppleEventDescriptor.list()
        if let argument { arguments.insert(NSAppleEventDescriptor(double: argument), at: 1) }
        event.setParam(arguments, forKeyword: FourCharCode(fourCC: "----"))
        return event
    }
}

nonisolated enum AppleScriptFailure: Error, Sendable, Equatable {
    case notRunning
    /// -1743 errAEEventNotPermitted: the user denied Automation for this player.
    case notPermitted
    /// -1728 errAENoSuchObject: typically "no current track"; normal, not worth logging.
    case noSuchObject
    /// -1712 errAETimeout.
    case timedOut
    case failed(code: Int, message: String)

    init(code: Int, message: String) {
        switch code {
        case -1743: self = .notPermitted
        case -1728: self = .noSuchObject
        case -1712: self = .timedOut
        // procNotFound, connectionInvalid: the app quit between the check and the event.
        case -600, -609: self = .notRunning
        default: self = .failed(code: code, message: message)
        }
    }

    init(errorInfo: NSDictionary?) {
        let code = (errorInfo?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown AppleScript error"
        self.init(code: code, message: message)
    }
}

/// A script result converted to plain Sendable data while still on the bridge's queue.
nonisolated enum ScriptValue: Sendable, Equatable {
    case missing
    case text(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case list([ScriptValue])

    init(_ descriptor: NSAppleEventDescriptor?) {
        guard let descriptor else { self = .missing; return }
        let type = descriptor.descriptorType
        switch type {
        case FourCharCode(fourCC: "list"):
            let count = descriptor.numberOfItems
            self = .list(count > 0 ? (1...count).map { ScriptValue(descriptor.atIndex($0)) } : [])
        case FourCharCode(fourCC: "utxt"), FourCharCode(fourCC: "TEXT"), FourCharCode(fourCC: "utf8"):
            self = descriptor.stringValue.map(ScriptValue.text) ?? .missing
        case FourCharCode(fourCC: "doub"), FourCharCode(fourCC: "sing"), FourCharCode(fourCC: "long"), FourCharCode(fourCC: "shor"),
             FourCharCode(fourCC: "comp"), FourCharCode(fourCC: "magn"), FourCharCode(fourCC: "ldbl"):
            self = .number(descriptor.doubleValue)
        case FourCharCode(fourCC: "bool"), FourCharCode(fourCC: "true"), FourCharCode(fourCC: "fals"):
            self = .bool(descriptor.booleanValue)
        case FourCharCode(fourCC: "null"):
            self = .missing
        case FourCharCode(fourCC: "type"), FourCharCode(fourCC: "enum"):
            // `missing value` is the type constant 'msng'; any other constant is not data we use.
            self = .missing
        default:
            // Artwork: 'tdta', 'PNGf', 'JPEG', 'TIFF', …
            let bytes = descriptor.data
            self = bytes.isEmpty ? .missing : .data(bytes)
        }
    }

    var text: String? {
        if case .text(let text) = self { text } else { nil }
    }

    var number: Double? {
        switch self {
        case .number(let number): number
        case .text(let text): AppleScriptNumber.parse(text)
        default: nil
        }
    }

    var items: [ScriptValue]? {
        if case .list(let items) = self { items } else { nil }
    }
}

/// AppleScript coerces reals to text with the user's decimal separator: on a Hungarian system
/// `player position as text` is "23,410999298096", which `Double(_:)` rejects (the legacy scrubber then
/// silently never moved). Results are requested as typed numbers where possible; text is parsed here.
nonisolated enum AppleScriptNumber {
    static func parse(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        let lastComma = cleaned.lastIndex(of: ",")
        let lastDot = cleaned.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Both present: the later one is the decimal separator, the other groups thousands.
            if comma > dot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        case (_?, nil):
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        default:
            break
        }
        return Double(cleaned)
    }
}

/// The handlers every player's script library defines. Names are lowercase because a subroutine Apple
/// event must name the handler in lowercase, and `ni`-prefixed so they cannot collide with a player's
/// scripting terminology (AppleScript resolves identifiers against the target app's dictionary first).
nonisolated enum ScriptHandler: String, Sendable, CaseIterable {
    case seed = "niseed"
    case position = "niposition"
    case artwork = "niartwork"
    case play = "niplay"
    case pause = "nipause"
    case toggle = "nitoggle"
    case next = "ninext"
    case previous = "niprevious"
    case seek = "niseek"
}

/// Builds the one fixed AppleScript library per player. Pure.
///
/// Parameters (a seek position) are passed as handler arguments through a subroutine Apple event, never
/// interpolated into source, so the library compiles once per player and is reused for every call. (The
/// legacy cache was keyed by full source text: every distinct seek value compiled and cached a new
/// script forever.)
///
/// Every handler
/// * returns early unless `application id "…" is running` — entering a `tell` block launches the app,
///   and this check runs in the same execution as the `tell`;
/// * wraps its events in `with timeout of 3 seconds`, so a hung player blocks the bridge for at most
///   that long instead of the two-minute default;
/// * uses long `the…` variable names (short ones such as `st` collide with app terminology and fail to
///   compile with "Expected expression");
/// * keeps `player position` inside `try` (it errors while stopped, which used to sink the whole seed).
nonisolated enum AppleScriptLibrary {
    static let timeoutSeconds = 3

    static func source(for player: ScriptablePlayer) -> String {
        let app = "application id \"\(player.bundleID)\""
        let identifierExpression = switch player.artwork {
        case .rawData: "persistent ID of theTrack"
        case .url: "id of theTrack"
        }
        let artworkExpression = switch player.artwork {
        case .rawData: "raw data of artwork 1 of current track"
        case .url: "artwork url of current track"
        }

        func handler(_ handler: ScriptHandler, parameter: String? = nil, notRunning: String, body: [String]) -> String {
            let signature = "\(handler.rawValue)(\(parameter ?? ""))"
            let lines = ["on \(signature)",
                         "\tif \(app) is not running then return \(notRunning)",
                         "\twith timeout of \(timeoutSeconds) seconds",
                         "\t\ttell \(app)"]
                + body.map { "\t\t\t" + $0 }
                + ["\t\tend tell", "\tend timeout", "end \(handler.rawValue)"]
            return lines.joined(separator: "\n")
        }

        func command(_ name: ScriptHandler, _ statement: String, parameter: String? = nil) -> String {
            handler(name, parameter: parameter, notRunning: "false", body: [statement, "return true"])
        }

        let handlers = [
            handler(.seed, notRunning: "{\"stopped\", missing value, \"\", \"\", \"\", 0, \"\"}", body: [
                "set theState to (player state as text)",
                "set thePosition to missing value",
                "try",
                "\tset thePosition to player position",
                "end try",
                "set theName to \"\"",
                "set theArtist to \"\"",
                "set theAlbum to \"\"",
                "set theDuration to 0",
                "set theIdentifier to \"\"",
                "try",
                "\tset theTrack to current track",
                "\tset theName to (name of theTrack)",
                "\tset theArtist to (artist of theTrack)",
                "\tset theAlbum to (album of theTrack)",
                "\tset theDuration to (duration of theTrack)",
                "\ttry",
                "\t\tset theIdentifier to (\(identifierExpression) as text)",
                "\tend try",
                "end try",
                "return {theState, thePosition, theName, theArtist, theAlbum, theDuration, theIdentifier}",
            ]),
            handler(.position, notRunning: "missing value", body: [
                "try", "\treturn player position", "on error", "\treturn missing value", "end try",
            ]),
            handler(.artwork, notRunning: "missing value", body: [
                "try", "\treturn (get \(artworkExpression))", "on error", "\treturn missing value", "end try",
            ]),
            command(.play, "play"),
            command(.pause, "pause"),
            command(.toggle, "playpause"),
            command(.next, "next track"),
            command(.previous, "previous track"),
            command(.seek, "set player position to theSeconds", parameter: "theSeconds"),
        ]
        return handlers.joined(separator: "\n\n") + "\n"
    }
}

extension FourCharCode {
    /// `FourCharCode(fourCC: "list")` reads like the C literal 'list'.
    nonisolated init(fourCC code: StaticString) {
        self = code.withUTF8Buffer { bytes in
            precondition(bytes.count == 4, "a four-char code has four ASCII characters")
            return bytes.reduce(0) { $0 << 8 | UInt32($1) }
        }
    }
}
