import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Hold the actual private directory open. Relative openat operations refuse
/// symlinks, so a guest cannot redirect a host read/write outside its container.
final class TahoeHostPickerDirectory: @unchecked Sendable {
    let root: URL
    private let descriptor: Int32
    init(home: URL, channel: UUID, create: Bool = true) throws {
        root = TahoeHostPickerHandoff.root(home: home.resolvingSymlinksInPath().standardizedFileURL, channel: channel)
        var current = home.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard current >= 0 else { throw Self.failure() }
        do {
            for part in ["Library", "Caches", "SideOSHostPicker", channel.uuidString] {
                let next = try Self.directory(at: current, name: part, create: create)
                close(current); current = next
            }
            descriptor = current
        } catch { close(current); throw error }
    }
    deinit { close(descriptor) }
    func request() throws -> TahoeHostPickerHandoff.Request {
        let fd = "request.json".withCString { openat(descriptor, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw Self.failure() }
        let data = try Self.readMetadata(fd: fd)
        return try JSONDecoder().decode(TahoeHostPickerHandoff.Request.self, from: data)
    }
    func respond(_ response: TahoeHostPickerHandoff.Response) throws {
        let data = try JSONEncoder().encode(response)
        guard data.count <= TahoeHostPickerHandoff.metadataLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        let temporary = ".response-\(UUID().uuidString)"
        let fd = temporary.withCString { openat(descriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)) }
        guard fd >= 0 else { throw Self.failure() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close(); temporary.withCString { _ = unlinkat(descriptor, $0, 0) } }
        try file.write(contentsOf: data)
        let renamed = temporary.withCString { temp in "response.json".withCString { renameat(descriptor, temp, descriptor, $0) } }
        guard renamed == 0 else { throw Self.failure() }
    }
    func copyIPA(from source: URL, request: UUID, filename: String) throws {
        guard TahoeHostPickerHandoff.validFilename(filename) else { throw CocoaError(.fileWriteInvalidFileName) }
        let imports = try Self.directory(at: descriptor, name: "imports")
        defer { close(imports) }
        let target = try Self.directory(at: imports, name: request.uuidString)
        defer { close(target) }
        let fd = filename.withCString { openat(target, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)) }
        guard fd >= 0 else { throw Self.failure() }
        let destination = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let origin = try FileHandle(forReadingFrom: source)
        defer { try? origin.close(); try? destination.close() }
        do {
            func transfer() throws -> Bool {
                guard let block = try origin.read(upToCount: 1_048_576), !block.isEmpty else { return false }
                try destination.write(contentsOf: block)
                return true
            }
            while true {
#if canImport(Darwin)
                let more = try autoreleasepool(invoking: transfer)
#else
                let more = try transfer()
#endif
                if !more { break }
            }
        } catch {
            filename.withCString { _ = unlinkat(target, $0, 0) }
            throw error
        }
    }
    var pathUnchanged: Bool { root.resolvingSymlinksInPath().standardizedFileURL == root }
    func removeImport(request: UUID, filename: String) {
        guard TahoeHostPickerHandoff.validFilename(filename),
              let imports = try? Self.directory(at: descriptor, name: "imports", create: false) else { return }
        defer { close(imports) }
        guard let target = try? Self.directory(at: imports, name: request.uuidString, create: false) else { return }
        defer { close(target) }
        filename.withCString { _ = unlinkat(target, $0, 0) }
        request.uuidString.withCString { _ = unlinkat(imports, $0, AT_REMOVEDIR) }
    }
    private static func directory(at parent: Int32, name: String, create: Bool = true) throws -> Int32 {
        if create {
            let created = name.withCString { mkdirat(parent, $0, mode_t(0o700)) }
            guard created == 0 || errno == EEXIST else { throw failure() }
        }
        let fd = name.withCString { openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw failure() }
        return fd
    }
    private static func readMetadata(fd: Int32) throws -> Data {
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, UInt32(info.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG),
              info.st_size <= TahoeHostPickerHandoff.metadataLimit else { throw CocoaError(.fileReadTooLarge) }
        let data = try file.read(upToCount: TahoeHostPickerHandoff.metadataLimit + 1) ?? Data()
        guard data.count <= TahoeHostPickerHandoff.metadataLimit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
    private static func failure() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
