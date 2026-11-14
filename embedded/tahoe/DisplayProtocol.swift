import Foundation

enum TahoeDisplayTiming {
    static let framesPerSecond = 60
    static let frameInterval: Duration = .nanoseconds((1_000_000_000 + Int64(framesPerSecond) - 1) / Int64(framesPerSecond))
    static func delay(afterCapture elapsed: Duration) -> Duration {
        // Even an over-budget capture must suspend so UIKit can process input.
        max(.milliseconds(1), frameInterval - elapsed)
    }
}

enum TahoeDisplayError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

struct TahoeDisplayMode: Codable, Equatable, Sendable {
    let width: Int, height: Int, pointsWide: Int, pointsHigh: Int
    var codedWidth: Int { (width + 1) & ~1 }
    var codedHeight: Int { (height + 1) & ~1 }
    func validate() throws {
        guard (320...4096).contains(width), (240...4096).contains(height), width * height <= 8_388_608,
              (240...4096).contains(pointsWide), (240...4096).contains(pointsHigh),
              width >= pointsWide, height >= pointsHigh, width <= pointsWide * 4, height <= pointsHigh * 4,
              abs(Double(width) / Double(pointsWide) - Double(height) / Double(pointsHigh)) < 0.02 else {
            throw TahoeDisplayError.invalid("Unsupported display size. Rotate before connecting, or use a smaller window.")
        }
    }
}

/// Display-only protocol. No input, launch, file-access or arbitrary commands.
struct TahoeDisplayControl: Codable, Sendable {
    var version = 1
    let type: String
    var mode: TahoeDisplayMode? = nil
    var sequence: UInt64? = nil
    func validate() throws {
        guard version == 1 else { throw TahoeDisplayError.invalid("Update SideOS on both devices.") }
        switch type {
        case "offer", "accept": guard let mode else { throw TahoeDisplayError.invalid("Missing display size.") }; try mode.validate()
        case "ack": guard let sequence, sequence > 0 else { throw TahoeDisplayError.invalid("Invalid frame acknowledgement.") }
        case "ping", "pong", "bye": break
        default: throw TahoeDisplayError.invalid("This connection accepts display data only.")
        }
    }
}

struct TahoeDisplayPacket: Sendable {
    static let limit = 12 * 1024 * 1024
    let kind: UInt8
    let data: Data
    func encoded() throws -> Data {
        guard kind == 1 || kind == 2, !data.isEmpty, data.count < Self.limit else { throw TahoeDisplayError.invalid("Invalid display packet.") }
        var length = UInt32(data.count + 1).bigEndian
        var result = Data(bytes: &length, count: 4); result.append(kind); result.append(data); return result
    }
}

struct TahoeDisplayParser {
    private var bytes = Data()
    mutating func append(_ data: Data) throws -> [TahoeDisplayPacket] {
        guard data.count <= 65_536, bytes.count + data.count <= TahoeDisplayPacket.limit + 65_540 else { throw TahoeDisplayError.invalid("Display receive limit exceeded.") }
        bytes.append(data)
        var result: [TahoeDisplayPacket] = []
        while bytes.count >= 4 {
            let count = bytes.prefix(4).reduce(0) { $0 * 256 + Int($1) }
            guard count > 1, count <= TahoeDisplayPacket.limit else { throw TahoeDisplayError.invalid("Invalid display packet length.") }
            guard bytes.count >= count + 4 else { break }
            let type = bytes[bytes.startIndex + 4]
            guard type == 1 || type == 2, result.count < 128 else { throw TahoeDisplayError.invalid("Invalid display packet type or rate.") }
            result.append(TahoeDisplayPacket(kind: type, data: Data(bytes.dropFirst(5).prefix(count - 1))))
            bytes = Data(bytes.dropFirst(count + 4))
        }
        return result
    }
}

struct TahoeDisplayFrame: Codable, Sendable {
    let width: Int, height: Int
    let sequence: UInt64
    let parameters: [Data]
    func packet(_ sample: Data) throws -> Data {
        let header = try JSONEncoder().encode(self)
        guard header.count < 65_536, !sample.isEmpty else { throw TahoeDisplayError.invalid("Invalid encoded frame.") }
        var size = UInt32(header.count).bigEndian
        var data = Data(bytes: &size, count: 4); data.append(header); data.append(sample); return data
    }
    static func unpack(_ data: Data, mode: TahoeDisplayMode) throws -> (Self, Data) {
        guard data.count > 4 else { throw TahoeDisplayError.invalid("Short encoded frame.") }
        let size = data.prefix(4).reduce(0) { $0 * 256 + Int($1) }
        guard size > 0, size < 65_536, data.count > size + 4 else { throw TahoeDisplayError.invalid("Invalid frame header.") }
        let header = try JSONDecoder().decode(Self.self, from: data.subdata(in: 4..<(4 + size)))
        guard header.width == mode.codedWidth, header.height == mode.codedHeight, header.sequence > 0,
              header.parameters.count == 2, header.parameters.allSatisfy({ !$0.isEmpty && $0.count <= 16_384 }) else {
            throw TahoeDisplayError.invalid("Frame does not match the paired display.")
        }
        return (header, Data(data.dropFirst(4 + size)))
    }
}

/// Credits cover capture, encode, network send AND decoder consumption.
/// Reordered/duplicate acknowledgements never release another frame's slot.
final class TahoeDisplayCredits: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UInt64: (sent: Bool, consumed: Bool, began: TimeInterval)] = [:]
    func begin(_ sequence: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard sequence > 0, pending.count < 2, pending[sequence] == nil else { return false }
        pending[sequence] = (false, false, ProcessInfo.processInfo.systemUptime); return true
    }
    func sent(_ sequence: UInt64, okay: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard var item = pending[sequence] else { return }
        if !okay || item.consumed { pending.removeValue(forKey: sequence) }
        else { item.sent = true; pending[sequence] = item }
    }
    func consumed(_ sequence: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard var item = pending[sequence] else { return }
        if item.sent { pending.removeValue(forKey: sequence) }
        else { item.consumed = true; pending[sequence] = item }
    }
    var oldestAge: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return pending.values.map { ProcessInfo.processInfo.systemUptime - $0.began }.max() ?? 0
    }
    func reset() { lock.lock(); pending.removeAll(); lock.unlock() }
}
