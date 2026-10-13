import Darwin
import Testing
@testable import NotchIslandKit

@Suite("Memory counted twice")
struct AliasTrimTests {
    private func region(_ address: UInt64, size: UInt64 = 1 << 20, object: UInt32, offset: UInt64 = 0, tag: UInt32 = 0,
                        candidate: Bool = true) -> AliasTrim.Region {
        AliasTrim.Region(address: address, size: size, object: object, offset: offset, tag: tag, inheritance: 0,
                         residentPages: 64, isCandidate: candidate)
    }

    @Test("Of memory mapped several times, all but the highest place are mapped again")
    func olderPlacesOfTheTable() {
        let old1 = region(0x1000_0000, object: 7), old2 = region(0x2000_0000, object: 7), inUse = region(0x3000_0000, object: 7)
        #expect(AliasTrim.extras(in: [inUse, old1, old2]) == [old1, old2])
    }

    @Test("Memory mapped once is never touched, whatever it is")
    func mappedOnceStays() {
        let alone = region(0x1000_0000, object: 7), other = region(0x2000_0000, object: 8)
        #expect(AliasTrim.extras(in: [alone, other]).isEmpty)
    }

    @Test("A place is mapped again only if another place maps all of the same memory")
    func onlyWhatIsWhollyCovered() {
        // The same object, but another part of it: both are counted once already.
        let first = region(0x1000_0000, object: 7, offset: 0), second = region(0x2000_0000, object: 7, offset: 1 << 20)
        #expect(AliasTrim.extras(in: [first, second]).isEmpty)
        // Half inside the other's range: not wholly covered.
        let wide = region(0x3000_0000, size: 2 << 20, object: 9, offset: 0)
        let straddling = region(0x1000_0000, size: 2 << 20, object: 9, offset: 1 << 20)
        #expect(AliasTrim.extras(in: [wide, straddling]).isEmpty)
        // Inside it: the smaller one goes, wherever it is.
        let inside = region(0x5000_0000, size: 1 << 20, object: 9, offset: 1 << 20)
        #expect(AliasTrim.extras(in: [wide, inside]) == [inside])
    }

    @Test("The allocator's own region is the one kept, and never mapped again")
    func allocatorRegionsStay() {
        let buffer = region(0x1000_0000, size: 9 << 20, object: 5, tag: UInt32(VM_MEMORY_MALLOC_LARGE))
        let copy = region(0x9000_0000, size: 8 << 20, object: 5, offset: 1 << 20, tag: UInt32(VM_MEMORY_ACCELERATE))
        #expect(AliasTrim.extras(in: [copy, buffer]) == [copy])
        let twin = region(0x9000_0000, size: 9 << 20, object: 5, tag: UInt32(VM_MEMORY_MALLOC_LARGE))
        #expect(AliasTrim.extras(in: [twin, buffer]).isEmpty)
    }

    @Test("Small places, files and devices are left alone")
    func whatIsNotLookedAt() {
        let small = region(0x1000_0000, size: 64 << 10, object: 3), smallTwin = region(0x2000_0000, size: 64 << 10, object: 3)
        #expect(AliasTrim.extras(in: [small, smallTwin]).isEmpty)
        let file = region(0x1000_0000, object: 4, candidate: false), fileTwin = region(0x2000_0000, object: 4, candidate: false)
        #expect(AliasTrim.extras(in: [file, fileTwin]).isEmpty)
        let unnamed = region(0x1000_0000, object: 0), unnamedTwin = region(0x2000_0000, object: 0)
        #expect(AliasTrim.extras(in: [unnamed, unnamedTwin]).isEmpty)
    }

    @Test("A look only after the footprint has grown")
    func looksAfterGrowth() {
        #expect(AliasTrim.isWorthALook(footprint: 40 << 20, last: 0))
        #expect(!AliasTrim.isWorthALook(footprint: 195 << 20, last: 192 << 20))
        #expect(AliasTrim.isWorthALook(footprint: 197 << 20, last: 192 << 20))
    }

    @Test("The walk over the process's regions ends, in order, without the system's libraries")
    func walkEnds() {
        let regions = AliasTrim.regions()
        #expect(regions.count > 10)
        #expect(regions.count < 50_000)
        #expect(zip(regions, regions.dropFirst()).allSatisfy { $0.address + $0.size <= $1.address })
    }

    @Test("Mapped again, the memory is the same and counted once")
    func trimKeepsTheMemory() throws {
        let size: mach_vm_size_t = 32 << 20
        var first: mach_vm_address_t = 0
        #expect(mach_vm_allocate(mach_task_self_, &first, size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS)
        defer { mach_vm_deallocate(mach_task_self_, first, size) }
        let bytes = UnsafeMutablePointer<UInt8>(bitPattern: UInt(first))!
        for index in stride(from: 0, to: Int(size), by: 4096) { bytes[index] = UInt8(truncatingIfNeeded: index >> 12) }
        var second: mach_vm_address_t = 0
        var current: vm_prot_t = 0, maximum: vm_prot_t = 0
        #expect(mach_vm_remap(mach_task_self_, &second, size, 0, VM_FLAGS_ANYWHERE, mach_task_self_, first, 0, &current, &maximum, VM_INHERIT_NONE) == KERN_SUCCESS)
        defer { mach_vm_deallocate(mach_task_self_, second, size) }
        let alias = UnsafeMutablePointer<UInt8>(bitPattern: UInt(second))!
        var sum = 0
        for index in stride(from: 0, to: Int(size), by: 4096) { sum &+= Int(alias[index]) }
        let twice = AliasTrim.footprint()
        let outcome = AliasTrim.trim()
        let once = AliasTrim.footprint()
        #expect(outcome.regions >= 1)
        // Counted once again: most of the 32 MB gone from the footprint (other tests run beside this one).
        #expect(twice > once && twice - once > 24 << 20)
        // The same memory through both places, still.
        bytes[4096 * 3] = 201
        #expect(alias[4096 * 3] == 201)
        alias[4096 * 5] = 77
        #expect(bytes[4096 * 5] == 77)
        #expect(sum > 0)
    }
}
