import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// How the Mac around NotchIsland is set up: the menu bar, Dock and Spaces, the keyboard and its
/// shortcuts, appearance and accessibility, sound devices and Bluetooth, power and security, every
/// installed app (the ones known to fight over the notch, the HUD or the keys marked), and the
/// app's own log of this run.
///
/// Preferences are read with CFPreferences (no process started); everything here blocks, so it
/// runs only inside `@concurrent` functions, like `DiagnosticsProbes`.
nonisolated enum DiagnosticsEnvironment {
    static let menuBarTitle = "Menu bar, Dock & Spaces"
    static let keyboardTitle = "Keyboard & input"
    static let systemTitle = "System settings"
    static let appsTitle = "Installed apps"
    static let interferingKey = "May interfere"
    static let trailTitle = "Event trail (this run)"

    static func sections() -> [DiagnosticsReport.Section] {
        [menuBar(), keyboard(), systemSettings(), powerAndSecurity(), sound(), installedApps(), backgroundItems()]
    }

    // MARK: Menu bar, Dock, Spaces

    static func menuBar() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(menuBarTitle)
        for key in ["_HIHideMenuBar", "AppleMenuBarVisibleInFullscreen", "NSStatusItemSpacing", "NSStatusItemSelectionPadding",
                    "AppleShowScrollBars", "AppleReduceDesktopTinting", "AppleWindowTabbingMode", "AppleActionOnDoubleClick",
                    "NSAutomaticWindowAnimationsEnabled"] {
            section.add("global.\(key)", global(key))
        }
        // The Dock's own lists are in Installed apps: they differ on every Mac.
        add(domain: "com.apple.dock", as: "dock", to: &section, skipping: ["persistent-apps", "persistent-others", "recent-apps"])
        add(domain: "com.apple.WindowManager", as: "stageManager", to: &section)
        section.add("spaces.spans-displays", format(CFPreferencesCopyAppValue("spans-displays" as CFString, "com.apple.spaces" as CFString)))
        add(domain: "com.apple.controlcenter", as: "controlCenter", to: &section)
        add(domain: "com.apple.controlcenter", as: "controlCenter(host)", to: &section, host: kCFPreferencesCurrentHost)
        add(domain: "com.apple.menuextra.clock", as: "clock", to: &section)
        return section
    }

    // MARK: Keyboard

    /// The system's shortcut ids that matter here: ⌘Space and ⌥⌘Space (Spotlight, what NotchIsland's
    /// Siri takes over), ⌃Space and ⌃⌥Space (input sources).
    static let hotKeys = ["64": "⌘Space: Spotlight", "65": "⌥⌘Space: Finder search",
                          "60": "⌃Space: previous input source", "61": "⌃⌥Space: next input source"]

    static let fnUsage = ["0": "Do nothing", "1": "Change input source", "2": "Show emoji & symbols", "3": "Start dictation"]

    static func keyboard() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(keyboardTitle)
        let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        for (id, title) in Self.hotKeys.sorted(by: { $0.key < $1.key }) {
            let entry = hotKeys?[id] as? [String: Any]
            let enabled = (entry?["enabled"] as? NSNumber).map { $0.boolValue ? "on" : "off" } ?? "default (on)"
            let parameters = ((entry?["value"] as? [String: Any])?["parameters"] as? [Any]).map { format($0) } ?? ""
            section.add(title, enabled + (parameters.isEmpty ? "" : ", keys \(parameters)"))
        }
        let fn = format(CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString))
        section.add("fn / 🌐 key", fnUsage[fn] ?? (fn == "—" ? "default" : fn))
        section.add("fn keys are F1, F2… (fnState)", global("com.apple.keyboard.fnState"))
        for key in ["com.apple.swipescrolldirection", "KeyRepeat", "InitialKeyRepeat", "AppleKeyboardUIMode",
                    "ApplePressAndHoldEnabled", "com.apple.trackpad.forceClick", "com.apple.mouse.scaling"] {
            section.add("global.\(key)", global(key))
        }
        let sources = CFPreferencesCopyAppValue("AppleEnabledInputSources" as CFString, "com.apple.HIToolbox" as CFString) as? [[String: Any]] ?? []
        section.add("Input sources", sources.map { ($0["KeyboardLayout Name"] ?? $0["Bundle ID"] ?? $0["InputSourceKind"]).map { "\($0)" } ?? "?" }
            .joined(separator: ", "))
        section.add("Current layout", format(CFPreferencesCopyAppValue("AppleCurrentKeyboardLayoutInputSourceID" as CFString, "com.apple.HIToolbox" as CFString)))
        add(domain: "com.apple.AppleMultitouchTrackpad", as: "trackpad", to: &section)
        add(domain: "com.apple.Siri", as: "siri", to: &section)
        return section
    }

    // MARK: Appearance, accessibility, sound feedback

    static func systemSettings() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(systemTitle)
        for key in ["AppleInterfaceStyle", "AppleInterfaceStyleSwitchesAutomatically", "AppleAccentColor", "AppleHighlightColor",
                    "AppleLocale", "AppleMeasurementUnits", "AppleTemperatureUnit", "AppleICUForce24HourTime",
                    "com.apple.sound.beep.feedback", "com.apple.sound.uiaudio.enabled", "com.apple.springing.enabled",
                    "NSQuitAlwaysKeepsWindows", "AppleWindowTabbingMode"] {
            section.add("global.\(key)", global(key))
        }
        add(domain: "com.apple.universalaccess", as: "accessibility", to: &section)
        return section
    }

    // MARK: Power and security

    static func powerAndSecurity() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Power & security")
        section.add("pmset -g", DiagnosticsFormat.head(DiagnosticsProbes.run("/usr/bin/pmset", ["-g"]) ?? "unavailable", limit: 3000))
        section.add("csrutil status", DiagnosticsProbes.run("/usr/bin/csrutil", ["status"]) ?? "unavailable")
        section.add("spctl --status", DiagnosticsProbes.run("/usr/sbin/spctl", ["--status"]) ?? "unavailable")
        section.add("fdesetup status", DiagnosticsProbes.run("/usr/bin/fdesetup", ["status"]) ?? "unavailable")
        section.add("sw_vers", DiagnosticsProbes.run("/usr/bin/sw_vers", []) ?? "unavailable")
        return section
    }

    // MARK: Sound and Bluetooth

    static func sound() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Sound & Bluetooth")
        let output = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let input = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let system = defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
        for device in audioDevices() {
            var roles: [String] = []
            if device == output { roles.append("default output") }
            if device == system { roles.append("system sounds") }
            if device == input { roles.append("default input") }
            let outputs = channels(device, scope: kAudioObjectPropertyScopeOutput)
            let inputs = channels(device, scope: kAudioObjectPropertyScopeInput)
            var line = "\(transport(device)), \(outputs) out / \(inputs) in"
            if outputs > 0, let volume = volume(device) { line += String(format: ", volume %.0f%%", volume * 100) }
            if outputs > 0, let muted = muted(device) { line += muted ? ", muted" : "" }
            if !roles.isEmpty { line += " — " + roles.joined(separator: ", ") }
            section.add(deviceName(device) ?? "device \(device)", line)
        }
        let bluetooth = DiagnosticsProbes.run("/usr/sbin/system_profiler", ["-detailLevel", "mini", "SPBluetoothDataType"], timeout: 15)
        section.add("Bluetooth", DiagnosticsFormat.head(bluetooth ?? "unavailable", limit: 8000))
        return section
    }

    static func audioDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        return device
    }

    static func deviceName(_ device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    static func transport(_ device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return "unknown" }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return "built-in"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "Continuity"
        default: return String(format: "0x%08x", value)
        }
    }

    static func channels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func volume(_ device: AudioObjectID) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func muted(_ device: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    // MARK: Installed apps

    /// Apps known to take the notch, the volume/brightness HUD, the media keys, ⌘Space or the menu
    /// bar's space, matched in the name or bundle id (lowercased).
    static let interfering = ["notch", "alcove", "mediamate", "bartender", "jordanbaird.ice", "hiddenbar", "vanilla", "dozer",
                              "soundsource", "backgroundmusic", "eqmac", "bettertouchtool", "karabiner", "monitorcontrol", "lunar", "betterdisplay", "raycast", "alfred", "launchbar",
                              "sketchybar", "hud", "boring"]

    static func installedApps() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(appsTitle)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "\(home)/Applications", "/Applications/Setapp"]
        var interferingFound: [String] = []
        var total = 0
        for folder in folders {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }.sorted()
            guard !names.isEmpty else { continue }
            total += names.count
            let lines = names.map { name -> String in
                let info = Bundle(path: "\(folder)/\(name)")?.infoDictionary
                let id = info?["CFBundleIdentifier"] as? String ?? "?"
                let version = info?["CFBundleShortVersionString"] as? String ?? info?["CFBundleVersion"] as? String ?? "?"
                let title = String(name.dropLast(4))
                let key = "\(title) \(id)".lowercased()
                if id != Bundle.main.bundleIdentifier, interfering.contains(where: key.contains) {
                    interferingFound.append("\(title) \(version)")
                }
                return "\(title) — \(id) \(version)"
            }
            section.add(folder, lines.joined(separator: "\n"))
        }
        section.add("/System/Applications", ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Applications")) ?? [])
            .filter { $0.hasSuffix(".app") }.count.description + " apps")
        section.add("Apps", total)
        section.add(interferingKey, interferingFound.isEmpty ? "none" : interferingFound.joined(separator: ", "))
        let dock = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
        section.add("In the Dock", dock.compactMap { ($0["tile-data"] as? [String: Any])?["file-label"] as? String }.joined(separator: ", "))
        return section
    }

    /// Login items and launch agents: what starts by itself next to NotchIsland.
    static func backgroundItems() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Background items")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for folder in ["\(home)/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".plist") }.sorted()
            section.add(folder, names.isEmpty ? "none" : names.joined(separator: "\n"))
        }
        return section
    }

    // MARK: The app's own log

    /// This run's NotchIsland log, read in-process (no `log show`, which takes seconds): the last
    /// `limit` lines.
    static func trail(limit: Int = 400) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(trailTitle)
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", Log.subsystem))
            var lines: [String] = []
            lines.reserveCapacity(limit)
            let formatter = Date.ISO8601FormatStyle(includingFractionalSeconds: true).time(includingFractionalSeconds: true)
            for case let entry as OSLogEntryLog in entries {
                lines.append("\(entry.date.formatted(formatter)) \(level(entry.level)) [\(entry.category)] \(entry.composedMessage)")
                if lines.count > limit * 2 { lines.removeFirst(lines.count - limit) }
            }
            section.add("Lines", lines.count > limit ? "last \(limit)" : "\(lines.count)")
            section.add("Log", lines.suffix(limit).joined(separator: "\n"))
        } catch {
            section.add("Log", "unavailable: \(error.localizedDescription)")
        }
        return section
    }

    /// This run's log since `since`, read in-process in one pass: NotchIsland's own lines and every
    /// error or fault in the process, as `log show --style compact` writes them (so the same parsing
    /// applies), and the trail of NotchIsland's lines. For the light hourly report: `log show` cost
    /// ~0.6–1.8 s of CPU and the log daemon's work besides.
    static func ownLog(since: Date, limit: Int, trailLimit: Int = 400) -> (DiagnosticsReport.Attachment, DiagnosticsReport.Section) {
        var trail = DiagnosticsReport.Section(trailTitle)
        var lines: [String] = []
        var trailLines: [String] = []
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(at: store.position(date: since))
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let short = Date.ISO8601FormatStyle(includingFractionalSeconds: true).time(includingFractionalSeconds: true)
            var size = 0
            for case let entry as OSLogEntryLog in entries {
                let own = entry.subsystem == Log.subsystem
                let isError = entry.level == .error || entry.level == .fault
                guard own || isError else { continue }
                let type = switch entry.level {
                case .error: "E "
                case .fault: "Fa"
                case .info: "I "
                case .debug: "Db"
                default: "Df"
                }
                let line = "\(stamp.string(from: entry.date)) \(type) NotchIsland[\(pid):0] [\(entry.subsystem):\(entry.category)] \(entry.composedMessage)"
                lines.append(line)
                size += line.utf8.count + 1
                if size > limit * 2 { size -= (lines.first?.utf8.count ?? 0) + 1; lines.removeFirst() }
                if own, entry.level != .debug {
                    trailLines.append("\(entry.date.formatted(short)) \(level(entry.level)) [\(entry.category)] \(entry.composedMessage)")
                    if trailLines.count > trailLimit * 2 { trailLines.removeFirst(trailLines.count - trailLimit) }
                }
            }
            trail.add("Lines", trailLines.count > trailLimit ? "last \(trailLimit)" : "\(trailLines.count)")
            trail.add("Log", trailLines.suffix(trailLimit).joined(separator: "\n"))
        } catch {
            trail.add("Log", "unavailable: \(error.localizedDescription)")
        }
        let text = "Timestamp               Ty Process[PID:TID]\n" + lines.joined(separator: "\n")
        return (DiagnosticsReport.Attachment(name: "log.txt", text: DiagnosticsFormat.tail(text, limit: limit)), trail)
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "D"
        case .info: "I"
        case .notice: "N"
        case .error: "E"
        case .fault: "F"
        default: "?"
        }
    }

    // MARK: Preferences

    static func global(_ key: String) -> String {
        format(CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    /// Keys that are bookkeeping, not settings (dates, counters, caches, tokens): they differ on
    /// every Mac and every day, and would drown the real differences from the reference.
    static let bookkeeping = ["datestring", "postdate", "indicatortime", "lastnightshift", "heartbeat", "analytics", "stamp",
                              "mod-count", "history", "cache", "token", "uuid", "trash-full", "chrono", "liveactivitystate",
                              "version", "migrat", "educatio", "lastselected", "enabledever"]

    /// Every setting of `domain`, as "`prefix`.key"; binary values and `bookkeeping` left out.
    static func add(domain: String, as prefix: String, to section: inout DiagnosticsReport.Section,
                    host: CFString = kCFPreferencesAnyHost, skipping: Set<String> = []) {
        guard let values = CFPreferencesCopyMultiple(nil, domain as CFString, kCFPreferencesCurrentUser, host) as? [String: Any] else { return }
        for key in values.keys.sorted() where !skipping.contains(key) && !(values[key] is Data) {
            let lower = key.lowercased()
            guard !bookkeeping.contains(where: lower.contains) else { continue }
            section.add("\(prefix).\(key)", format(values[key]))
        }
    }

    /// A preference on one line: JSON for lists and dictionaries, "—" for none, at most 400 characters.
    static func format(_ value: Any?) -> String {
        guard let value else { return "—" }
        var text: String
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) {
            text = String(decoding: data, as: UTF8.self)
        } else if let data = value as? Data {
            text = "<\(data.count) bytes>"
        } else {
            text = "\(value)"
        }
        text = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return text.count > 400 ? String(text.prefix(400)) + "…" : text
    }
}
