import Foundation
import IOKit

/// The System Management Controller: the fans' speeds and the sensors' temperatures, each read by a
/// four-letter key ("F0Ac", "Tp00"…). Anyone may read; only root may write (a fan's mode and its
/// target), so only the fan helper writes (`FanHelper`).
///
/// Talks to `AppleSMC` the way every SMC tool does: one struct of 80 bytes in and out of
/// `IOConnectCallStructMethod`'s selector 2, the command in its `data8`. The struct is built byte by
/// byte at its C offsets, so nothing depends on how Swift lays a struct out.
nonisolated final class SMC: @unchecked Sendable {
    /// A key's raw bytes and their type ("flt ", "fpe2", "ui8 "…).
    struct Value: Sendable, Equatable {
        var type: String
        var bytes: [UInt8]
    }

    /// The machine's SMC, opened once; nil where it cannot be opened.
    static let shared = SMC()

    private let connection: io_connect_t
    private let lock = NSLock()
    /// Each key's size and type, asked once.
    private var infos: [UInt32: (size: UInt32, type: UInt32)] = [:]

    private enum Command: UInt8 {
        case readBytes = 5, writeBytes = 6, readIndex = 8, readKeyInfo = 9
    }

    // The C struct's offsets (SMCKeyData_t).
    private enum Offset {
        static let key = 0, dataSize = 28, dataType = 32, result = 40, data8 = 42, data32 = 44, bytes = 48
    }

    private static let structSize = 80

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    // MARK: Reading

    func read(_ key: String) -> Value? {
        guard let code = Self.code(key) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let info = info(code) else { return nil }
        var input = Self.blank()
        Self.put(&input, Offset.key, code)
        Self.put(&input, Offset.dataSize, info.size)
        input[Offset.data8] = Command.readBytes.rawValue
        guard let output = call(input), output[Offset.result] == 0 else { return nil }
        let count = min(Int(info.size), 32)
        return Value(type: Self.text(info.type), bytes: Array(output[Offset.bytes ..< Offset.bytes + count]))
    }

    /// The key as a number, whatever its type; nil where it has none or is of a type not read here.
    func number(_ key: String) -> Double? {
        read(key).flatMap(Self.decode)
    }

    /// How many keys the SMC has.
    var keyCount: Int {
        guard let value = read("#KEY") else { return 0 }
        return Int(value.bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }

    /// The `index`th key's name.
    func key(at index: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var input = Self.blank()
        input[Offset.data8] = Command.readIndex.rawValue
        Self.put(&input, Offset.data32, UInt32(index))
        guard let output = call(input), output[Offset.result] == 0 else { return nil }
        return Self.text(Self.get(output, Offset.key))
    }

    // MARK: Writing (root only)

    /// Writes `bytes` (as many as the key holds) to `key`. False where the SMC refused: not root,
    /// or a key it does not let anyone set.
    @discardableResult func write(_ key: String, bytes: [UInt8]) -> Bool {
        guard let code = Self.code(key) else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let info = info(code) else { return false }
        var input = Self.blank()
        Self.put(&input, Offset.key, code)
        Self.put(&input, Offset.dataSize, info.size)
        input[Offset.data8] = Command.writeBytes.rawValue
        for (index, byte) in bytes.prefix(min(Int(info.size), 32)).enumerated() { input[Offset.bytes + index] = byte }
        guard let output = call(input) else { return false }
        return output[Offset.result] == 0
    }

    /// Writes `number` to `key` in the key's own type.
    @discardableResult func write(_ key: String, number: Double) -> Bool {
        guard let type = read(key)?.type, let bytes = Self.encode(number, type: type) else { return false }
        return write(key, bytes: bytes)
    }

    // MARK: Values

    static func decode(_ value: Value) -> Double? {
        let bytes = value.bytes
        switch value.type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(Int(bytes[0]) << 6 + Int(bytes[1]) >> 2)
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ", "ui16", "ui32":
            guard !bytes.isEmpty else { return nil }
            return Double(bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        default:
            return nil
        }
    }

    static func encode(_ number: Double, type: String) -> [UInt8]? {
        switch type {
        case "flt ":
            return withUnsafeBytes(of: Float(number)) { Array($0) }
        case "fpe2":
            let value = min(max(Int(number.rounded()), 0), 16383)
            return [UInt8(value >> 6), UInt8((value << 2) & 0xff)]
        case "ui8 ":
            return [UInt8(min(max(Int(number.rounded()), 0), 255))]
        default:
            return nil
        }
    }

    // MARK: The call

    /// Caller holds the lock.
    private func info(_ code: UInt32) -> (size: UInt32, type: UInt32)? {
        if let known = infos[code] { return known }
        var input = Self.blank()
        Self.put(&input, Offset.key, code)
        input[Offset.data8] = Command.readKeyInfo.rawValue
        guard let output = call(input), output[Offset.result] == 0 else { return nil }
        let info = (size: Self.get(output, Offset.dataSize), type: Self.get(output, Offset.dataType))
        guard (1...32).contains(info.size), info.type != 0 else { return nil }
        infos[code] = info
        return info
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = Self.blank()
        var size = Self.structSize
        let result = input.withUnsafeBytes { inBytes in
            output.withUnsafeMutableBytes { outBytes in
                IOConnectCallStructMethod(connection, 2, inBytes.baseAddress, Self.structSize, outBytes.baseAddress, &size)
            }
        }
        return result == KERN_SUCCESS ? output : nil
    }

    private static func blank() -> [UInt8] { [UInt8](repeating: 0, count: structSize) }

    private static func put(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        withUnsafeBytes(of: value) { for index in 0..<4 { buffer[offset + index] = $0[index] } }
    }

    private static func get(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        buffer[offset ..< offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    /// "F0Ac" as the number the SMC knows it by (its four letters, the first highest).
    static func code(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func text(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, as: UTF8.self)
    }
}
