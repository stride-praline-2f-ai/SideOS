import Foundation

struct TahoeDownloadRecord: Codable, Sendable {
    var id: UUID
    var tabID: UUID
    var name: String
    var status: String
    var file: URL?
    var sourceURL: URL?
    var profile: String
    var resumeName: String?
    var stagingName: String?
    var date: Date
}

actor TahoeDownloadStorage {
    static let shared = TahoeDownloadStorage()
    private var revision: UInt64 = 0
    func save(_ records: [TahoeDownloadRecord], data: [UUID: Data], revision: UInt64) throws {
        guard revision >= self.revision else { return }
        let root = TahoeStorage.root.appendingPathComponent("DownloadResume", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (id, value) in data {
            let url = root.appendingPathComponent(id.uuidString + ".resume")
            #if os(iOS)
            try value.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try value.write(to: url, options: .atomic)
            #endif
        }
        try TahoeStorage.write(records, to: "downloads.json")
        self.revision = revision
        let keep = Set(records.compactMap(\.resumeName))
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    func resumeData(_ name: String) throws -> Data {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".resume") else { throw CocoaError(.fileReadInvalidFileName) }
        return try Data(contentsOf: TahoeStorage.root.appendingPathComponent("DownloadResume").appendingPathComponent(name))
    }
}
