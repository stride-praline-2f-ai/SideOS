import Foundation

enum TahoeFileOperations {
    static func unique(_ name: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(name)
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var result = candidate
        var index = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = directory.appendingPathComponent("\(stem) \(index)" + (ext.isEmpty ? "" : ".\(ext)")); index += 1
        }
        return result
    }
    /// Publish a complete copy atomically. An interrupted/failed copy never
    /// replaces an existing item or leaves a partially named visible document.
    static func copy(_ source: URL, name: String, to directory: URL) throws {
        guard validName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        try validateDestination(source, directory: directory)
        let staging = directory.appendingPathComponent(".copy-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        try FileManager.default.moveItem(at: staging, to: unique(name, in: directory))
    }
    static func move(_ source: URL, to directory: URL) throws {
        try validateDestination(source, directory: directory)
        guard source.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL else { return }
        try FileManager.default.moveItem(at: source, to: unique(source.lastPathComponent, in: directory))
    }
    private static func validateDestination(_ source: URL, directory: URL) throws {
        let from = source.resolvingSymlinksInPath().standardizedFileURL.path
        let to = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard from != to, !to.hasPrefix(from + "/") else { throw CocoaError(.fileWriteInvalidFileName) }
    }
    static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }
}
