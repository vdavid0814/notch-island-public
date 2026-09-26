import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import QuartzCore
import Synchronization

/// The music's loudness in five bands, left to right: bass, low mids, mids, high mids, treble —
/// what the compact equalizer's five bars show.
nonisolated struct SpectrumLevels: Sendable, Equatable {
    /// 0…1 per band, already evened out (see `SpectrumLeveler`).
    var bands: [Float] = Array(repeating: 0, count: SpectrumBands.count)
    /// `CACurrentMediaTime()` of the last buffer that was not silence (0: none yet).
    var lastSignal: CFTimeInterval = 0

    /// Sound came through within `window`: without the permission (or while nothing plays) a tap
    /// only ever delivers zeros, and the bars fall back to breathing.
    func hasSignal(now: CFTimeInterval = CACurrentMediaTime(), window: CFTimeInterval = 1) -> Bool {
        lastSignal > 0 && now - lastSignal < window
    }
}

/// Where the four bands lie, in hertz.
nonisolated enum SpectrumBands {
    static let edges: [Float] = [40, 150, 500, 1_500, 4_500, 14_000]
    static var count: Int { edges.count - 1 }

    /// The FFT bins (lower bound inclusive, upper exclusive) of each band, for `size` samples at
    /// `sampleRate`; every band gets at least one bin.
    static func bins(size: Int, sampleRate: Double) -> [Range<Int>] {
        let binWidth = Float(sampleRate) / Float(size)
        let last = size / 2
        return (0..<count).map { band in
            let low = max(1, min(Int((edges[band] / binWidth).rounded()), last - 1))
            let high = max(low + 1, min(Int((edges[band + 1] / binWidth).rounded()), last))
            return low..<high
        }
    }
}

/// Turns each band's raw power into a bar height, then moves the bar there on a spring.
///
/// # One yardstick for all five bars
///
/// Music is quieter the higher it goes: measured on a pop track, the five bands' mean bin power
/// sat near −24, −32, −40, −44 and −54 dB. The first version measured each band against its OWN
/// recent peak, so a treble that barely sounded still filled its bar — every bar stood high all
/// the time. Now:
///
/// 1. **The natural tilt is taken out** (`tilt`, about 6–7 dB per band, from that measurement), so
///    a mix with an even balance draws even bars and a band that is really quiet draws low.
/// 2. **All bands share one ceiling**, the loudest band's recent peak. It jumps up with a loud hit
///    and sinks slowly (`ceilingRelease`), and never below `minimumCeiling`, so a quiet passage or
///    a whisper does not get amplified to full height either.
/// 3. **A curve that keeps quiet low** (`exponent`): the top is left for what is actually loud.
/// 4. **Each band also has its own floor** (`floorRise`, `minimumSpan`): its recent quiet. With
///    one fixed floor a quiet band (the treble) moved only in a sliver near the bottom, and a held
///    note kept every bar hovering mid-way. Measured from its own floor up to the shared ceiling,
///    the treble swings visibly, and a held note sinks back toward the bottom as the floor rises
///    to meet it. The 10 dB minimum keeps a mere waver from filling the bar
///    (simulated: a ±1.5 dB waver moves a bar about 0.15, a hi-hat swings the treble 0.3 → 1).

