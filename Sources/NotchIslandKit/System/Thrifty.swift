import Foundation

/// Work that can wait a moment — decoding pictures, drawing icons — run one piece at a time on a
/// single thread at utility QoS.
///
/// On Apple silicon the same CPU time costs far more energy on several performance cores at full
/// clock than on one core that may run slowly: drawing Siri's app icons in parallel from the
/// gallery's cells took 2.2 W for half a second (Activity Monitor ~250), for ~0.3 s of CPU
/// (measured). One at a time at utility QoS, the icons arrive a little later for a fraction of the
/// energy.
nonisolated enum Thrifty {
    private static let queue = DispatchQueue(label: "com.davidvarga.notchisland.thrifty", qos: .utility)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
