import Darwin

/// Hands memory the app has freed back to the system.
///
/// Settings and Siri build large view graphs that are torn down when they close, but the allocator
/// keeps the freed pages dirty for reuse, so the footprint stayed where it peaked (measured: ~50 MB
/// of small-allocation pages after one visit to Settings, about half of them free). Releasing them
/// is a few milliseconds of work, done once, a moment after the surface has gone.
@MainActor enum MemoryRelief {
    private static var pending: Task<Void, Never>?

    static func afterLargeSurfaceClosed() {
        pending?.cancel()
        pending = Task {
            // After the close animation and the teardown it ends in.
            try? await Task.sleep(for: .seconds(2), tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            pending = nil
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
