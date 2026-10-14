import Darwin
import Foundation

/// Memory macOS counts twice, counted once again — with nothing taken out of memory.
///
/// macOS charges a page to the app once for every place it is mapped at and was touched through
/// (a 64 MB test mapping read 129 MB in Activity Monitor once it was touched through a second
/// mapping of the same memory, or through a copy-on-write copy of it). Two things in the app are
/// mapped twice:
///
/// - SwiftUI keeps every view graph's nodes in one table (AttributeGraph's). When the table is
///   full it maps the same memory again at a new, larger place (`AG::data::table::grow_region`)
///   and leaves the old place mapped (`vmmap`: "AttributeGraph Data (old mapping)"). With Settings
///   built, ~20 MB of the table stood in the footprint twice (measured, October 14: 218 MB, the
///   table's old places 19–21 MB of it).
/// - Core Animation hands a picture to the window server as a copy-on-write copy of its bytes
///   (`CA::Render::copy_image`): the wallpapers behind Settings ▸ Widgets' stage, ~11 MB, twice.
///
/// Mapping such a place onto itself (`mach_vm_remap` with overwrite, shared, not a copy) leaves
/// the same memory there — whatever still reads or writes through it goes on working — but as a
/// mapping nothing has been touched through yet, so the pages are charged once, through the
/// other place. The swap happens inside the kernel in one step: no thread ever finds the place
/// unmapped. A page touched through it again is simply counted again, until the next trim.
///
/// Only a place whose every page is also mapped by another, kept place is mapped again: the same
/// call on memory mapped once would take it out of the count while it stays in memory (the test
/// read 1 MB with 64 MB in use) — a number that says less than the truth. Never that.
nonisolated enum AliasTrim {
    struct Region: Equatable, Sendable {
        var address: UInt64
        var size: UInt64
        /// The memory behind it (the kernel's id of the object) and where in it the region begins.
        var object: UInt32
        var offset: UInt64
        var tag: UInt32
        var inheritance: UInt32
        /// Pages in memory, as the kernel counts them for the memory behind this region.
        var residentPages: UInt32
        /// Anonymous memory of the app's own that may be mapped twice.
        var isCandidate: Bool

        /// The allocator's own regions are never mapped again (it keeps its own books on them),
        /// and are the ones kept where a copy of one exists.
        var isMalloc: Bool { (1...12).contains(tag) }
    }

    /// Smaller ones are not worth a call.
    static let minimumSize: UInt64 = 256 << 10

    /// The places to map again: of every piece of memory mapped more than once, those wholly
    /// inside the range of the same memory another place maps — that one is kept: the allocator's
    /// own before any other, then the larger, then the one highest in the address space (the
    /// graph's table in use is the last one made, and so far that has been the highest; a wrong
    /// guess costs nothing but the page faults that count the place in use again).
    static func extras(in regions: [Region]) -> [Region] {
        var groups: [UInt32: [Region]] = [:]
        for region in regions where region.isCandidate && region.size >= minimumSize && region.object != 0 {
            groups[region.object, default: []].append(region)
        }
        var extras: [Region] = []
        for group in groups.values where group.count >= 2 {
            let ordered = group.sorted {
                if $0.isMalloc != $1.isMalloc { return $0.isMalloc }
                if $0.size != $1.size { return $0.size > $1.size }
                return $0.address > $1.address
            }
            var kept: [Region] = []
            for region in ordered {
                let isCovered = kept.contains { $0.offset <= region.offset && $0.offset + $0.size >= region.offset + region.size }
                if isCovered, !region.isMalloc { extras.append(region) } else { kept.append(region) }
            }
        }
        return extras.sorted { $0.address < $1.address }
    }

    /// The task's own regions, top level only (the shared cache is one of them, not thousands).
    static func regions() -> [Region] {
        var found: [Region] = []
        var address: mach_vm_address_t = 0
        let cache = sharedCache
        // Always forward, and never without end: a walk that found the same region again span on
        // a core for as long as the app ran (seen the night this was written).
        var steps = 0
        while steps < maximumSteps, let (region, next) = region(from: address), next > address {
            steps += 1
            // The system's libraries (thousands of regions, none of them ours to look at).
            if let cache, cache.contains(region.address) {
                address = max(cache.upperBound, next)
                continue
            }
            found.append(region)
            address = next
        }
        return found
    }

    private static let maximumSteps = 200_000

    /// Where the system's shared libraries are mapped (dyld's own call, looked up by name: without
    /// it they are walked through like everything else).
    private static let sharedCache: Range<mach_vm_address_t>? = {
        typealias Call = @convention(c) (UnsafeMutablePointer<Int>) -> UnsafeRawPointer?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_dyld_get_shared_cache_range") else { return nil }
        var length = 0
        guard let start = unsafeBitCast(symbol, to: Call.self)(&length), length > 0 else { return nil }
        let base = mach_vm_address_t(UInt(bitPattern: start))
        return base..<base + mach_vm_address_t(length)
    }()

    /// The first region at or after `address`, and where the next one may begin.
    private static func region(from address: mach_vm_address_t) -> (Region, mach_vm_address_t)? {
        var start = address
        var size: mach_vm_size_t = 0
        var depth: natural_t = 0
        var info = vm_region_submap_info_data_64_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int32.self, capacity: Int(count)) {
                mach_vm_region_recurse(mach_task_self_, &start, &size, &depth, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, size > 0 else { return nil }
        // Anonymous memory of the app's own, readable, shared or copy-on-write (mapped more than
        // once, or with another task), not wired. Not files, devices or surfaces.
        let shared = [SM_COW, SM_SHARED, SM_TRUESHARED, SM_PRIVATE_ALIASED, SM_SHARED_ALIASED].contains(Int32(info.share_mode))
        let readable = info.protection & VM_PROT_READ != 0
        let candidate = shared && readable && info.is_submap == 0 && info.external_pager == 0 && info.user_wired_count == 0
            && !excludedTags.contains(Int32(info.user_tag))
        let region = Region(address: start, size: size, object: info.object_id, offset: info.offset, tag: info.user_tag,
                            inheritance: info.inheritance, residentPages: info.pages_resident, isCandidate: candidate)
        return (region, start + size)
    }

    /// Shared with the window server or a driver, never the graph's.
    private static let excludedTags: Set<Int32> = [
        VM_MEMORY_IOSURFACE, VM_MEMORY_IOKIT, VM_MEMORY_IOACCELERATOR, VM_MEMORY_COREGRAPHICS, VM_MEMORY_CGIMAGE,
        VM_MEMORY_LAYERKIT, VM_MEMORY_STACK, VM_MEMORY_GUARD,
    ]

    private struct Done: Hashable { var address: UInt64; var size: UInt64; var object: UInt32 }
    /// The places already mapped again (on `queue`, or a test's thread).
    nonisolated(unsafe) private static var done: Set<Done> = []

    struct Outcome: Equatable, Sendable {
        var regions = 0
        /// What stood in the footprint a second time.
        var bytes: UInt64 = 0
    }

    /// Maps every extra place onto itself; what it took out of the count.
    @discardableResult static func trim() -> Outcome {
        var outcome = Outcome()
        let all = regions()
        let found = extras(in: all)
        Log.system.debug("alias trim: \(all.count, privacy: .public) regions, \(all.filter(\.isCandidate).count, privacy: .public) candidates, \(found.count, privacy: .public) extras")
        for extra in found {
            // Still the same place of the same memory (looked at again just before the call).
            guard let (now, _) = region(from: extra.address), now.address == extra.address, now.size == extra.size,
                  now.object == extra.object, now.isCandidate, now.residentPages > 0 else { continue }
            // Once is enough: nothing reads the table's old places again (they stayed at 0 KB in
            // memory through a whole tour, measured), and a place mapped again is a new one for
            // the kernel's count, not for the memory behind it.
            let key = Done(address: extra.address, size: extra.size, object: extra.object)
            guard !done.contains(key) else { continue }
            done.insert(key)
            var target = extra.address
            var current: vm_prot_t = 0, maximum: vm_prot_t = 0
            // (No tag among the flags: the call refuses one. `vmmap` goes on naming the table's.)
            let flags = VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE
            let result = mach_vm_remap(mach_task_self_, &target, extra.size, 0, flags, mach_task_self_, extra.address, 0,
                                       &current, &maximum, vm_inherit_t(now.inheritance))
            guard result == KERN_SUCCESS else {
                Log.system.debug("not mapped again (\(result, privacy: .public)): \(extra.size >> 10, privacy: .public) K, tag \(extra.tag, privacy: .public)")
                continue
            }
            Log.system.debug("mapped again: \(extra.size >> 10, privacy: .public) K at \(String(extra.address, radix: 16), privacy: .public), tag \(extra.tag, privacy: .public)")
            outcome.regions += 1
            outcome.bytes += UInt64(now.residentPages) * UInt64(getpagesize())
        }
        return outcome
    }

    private static let queue = DispatchQueue(label: "com.davidvarga.notchisland.aliastrim", qos: .background)
    nonisolated(unsafe) private static var pending: DispatchWorkItem?
    /// The footprint the last look left behind (read and written on `queue` only).
    nonisolated(unsafe) private static var lastFootprint: UInt64 = 0
    private static let lock = NSLock()

    /// The table's old places only come with its growth, and that shows in the footprint: nothing
    /// is looked for until it has grown by this much since the last look (a look walks the app's
    /// ~2 000 regions: a few milliseconds on an efficiency core).
    static let growthWorthALook: UInt64 = 4 << 20

    static func isWorthALook(footprint: UInt64, last: UInt64) -> Bool {
        last == 0 || footprint > last + growthWorthALook
    }

    /// A trim a few seconds from now, on a thread of its own at background quality of service;
    /// asked for again meanwhile, it waits anew (the table grows while views are built: once they
    /// are, not in between).
    static func soon(after seconds: TimeInterval = 4) {
        let work = DispatchWorkItem {
            guard isWorthALook(footprint: footprint(), last: lastFootprint) else { return }
            let before = footprint()
            let start = DispatchTime.now().uptimeNanoseconds
            let outcome = trim()
            lastFootprint = footprint()
            guard outcome.regions > 0, before > lastFootprint else { return }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            Log.system.notice("memory counted twice: \(outcome.regions, privacy: .public) places mapped again, footprint \(before >> 20, privacy: .public) → \(lastFootprint >> 20, privacy: .public) MB (\(ms, format: .fixed(precision: 1), privacy: .public) ms)")
        }
        lock.lock()
        pending?.cancel()
        pending = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// What Activity Monitor's Memory column shows for the app.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
