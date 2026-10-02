import AppKit
import Contacts
import CoreBluetooth
import EventKit

/// Every permission NotchIsland can ask for: where it lives in System Settings, what macOS calls it
/// (for `tccutil`), and its current answer, read without showing a prompt.
nonisolated enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case automation
    case systemAudio
    case calendars
    case contacts
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .inputMonitoring: String(localized: "Input Monitoring")
        case .screenRecording: String(localized: "Screen Recording")
        case .automation: String(localized: "Automation")
        case .systemAudio: String(localized: "System Audio Recording")
        case .calendars: String(localized: "Calendars")
        case .contacts: String(localized: "Contacts")
        case .bluetooth: String(localized: "Bluetooth")
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard.fill"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .automation: "gearshape.2.fill"
        case .systemAudio: "waveform"
        case .calendars: "calendar"
        case .contacts: "person.crop.circle.fill"
        case .bluetooth: "wave.3.right"
        }
    }

    /// The anchor of its list in Privacy & Security.
    var pane: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        case .systemAudio: "Privacy_AudioCapture"
        case .calendars: "Privacy_Calendars"
        case .contacts: "Privacy_Contacts"
        case .bluetooth: "Privacy_Bluetooth"
        }
    }

    /// The service name `tccutil reset` takes.
    var tccService: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "ListenEvent"
        case .screenRecording: "ScreenCapture"
        case .automation: "AppleEvents"
        case .systemAudio: "AudioCapture"
        case .calendars: "Calendar"
        case .contacts: "AddressBook"
        case .bluetooth: "BluetoothAlways"
        }
    }

    /// Where to find it, as System Settings names it.
    var location: String {
        String(localized: "System Settings ▸ Privacy & Security ▸ \(listName)")
    }

    /// The list's own name in Privacy & Security (not always the permission's).
    var listName: String {
        switch self {
        case .systemAudio: String(localized: "Screen & System Audio Recording")
        case .screenRecording: String(localized: "Screen & System Audio Recording")
        default: title
        }
    }

    /// Lists macOS fills itself when the app asks: the switch is already there. The others need
    /// the app added with "+" if it is missing.
    var appearsWhenAsked: Bool {
        switch self {
        case .accessibility, .inputMonitoring, .screenRecording, .automation, .calendars, .contacts, .bluetooth: true
        case .systemAudio: false
        }
    }

    /// Whether a stale entry can be cleared with `tccutil` (all of them).
    var canReset: Bool { true }

    @MainActor func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// One permission's answer.
nonisolated enum PermissionStatus: Sendable, Equatable {
    case allowed
    case denied
    /// Never asked: the first request shows macOS's prompt.
    case notAsked
    /// Cannot be read without asking (an app that is not running, an unknown service).
    case unknown

    var isAllowed: Bool { self == .allowed }
}

/// The answers, read without prompting. Cheap: About reads them every couple of seconds while the
/// permissions are on screen, nothing reads them otherwise.
@MainActor enum PermissionProbe {
    static func status(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility: AXIsProcessTrusted() ? .allowed : .denied
        case .inputMonitoring: CGPreflightListenEventAccess() ? .allowed : preflight("kTCCServiceListenEvent")
        case .screenRecording: CGPreflightScreenCaptureAccess() ? .allowed : preflight("kTCCServiceScreenCapture")
        case .automation: combined(automationTargets.map { automation($0.bundleID) })
        case .systemAudio: preflight("kTCCServiceAudioCapture")
        case .calendars:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized, .limited: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        }
    }

    /// The apps Now Playing scripts when the MediaRemote adapter is missing.
    static let automationTargets: [(name: String, bundleID: String)] = [("Music", "com.apple.Music"), ("Spotify", "com.spotify.client")]

    static func automation(_ bundleID: String) -> PermissionStatus {
        // Asking about an app that is not running only logs errors; the answer waits for it.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .unknown }
        var target = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { pointer in
            guard AECreateDesc(typeApplicationBundleID, pointer, strlen(pointer), &target) == noErr else { return OSStatus(-1) }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        }
        switch status {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unknown
        }
    }

    private static func combined(_ statuses: [PermissionStatus]) -> PermissionStatus {
        if statuses.contains(.denied) { return .denied }
        if statuses.contains(.allowed) { return .allowed }
        if statuses.contains(.notAsked) { return .notAsked }
        return .unknown
    }

    /// TCC's own answer for services without a public check (`TCCAccessPreflight`, private):
    /// 0 granted, 1 denied, otherwise not decided. Absent, the answer is unknown.
    private static func preflight(_ service: String) -> PermissionStatus {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
        guard let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(symbol, to: Preflight.self)(service as CFString, nil) {
        case 0: return .allowed
        case 1: return .denied
        default: return .notAsked
        }
    }

    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY)
}
