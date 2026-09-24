import AppKit

/// Music without AppleScript: the handlers of `AppleScriptLibrary`, sent as plain Apple Events.
///
/// Compiling AppleScript runs an XProtect scan whose YARA rules then stay in the process — about
/// 14 MB for as long as the app runs (measured with malloc stack logging), plus the AppleScript
/// heap — and every call interprets a script. Plain events need neither. The results have the
/// same shape as the script library's, so everything after the bridge is unchanged.
///
/// Codes come from Music's scripting dictionary (com.apple.Music.sdef). Spotify still goes through
/// AppleScript: its codes cannot be checked on this Mac.
nonisolated enum PlayerAppleEvents {
    /// The players handled here.
    static let bundleIDs: Set<String> = [ScriptablePlayer.music.bundleID]
    /// As `with timeout of 3 seconds` in the script library.
    static let timeout: TimeInterval = TimeInterval(AppleScriptLibrary.timeoutSeconds)

    static func run(_ handler: ScriptHandler, bundleID: String, argument: Double?) -> Result<ScriptValue, AppleScriptFailure> {
        let app = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        do {
            switch handler {
            case .seed:
                return .success(try seed(app))
            case .position:
                return .success((try? get(property("pPos"), from: app)).map(ScriptValue.init) ?? .missing)
            case .artwork:
                // raw data of artwork 1 of current track
                let artwork = element("cArt", index: 1, of: property("pTrk"))
                return .success((try? get(property("pRaw", of: artwork), from: app)).map(ScriptValue.init) ?? .missing)
            case .play: try command("Play", to: app)
            case .pause: try command("Paus", to: app)
            case .toggle: try command("PlPs", to: app)
            case .next: try command("Next", to: app)
            case .previous: try command("Prev", to: app)
            case .seek:
                try set(property("pPos"), to: NSAppleEventDescriptor(double: argument ?? 0), in: app)
            }
            return .success(.bool(true))
        } catch let failure as AppleScriptFailure {
            return .failure(failure)
        } catch {
            return .failure(.failed(code: 0, message: String(describing: error)))
        }
    }

    /// {state, position, name, artist, album, duration, persistent ID}, as the library's `niseed`.
    private static func seed(_ app: NSAppleEventDescriptor) throws -> ScriptValue {
        let state = try get(property("pPlS"), from: app)
        let position = (try? get(property("pPos"), from: app)).map(ScriptValue.init) ?? .missing
        let track = property("pTrk")
        func text(_ code: StaticString) -> ScriptValue {
            .text((try? get(property(code, of: track), from: app))?.stringValue ?? "")
        }
        let duration = (try? get(property("pDur", of: track), from: app)).map(ScriptValue.init) ?? .number(0)
        return .list([.text(stateText(state)), position, text("pnam"), text("pArt"), text("pAlb"), duration, text("pPIS")])
    }

    /// The player-state enumerators, as the script library's `player state as text`.
    static func stateText(_ descriptor: NSAppleEventDescriptor) -> String {
        switch descriptor.enumCodeValue {
        case FourCharCode(fourCC: "kPSP"): "playing"
        case FourCharCode(fourCC: "kPSp"): "paused"
        case FourCharCode(fourCC: "kPSF"): "fast forwarding"
        case FourCharCode(fourCC: "kPSR"): "rewinding"
        default: "stopped"
        }
    }

    // MARK: Events

    private static func get(_ specifier: NSAppleEventDescriptor, from app: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let event = event("core", "getd", to: app)
        event.setParam(specifier, forKeyword: keyDirectObject)
        let reply = try send(event)
        guard let result = reply.paramDescriptor(forKeyword: keyDirectObject) else { throw AppleScriptFailure.noSuchObject }
        return result
    }

    private static func set(_ specifier: NSAppleEventDescriptor, to value: NSAppleEventDescriptor, in app: NSAppleEventDescriptor) throws {
        let event = event("core", "setd", to: app)
        event.setParam(specifier, forKeyword: keyDirectObject)
        event.setParam(value, forKeyword: FourCharCode(fourCC: "data"))
        _ = try send(event)
    }

    private static func command(_ id: StaticString, to app: NSAppleEventDescriptor) throws {
        _ = try send(event("hook", id, to: app))
    }

    private static func event(_ eventClass: StaticString, _ id: StaticString, to app: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: FourCharCode(fourCC: eventClass),
            eventID: FourCharCode(fourCC: id),
            targetDescriptor: app,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    /// Sends and waits (at most `timeout`); an error in the reply becomes an `AppleScriptFailure`
    /// with the same codes a script would report.
    private static func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
        } catch let error as NSError {
            throw AppleScriptFailure(code: error.code, message: error.localizedDescription)
        }
        if let number = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, number != 0 {
            let message = reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue ?? "Apple Event error"
            throw AppleScriptFailure(code: Int(number), message: message)
        }
        return reply
    }

    // MARK: Object specifiers

    /// `property <code> of <container>` (of the application when there is no container).
    static func property(_ code: StaticString, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
        specifier(want: "prop", form: "prop", data: NSAppleEventDescriptor(typeCode: FourCharCode(fourCC: code)), of: container)
    }

    /// `<class> <index> of <container>`.
    static func element(_ code: StaticString, index: Int32, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: code, form: "indx", data: NSAppleEventDescriptor(int32: index), of: container)
    }

    private static func specifier(want: StaticString, form: StaticString, data: NSAppleEventDescriptor,
                                  of container: NSAppleEventDescriptor?) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: FourCharCode(fourCC: want)), forKeyword: FourCharCode(fourCC: "want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: FourCharCode(fourCC: form)), forKeyword: FourCharCode(fourCC: "form"))
        record.setDescriptor(data, forKeyword: FourCharCode(fourCC: "seld"))
        record.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: FourCharCode(fourCC: "from"))
        return record.coerce(toDescriptorType: FourCharCode(fourCC: "obj ")) ?? record
    }
}
