import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The installer shares only its own container with SideOS. No arbitrary host
/// path or file URL is accepted across this narrow picker handoff.
enum TahoeHostPickerHandoff {
    static let notification = "com.sideos.installer.pick-ipa"
    static let channelEnvironment = "SI_HOST_IPA_PICKER_CHANNEL"
    static let metadataLimit = 16_384
    static let lifetime: TimeInterval = 600
    enum Action: String, Codable, Sendable { case choose, cancel }
    enum Status: String, Codable, Sendable { case selected, cancelled, failed }
    struct Request: Codable, Equatable, Sendable {
        let id: UUID
        let action: Action
        let created: Date
        var isFresh: Bool { isFresh(at: Date()) }
        func isFresh(at now: Date) -> Bool { (-30...TahoeHostPickerHandoff.lifetime).contains(now.timeIntervalSince(created)) }
    }
    struct Response: Codable, Equatable, Sendable {
        let id: UUID
        let status: Status
        var filename: String? = nil
        var message: String? = nil
    }
    static func root(home: URL, channel: UUID) -> URL {
        home.appendingPathComponent("Library/Caches/SideOSHostPicker", isDirectory: true)
            .appendingPathComponent(channel.uuidString, isDirectory: true)
    }
    static func validFilename(_ value: String) -> Bool {
        value.utf8.count <= 240 && value.count > 4 &&
        !value.contains("/") && !value.contains("\\") && !value.contains("\0") &&
        value.lowercased().hasSuffix(".ipa") && value != "." && value != ".."
    }
    static func selectedURL(_ response: Response, root: URL) -> URL? {
        guard response.status == .selected, let name = response.filename, validFilename(name) else { return nil }
        let url = root.appendingPathComponent("imports", isDirectory: true)
            .appendingPathComponent(response.id.uuidString, isDirectory: true).appendingPathComponent(name)
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base) else { return nil }
        return url
    }
    static func temporaryCopy(_ url: URL, temporaryDirectory: URL) -> URL? {
        let base = temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return resolved.path.hasPrefix(base.path + "/") ? resolved : nil
    }
    static func stagedDirectory(for url: URL, home: URL) -> URL? {
        let base = home.appendingPathComponent("Library/Caches/SideOSHostPicker", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(base.path + "/") else { return nil }
        let parts = Array(resolved.pathComponents.dropFirst(base.pathComponents.count))
        guard parts.count == 4, let channel = UUID(uuidString: parts[0]), parts[0] == channel.uuidString,
              parts[1] == "imports", let request = UUID(uuidString: parts[2]), parts[2] == request.uuidString,
              validFilename(parts[3]) else { return nil }
        return resolved.deletingLastPathComponent()
    }
    static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let fd = url.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, UInt32(info.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG),
              info.st_size <= metadataLimit else { throw CocoaError(.fileReadTooLarge) }
        let data = try file.read(upToCount: metadataLimit + 1) ?? Data()
        guard data.count <= metadataLimit else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, at url: URL) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= metadataLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}
