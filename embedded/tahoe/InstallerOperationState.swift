import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum TahoeInstallerOperation {
    static func isIdle(at file: URL) throws -> Bool {
        let descriptor = open(file.path, O_RDWR)
        if descriptor < 0 {
            if errno == ENOENT { return true }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN); return true
        }
        if errno == EWOULDBLOCK || errno == EAGAIN { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
