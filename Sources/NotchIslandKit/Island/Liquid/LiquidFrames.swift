import CoreGraphics
import CryptoKit
import Foundation

/// The liquid card's frames: its outline for every 1/120 s of a move (`LiquidField`), and where
/// they are kept between launches.
///
/// Every move is worked out as if it started at `nominal`, a fixed moment, so the same move always
/// gives the same paths, bit for bit, whenever and wherever it is worked out. Worked out at
/// `Date()` instead, the times inside a move (`start + i / 120`, less `start`) differed in their
/// last bits from one run to the next.
nonisolated enum LiquidFrames {
    static let rate: Double = 120
    static let nominal = Date(timeIntervalSinceReferenceDate: 0)

    /// One move of the liquid: how it goes, for how long, and the window it is drawn in.
    struct Move: Sendable {
        let make: @Sendable (Date) -> LiquidCardState.Motion
        let duration: TimeInterval
        let notch: CGRect
        let frame: CGRect

        /// Its outline at every frame, in the window's coordinates.
        func paths() -> [CGPath] {
            let motion = make(nominal)
            let leftNotch: Date? = if case .out = motion { nominal } else { nil }
            let count = max(2, Int((duration * rate).rounded(.up)) + 1)
            let clip = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + LiquidCardState.overdraw)
            var move = CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            return (0..<count).map { index in
                let scene = LiquidCardState.scene(motion: motion, leftNotch: leftNotch, notch: notch,
                                                  at: nominal.addingTimeInterval(min(Double(index) / rate, duration)))
                return LiquidField.path(scene, clip: clip).copy(using: &move) ?? CGMutablePath()
            }
        }
    }

    /// Everything besides the move itself that shapes its frames: the field's and the flow's
    /// constants, and the build (for the shapes' numbers written inline, and the code itself) with
    /// the executable's date, so a rebuild under the same build number (tuning by eye) never plays
    /// the frames of the one before.
    struct Recipe: Equatable {
        var smoothing = LiquidField.smoothing
        var cell = LiquidField.cell
        var curves = [LiquidFlow.out, LiquidFlow.back, LiquidFlow.move]
        var overdraw = LiquidCardState.overdraw
        var absorb = LiquidCardState.absorb
        var rate = LiquidFrames.rate
        var build = Recipe.currentBuild

        static var currentBuild: String {
            let number = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let built = (try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            return "\(number)@\(built)"
        }

        /// Names the folder the frames made with it are kept in.
        var id: String {
            let curves = curves.map { "\($0.duration),\($0.overshoot)" }.joined(separator: ";")
            return LiquidFrames.hash("\(smoothing)|\(cell)|\(curves)|\(overdraw)|\(absorb)|\(rate)|\(build)")
        }
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The frames on disk: one lzfse-compressed file of doubles per move, in a folder per recipe.
    /// A relaunch reads a move's frames back in a few milliseconds instead of tracing them again
    /// (~0.3 s of CPU for the four moves `LiquidCard.prewarm` works out).
    struct Store: Sendable {
        let root: URL
        var recipe = Recipe().id

        static let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { Store(root: $0.appendingPathComponent("com.davidvarga.notchisland/LiquidFrames", isDirectory: true)) }

        func file(for key: String) -> URL {
            root.appendingPathComponent(recipe, isDirectory: true).appendingPathComponent(LiquidFrames.hash(key) + ".lzfse")
        }

        /// The move's frames from disk, or worked out and kept there. `key` says where it goes
        /// (`LiquidCard`'s frames cache key).
        func frames(_ move: Move, key: String) -> [CGPath] {
            if let paths = load(key) { return paths }
            let paths = move.paths()
            save(paths, as: key)
            return paths
        }

        func load(_ key: String) -> [CGPath]? {
            guard let data = try? Data(contentsOf: file(for: key)),
                  let raw = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
            return LiquidFrames.decode(raw)
        }

        /// Frames of an earlier recipe (another build) go as the first of a new one is kept.
        func save(_ paths: [CGPath], as key: String) {
            let folder = root.appendingPathComponent(recipe, isDirectory: true)
            let manager = FileManager.default
            if !manager.fileExists(atPath: folder.path) {
                for old in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                    try? manager.removeItem(at: old)
                }
                try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            guard let data = try? (encode(paths) as NSData).compressed(using: .lzfse) as Data else { return }
            try? data.write(to: file(for: key), options: .atomic)
        }
    }

    // MARK: Encoding

    /// Element codes: a move to or a line to a point (followed by its x and y), a closed subpath,
    /// the end of a path.
    private static let moveCode: Double = 0, lineCode: Double = 1, closeCode: Double = 2, endCode: Double = 3

    /// The paths as doubles (`LiquidField` draws only moves, lines and closes).
    static func encode(_ paths: [CGPath]) -> Data {
        var values: [Double] = []
        for path in paths {
            path.applyWithBlock { element in
                let points = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: values += [moveCode, points[0].x, points[0].y]
                case .addLineToPoint: values += [lineCode, points[0].x, points[0].y]
                case .closeSubpath: values.append(closeCode)
                default: break
                }
            }
            values.append(endCode)
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// The paths back, exactly as encoded; nil for a file that is not whole.
    static func decode(_ data: Data) -> [CGPath]? {
        guard data.count % MemoryLayout<Double>.size == 0 else { return nil }
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
        var paths: [CGPath] = []
        var path = CGMutablePath()
        var index = 0
        while index < values.count {
            switch values[index] {
            case moveCode, lineCode:
                guard index + 2 < values.count else { return nil }
                let point = CGPoint(x: values[index + 1], y: values[index + 2])
                if values[index] == moveCode { path.move(to: point) } else { path.addLine(to: point) }
                index += 3
            case closeCode:
                path.closeSubpath()
                index += 1
            case endCode:
                paths.append(path)
                path = CGMutablePath()
                index += 1
            default:
                return nil
            }
        }
        return paths
    }
}