///
/// # Smooth, not damped
///
/// The reading rises fast and falls a little slower, so a beat reads as a hit; the smoothing is in
/// the motion: a critically damped spring (`stiffness`) carries each bar to its target. It never
/// overshoots and its speed never jumps, so a waver becomes a soft sway while a real beat still
/// swings the bar through most of its height.
nonisolated struct SpectrumLeveler: Sendable {
    /// The span of a bar, in dB below the shared ceiling.
    static let range: Float = 28
    /// Added to each band (bass → treble) before comparing them.
    static let tilt: [Float] = [0, 7, 13, 19, 29]
    /// How fast the ceiling sinks after a peak, in dB per second.
    static let ceilingRelease: Float = 3
    /// The ceiling never sinks below this (tilt-corrected dB): quiet audio stays quiet.
    static let minimumCeiling: Float = -42
    /// Below this (dB of mean bin power) a band counts as silent.
    static let silence: Float = -95
    static let exponent: Float = 1.7
    /// A reading is stretched by this before it is capped at the top: 1.188 lets a bar reach its
    /// full height about 19% more easily (1.212, then 2% less).
    static let reach: Float = 1.188
    /// Each bar's own stretch on top of `reach`, bass → treble, tuned by ear: the right side
    /// answers more readily than the left (the treble ≈ 1.33 before the lean below), the three
    /// middle bars +5% then −3%, the bass bar a touch less (0.95, then −2%) — and the whole
    /// emphasis leaned 5% back toward the left (×1.05 on the bass easing to ×0.95 on the treble),
    /// then 2% of that back to the right (×0.98 → ×1.02), and the fourth bar +2%.
    static let sensitivity: [Float] = [0.958, 1.034, 1.1, 1.207, 1.289]
    /// Per analysis frame (30 a second), the share of the way the target moves to the new reading.
    static let attack: Float = 0.42
    static let decay: Float = 0.28
    /// The spring's angular frequency (rad/s): a little under a third of a second to arrive
    /// (15, then 2% softer).
    static let stiffness: Float = 14.7

    /// Each band's own floor rises this fast (dB per second) while the band holds steady, and
    /// drops at once to anything quieter: a held note sinks back toward the bottom, a pause reaches it.
    static let floorRise: Float = 4
    /// A band's own span never narrows below this (dB): a waver does not fill the bar.
    static let minimumSpan: Float = 10

    /// How strongly a taller neighbour lifts a bar: this share of the height between them.
    static let neighbourPull: Float = 0.10

    private(set) var ceiling: Float = SpectrumLeveler.minimumCeiling
    private var floors: [Float] = Array(repeating: SpectrumLeveler.minimumCeiling - SpectrumLeveler.range,
                                        count: SpectrumBands.count)
    private(set) var levels: [Float] = Array(repeating: 0, count: SpectrumBands.count)
    private var targets: [Float] = Array(repeating: 0, count: SpectrumBands.count)
    private var velocities: [Float] = Array(repeating: 0, count: SpectrumBands.count)

    /// One analysis frame: `decibels` per band, `elapsed` seconds since the previous one.
    mutating func update(decibels: [Float], elapsed: Float) {
        let dt = min(max(elapsed, 0.001), 0.1)
        let corrected = decibels.indices.map { band in
            decibels[band] > Self.silence ? decibels[band] + Self.tilt[min(band, Self.tilt.count - 1)] : -.infinity
        }
        let loudest = corrected.max() ?? -.infinity
        ceiling = max(loudest, ceiling - Self.ceilingRelease * dt, Self.minimumCeiling)
        let floor = ceiling - Self.range
        for band in levels.indices {
            var reading: Float = 0
            if corrected[band].isFinite {
                // The band's floor: its recent quiet, never deeper than the shared span and never so
                // close to the ceiling that a waver fills the bar.
                floors[band] = min(max(min(corrected[band], floors[band] + Self.floorRise * dt), floor),
                                   ceiling - Self.minimumSpan)
                reading = min(max((corrected[band] - floors[band]) / (ceiling - floors[band]), 0), 1)
                let gain = Self.reach * Self.sensitivity[min(band, Self.sensitivity.count - 1)]
                reading = min(pow(reading, Self.exponent) * gain, 1)
            }
            let rate = reading > targets[band] ? Self.attack : Self.decay
            targets[band] += (reading - targets[band]) * rate
        }

        // Neighbours pull each other up: a bar heads for its own target plus a share
        // (`neighbourPull`) of how far each neighbour stands above it — the tallest lifts the ones
        // beside it a little, like bars on a loose string. Only upward: a quiet neighbour never
        // drags a loud bar down. Measured on last frame's heights, so the pull is as smooth as
        // the bars themselves.
        let previous = levels
        for band in levels.indices {
            var goal = targets[band]
            for neighbour in [band - 1, band + 1] where previous.indices.contains(neighbour) {
                goal += Self.neighbourPull * max(previous[neighbour] - previous[band], 0)
            }
            goal = min(goal, 1)

            // Semi-implicit Euler on x'' = ω²(goal − x) − 2ω x' (critical damping).
            let omega = Self.stiffness
            velocities[band] += (omega * omega * (goal - levels[band]) - 2 * omega * velocities[band]) * dt
            levels[band] = min(max(levels[band] + velocities[band] * dt, 0), 1)
        }
    }
}

