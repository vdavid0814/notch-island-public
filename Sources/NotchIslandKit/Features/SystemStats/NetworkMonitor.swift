import Darwin
import Foundation
import Observation

/// The Mac's download and upload speed, for the Network widget: the bytes every interface but the
/// loopback has carried, read every two seconds — only while a widget shows them.
@Observable final class NetworkMonitor {
    /// Bytes per second since the previous sample.
    private(set) var download: Double = 0
    private(set) var upload: Double = 0

    static let interval: TimeInterval = 2

    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previous: (received: UInt64, sent: UInt64, at: TimeInterval)?

    func startObserving() {
        observers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = Self.interval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopObserving() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
        previous = nil
    }

    private func sample() {
        guard let totals = Self.totals() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous, now > previous.at, totals.received >= previous.received, totals.sent >= previous.sent {
            let span = now - previous.at
            let down = Double(totals.received - previous.received) / span, up = Double(totals.sent - previous.sent) / span
            // Told only when the figure shown would change (whole kilobytes).
            if Self.rate(down) != Self.rate(download) { download = down }
            if Self.rate(up) != Self.rate(upload) { upload = up }
        }
        previous = (totals.received, totals.sent, now)
    }

    /// The bytes received and sent over every interface that is up, the loopback left out.
    nonisolated static func totals() -> (received: UInt64, sent: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0, interface.ifa_flags & UInt32(IFF_UP) != 0,
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    /// "1.2 MB/s": bytes a second as the widget writes them.
    nonisolated static func rate(_ bytesPerSecond: Double) -> String {
        let bytes = Int64(max(bytesPerSecond, 0))
        if bytes < 1000 { return "0 KB/s" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) + "/s"
    }
}
