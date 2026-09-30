import AppKit
import EventKit
import Foundation
import Observation

/// One coming event, as the Up Next widget and Spotlight show it.
nonisolated struct CalendarEvent: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    /// The calendar's colour.
    var red: Double
    var green: Double
    var blue: Double
    var location: String?
}

nonisolated struct CalendarInfo: Sendable, Equatable, Identifiable {
    var id: String
    var title: String
}

private nonisolated struct StoreBox: @unchecked Sendable {
    let store: EKEventStore
}

/// The user's coming events, for the Up Next widget and Spotlight's calendar.
///
/// Energy: nothing is read until someone holds a lease, and nothing polls. While held, the events
/// are read once off the main thread, again when Calendar's store says it changed (its own
/// notification), and once as the first of them ends — never on a timer. Access is asked for only
/// by `requestAccess` (an explicit button), never by showing a widget or a picture of one.
@Observable final class CalendarService {
    nonisolated enum Access: Sendable, Equatable {
        case notDetermined, denied, granted
    }

    private(set) var access: Access
    /// From now, soonest first: at most `limit`, up to a week ahead. Empty until a lease reads them.
    private(set) var events: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []

    nonisolated static let limit = 12
    nonisolated static let horizon: TimeInterval = 7 * 86400

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var changeToken: (any NSObjectProtocol)?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init() {
        access = Self.currentAccess()
    }

    nonisolated static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Asks macOS for the calendars (its own prompt, once). Only from a button the user pressed.
    func requestAccess() {
        guard access == .notDetermined else {
            // Decided before: only System Settings changes it.
            if access == .denied, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.store.requestFullAccessToEvents()
            self.access = Self.currentAccess()
            if self.holders > 0 { self.read() }
        }
    }

    func acquire() {
        holders += 1
        guard holders == 1 else { return }
        access = Self.currentAccess()
        changeToken = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        read()
    }

    func release() {
        holders = max(holders - 1, 0)
        guard holders == 0 else { return }
        if let changeToken { NotificationCenter.default.removeObserver(changeToken) }
        changeToken = nil
        readTask?.cancel()
        readTask = nil
        expiryTask?.cancel()
        expiryTask = nil
    }

    private func read() {
        guard access == .granted, holders > 0 else { return }
        readTask?.cancel()
        // The store is read off the main thread (EventKit's stores may be used from any one).
        let box = StoreBox(store: store)
        readTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.fetch(box.store, now: Date()) }.value
            guard !Task.isCancelled, let self, self.holders > 0 else { return }
            if result.events != self.events { self.events = result.events }
            if result.calendars != self.calendars { self.calendars = result.calendars }
            self.scheduleExpiry()
        }
    }

    /// Once, as the first event ends: it leaves the list then.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let end = events.map(\.end).min() else { return }
        let wait = max(end.timeIntervalSinceNow, 1) + 1
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.read()
        }
    }

    nonisolated private static func fetch(_ store: EKEventStore, now: Date) -> (events: [CalendarEvent], calendars: [CalendarInfo]) {
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(horizon), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.startDate, $0.title ?? "") < ($1.startDate, $1.title ?? "") }
            .prefix(limit * 3)
            .map { event -> CalendarEvent in
                let color = (event.calendar.cgColor).flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
                return CalendarEvent(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "",
                                     start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                                     calendarID: event.calendar.calendarIdentifier,
                                     red: Double(color?.redComponent ?? 0.4), green: Double(color?.greenComponent ?? 0.6),
                                     blue: Double(color?.blueComponent ?? 1), location: event.location)
            }
        return (Array(events), calendars.map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }.sorted { $0.title < $1.title })
    }

    /// The coming events of the given calendars (nil or empty: all of them), at most `count`.
    func upcoming(calendars ids: [String]?, count: Int) -> [CalendarEvent] {
        let chosen = ids.flatMap { $0.isEmpty ? nil : Set($0) }
        return Array(events.filter { chosen?.contains($0.calendarID) ?? true }.prefix(count))
    }

    /// For the pictures in Settings: nothing is read.
    nonisolated static func samples(now: Date) -> [CalendarEvent] {
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now
        return [
            CalendarEvent(id: "1", title: String(localized: "Design Review"), start: hour, end: hour.addingTimeInterval(3600), isAllDay: false,
                          calendarID: "", red: 0.35, green: 0.62, blue: 1, location: nil),
            CalendarEvent(id: "2", title: String(localized: "Lunch with Anna"), start: hour.addingTimeInterval(2 * 3600),
                          end: hour.addingTimeInterval(3 * 3600), isAllDay: false, calendarID: "", red: 1, green: 0.55, blue: 0.2, location: nil),
            CalendarEvent(id: "3", title: String(localized: "Gym"), start: hour.addingTimeInterval(6 * 3600),
                          end: hour.addingTimeInterval(7 * 3600), isAllDay: false, calendarID: "", red: 0.3, green: 0.8, blue: 0.45, location: nil),
            CalendarEvent(id: "4", title: String(localized: "Flight to Lisbon"), start: hour.addingTimeInterval(22 * 3600),
                          end: hour.addingTimeInterval(25 * 3600), isAllDay: false, calendarID: "", red: 0.8, green: 0.4, blue: 0.95, location: nil),
        ]
    }
}