/// The FFT behind `AudioSpectrumTap`, run on the tap's I/O queue.
///
/// Everything is allocated up front: the I/O block must not allocate or wait. The only shared state
/// is `levels`, behind a mutex held for a copy of five floats.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    static let log2Size: vDSP_Length = 11
    static let size = 1 << Int(log2Size)
    /// Analyses per second: the bars redraw at 20–24 fps, more would be wasted work.
    static let rate: Double = 30

    let levels = Mutex(SpectrumLevels())

    private let sampleRate: Double
    let hop: Int
    /// Samples per analysis: `hop` rounded up to whole device buffers (set when the tap starts).
    var block: Int
    /// This cycle's analyses (capacity kept).
    private var batch: [SpectrumLevels] = []
    private let bins: [Range<Int>]
    private let setup: FFTSetup
    private var ring: [Float]
    private var ringIndex = 0
    private var sinceAnalysis = 0
    private var window: [Float]
    private var frame: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]
    private var decibels: [Float]
    /// One chunk of the I/O cycle's samples folded to mono.
    private var mono: [Float]
    static let chunk = 4096
    private var leveler = SpectrumLeveler()

    init?(sampleRate: Double) {
        guard sampleRate > 0, let setup = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2)) else { return nil }
        let size = Self.size
        self.sampleRate = sampleRate
        self.setup = setup
        hop = max(Int(sampleRate / Self.rate), 256)
        block = hop
        batch.reserveCapacity(16)
        bins = SpectrumBands.bins(size: size, sampleRate: sampleRate)
        ring = Array(repeating: 0, count: size)
        window = Array(repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        frame = Array(repeating: 0, count: size)
        real = Array(repeating: 0, count: size / 2)
        imaginary = Array(repeating: 0, count: size / 2)
        power = Array(repeating: 0, count: size / 2)
        decibels = Array(repeating: 0, count: SpectrumBands.count)
        mono = Array(repeating: 0, count: Self.chunk)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// One I/O cycle's worth of Float32 samples, interleaved or one buffer per channel.
    ///
    /// Vectorised (vDSP): the channels are summed per chunk rather than per sample. The per-sample
    /// loop walked the buffer list through its generic collection conformance for every frame
    /// (measured: most of this thread's own time).
    func consume(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mNumberChannels > 0 else { return }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / Int(first.mNumberChannels)
        guard frames > 0 else { return }
        var done = 0
        batch.removeAll(keepingCapacity: true)
        // In pieces that end on analysis boundaries: one I/O cycle may hold several analyses.
        while done < frames {
            let count = min(frames - done, Self.chunk, block - sinceAnalysis)
            var loud = false
            mono.withUnsafeMutableBufferPointer { mono in
                let out = mono.baseAddress!
                vDSP_vclr(out, 1, vDSP_Length(count))
                var channels = 0
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let stride = Int(buffer.mNumberChannels)
                    for channel in 0..<stride {
                        vDSP_vadd(data + done * stride + channel, vDSP_Stride(stride), out, 1, out, 1, vDSP_Length(count))
                    }
                    channels += stride
                }
                if channels > 1 {
                    var scale = 1 / Float(channels)
                    vDSP_vsmul(out, 1, &scale, out, 1, vDSP_Length(count))
                }
                var peak: Float = 0
                vDSP_maxmgv(out, 1, &peak, vDSP_Length(count))
                if peak > 1e-4 { loud = true }
                // Into the ring, wrapping at its end.
                ring.withUnsafeMutableBufferPointer { ring in
                    var copied = 0
                    while copied < count {
                        let run = min(count - copied, ring.count - ringIndex)
                        (ring.baseAddress! + ringIndex).update(from: out + copied, count: run)
                        ringIndex = (ringIndex + run) % ring.count
                        copied += run
                    }
                }
            }
            if loud {
                let now = CACurrentMediaTime()
                levels.withLock { $0.lastSignal = now }
            }
            done += count
            sinceAnalysis += count
            if sinceAnalysis >= block {
                let elapsed = Float(sinceAnalysis) / Float(sampleRate)
                sinceAnalysis = 0
                batch.append(analyse(elapsed: elapsed))
            }
        }
        if !batch.isEmpty {
            AudioSpectrumTap.deliver(batch, interval: CFTimeInterval(block) / sampleRate)
        }
    }

    private func analyse(elapsed: Float) -> SpectrumLevels {
        let size = ring.count
        // The ring in time order, windowed.
        let tail = size - ringIndex
        ring.withUnsafeBufferPointer { ring in
            frame.withUnsafeMutableBufferPointer { frame in
                frame.baseAddress!.update(from: ring.baseAddress! + ringIndex, count: tail)
                (frame.baseAddress! + tail).update(from: ring.baseAddress!, count: ringIndex)
            }
        }
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(size))
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                frame.withUnsafeBytes { bytes in
                    vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(size / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2Size, FFTDirection(FFT_FORWARD))
                // Bin 0 packs DC and Nyquist together; neither is in a band.
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(size / 2))
            }
        }
        let scale = 1 / Float(size * size)
        for (band, range) in bins.enumerated() {
            var mean: Float = 0
            power.withUnsafeBufferPointer { power in
                vDSP_meanv(power.baseAddress! + range.lowerBound, 1, &mean, vDSP_Length(range.count))
            }
            decibels[band] = 10 * log10(mean * scale + 1e-14)
        }
        leveler.update(decibels: decibels, elapsed: elapsed)
        let bands = leveler.levels
        return levels.withLock { levels -> SpectrumLevels in
            levels.bands = bands
            return levels
        }
    }
}

/// Takes each analysis on the tap's I/O thread, as it is made (`AudioSpectrumTap.addSink`).
///
/// The equalizer used to read the levels on a display link on the main thread, 20 times a second:
/// that alone woke the app ~50 times a second (Energy Impact ~0.9 of the ~2 while music played,
/// measured). The I/O thread is running anyway for the tap, so the bars are set from there.
nonisolated protocol SpectrumSink: AnyObject, Sendable {
    /// The analyses of one I/O cycle, oldest first, `interval` seconds apart (the first one
    /// `interval` after the last of the previous cycle).
    func spectrumDidUpdate(_ batch: [SpectrumLevels], interval: CFTimeInterval)
}

/// The system's audio output as five band levels, from a Core Audio process tap on every process
/// but this one (macOS 14.2+; the first start asks for "System Audio Recording").
///
/// Runs only while something holds it (`acquire`/`release`): the compact equalizer while music
/// plays. The tap feeds a private aggregate device clocked by the default output, and follows the
/// default output when it changes (AirPods connecting). Nothing is recorded or kept: each buffer is
/// folded into the five levels and dropped.
@Observable final class AudioSpectrumTap {
    static let shared = AudioSpectrumTap()

    /// Who hears each analysis, on the I/O thread.
    nonisolated private static let sinks = Mutex<[any SpectrumSink]>([])

    nonisolated static func addSink(_ sink: any SpectrumSink) {
        sinks.withLock { list in
            if !list.contains(where: { $0 === sink }) { list.append(sink) }
        }
    }

    nonisolated static func removeSink(_ sink: any SpectrumSink) {
        sinks.withLock { $0.removeAll { $0 === sink } }
    }

    nonisolated static func deliver(_ batch: [SpectrumLevels], interval: CFTimeInterval) {
        sinks.withLock { list in
            for sink in list { sink.spectrumDidUpdate(batch, interval: interval) }
        }
    }

    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var outputListener: AudioObjectPropertyListenerBlock?

    /// A release waits this long before the tap is torn down: the island rebuilding the compact
    /// view (a resize, a banner passing) should not restart it.
    static let stopDelay: Duration = .seconds(3)

    private init() {}

    /// The current levels (zeros while stopped).
    var levels: SpectrumLevels {
        session?.analyzer.levels.withLock { $0 } ?? SpectrumLevels()
    }

    func acquire() {
        holders += 1
        stopTask?.cancel()
        stopTask = nil
        if session == nil { start() }
    }

    func release() {
        holders = max(holders - 1, 0)
        guard holders == 0, stopTask == nil else { return }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.stopDelay)
            guard !Task.isCancelled, let self, self.holders == 0 else { return }
            self.stopTask = nil
            self.stop()
        }
    }

    private func start() {
        do {
            session = try Session()
            observeOutput()
            Log.media.notice("audio spectrum tap started")
        } catch {
            Log.media.error("audio spectrum tap failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func stop() {
        session = nil
        if let outputListener {
            var address = HAL.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(HAL.system, &address, .main, outputListener)
            self.outputListener = nil
        }
        Log.media.notice("audio spectrum tap stopped")
    }

    private func observeOutput() {
        guard outputListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
        var address = HAL.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(HAL.system, &address, .main, block) == noErr {
            outputListener = block
        }
    }

    private func outputChanged() {
        guard session != nil else { return }
        session = nil
        session = try? Session()
    }

    // MARK: Core Audio

    nonisolated struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) (\(status))" }
    }

    /// One tap, its aggregate device and the running I/O proc; torn down in reverse on deinit.
    nonisolated final class Session {
        let analyzer: SpectrumAnalyzer
        private var tap = AudioObjectID(kAudioObjectUnknown)
        private var aggregate = AudioObjectID(kAudioObjectUnknown)
        private var proc: AudioDeviceIOProcID?
        private let queue = DispatchQueue(label: "com.davidvarga.notchisland.spectrum", qos: .userInteractive)
        /// Analyses per I/O cycle (the buffer holds this many analysis blocks): the equalizer needs
        /// only each few seconds' character, so the I/O thread wakes ~6 times a second, not ~23.
        static let analysesPerCycle = 4

        init() throws {
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: HAL.ownProcess.map { [$0] } ?? [])
            description.uuid = UUID()
            description.name = "NotchIsland Spectrum"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try HAL.check("create tap", AudioHardwareCreateProcessTap(description, &tap))

            do {
                guard let tapUID = HAL.string(tap, kAudioTapPropertyUID) else { throw Failure(step: "tap uid", status: -1) }
                guard let output = HAL.defaultOutput, let outputUID = HAL.string(output, kAudioDevicePropertyDeviceUID) else {
                    throw Failure(step: "default output", status: -1)
                }
                var format = AudioStreamBasicDescription()
                var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                var address = HAL.address(kAudioTapPropertyFormat)
                try HAL.check("tap format", AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
                guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                      format.mBitsPerChannel == 32, let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate) else {
                    throw Failure(step: "tap format is not Float32", status: -1)
                }
                self.analyzer = analyzer

                let settings: [String: Any] = [
                    kAudioAggregateDeviceNameKey: "NotchIsland Spectrum",
                    kAudioAggregateDeviceUIDKey: UUID().uuidString,
                    kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                    kAudioAggregateDeviceIsPrivateKey: true,
                    kAudioAggregateDeviceIsStackedKey: false,
                    kAudioAggregateDeviceTapAutoStartKey: true,
                    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                    kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
                ]
                try HAL.check("create aggregate", AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate))
                try HAL.check("create io proc",
                              AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue, Self.ioBlock(analyzer)))
                // One I/O cycle per analysis: the analyser runs once `hop` samples have come in,
                // and at the default 512 frames the I/O thread woke four times for each at 48 kHz
                // (~94 times a second). The buffer becomes the whole number of default buffers
                // that makes up an analysis (2048 at 48 kHz, 1536 at 44.1), so the analyses see the
                // same samples at the same moments with a quarter (a third) of the wake-ups. The
                // size applies to this app only.
                var bufferAddress = HAL.address(kAudioDevicePropertyBufferFrameSize)
                var current: UInt32 = 0
                var bufferSize = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectGetPropertyData(aggregate, &bufferAddress, 0, nil, &bufferSize, &current) == noErr, current > 0 {
                    let block = (analyzer.hop + Int(current) - 1) / Int(current) * Int(current)
                    analyzer.block = block
                    // As many analyses per cycle as the device's largest buffer holds.
                    var range = AudioValueRange()
                    var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
                    var rangeAddress = HAL.address(kAudioDevicePropertyBufferFrameSizeRange)
                    var largest = block
                    if AudioObjectGetPropertyData(aggregate, &rangeAddress, 0, nil, &rangeSize, &range) == noErr {
                        largest = max(block, Int(range.mMaximum))
                    }
                    var frames = UInt32(block * max(1, min(Self.analysesPerCycle, largest / block)))
                    AudioObjectSetPropertyData(aggregate, &bufferAddress, 0, nil, bufferSize, &frames)
                }
                try HAL.check("start", AudioDeviceStart(aggregate, proc))
            } catch {
                Self.destroy(tap: tap, aggregate: aggregate, proc: proc)
                throw error
            }
        }

        deinit { Self.destroy(tap: tap, aggregate: aggregate, proc: proc) }

        /// Built outside any actor: the block runs on the I/O queue.
        private static func ioBlock(_ analyzer: SpectrumAnalyzer) -> AudioDeviceIOBlock {
            { _, input, _, _, _ in analyzer.consume(input) }
        }

        private static func destroy(tap: AudioObjectID, aggregate: AudioObjectID, proc: AudioDeviceIOProcID?) {
            if aggregate != kAudioObjectUnknown {
                if let proc {
                    AudioDeviceStop(aggregate, proc)
                    AudioDeviceDestroyIOProcID(aggregate, proc)
                }
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        }
    }

    nonisolated enum HAL {
        static let system = AudioObjectID(kAudioObjectSystemObject)
        static var defaultOutputAddress: AudioObjectPropertyAddress { address(kAudioHardwarePropertyDefaultOutputDevice) }

        static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
        }

        static func check(_ step: String, _ status: OSStatus) throws {
            guard status == noErr else { throw Failure(step: step, status: status) }
        }

        static var defaultOutput: AudioObjectID? {
            var device = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = defaultOutputAddress
            let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device)
            return status == noErr && device != kAudioObjectUnknown ? device : nil
        }

        /// This app's own audio process object, so the tap leaves out its own sounds.
        static var ownProcess: AudioObjectID? {
            var pid = getpid()
            var object = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            let status = AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
            return status == noErr && object != kAudioObjectUnknown ? object : nil
        }

        static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var address = address(selector)
            let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
            guard status == noErr, let value else { return nil }
            return value.takeRetainedValue() as String
        }
    }
}
