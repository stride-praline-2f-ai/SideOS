import Foundation

struct TahoeFileMetadata: Sendable {
    var folder: Bool
    var bytes: Int
    var modified: Date
    var kind: String
}
struct TahoeDirectorySnapshot: Sendable {
    var entries: [URL]
    var metadata: [URL: TahoeFileMetadata]
}

/// File enumeration and recursive operations are serialized outside the UI
/// actor. Cancellation is checked between items, never halfway through a move.
actor TahoeFileWorker {
    static let shared = TahoeFileWorker()
    private struct TrashRecord: Codable { var original: URL; var deleted: Date }
    private struct Move { var source: URL; var destination: URL }
    private struct Undo {
        var moves: [Move]; var title: String
        init(source: URL, destination: URL, title: String) { moves = [Move(source: source, destination: destination)]; self.title = title }
        init(moves: [Move], title: String) { self.moves = moves; self.title = title }
    }
    private var undo: [Undo] = []
    private var trashRoots = Set<URL>()
    var undoTitle: String? { undo.last?.title }
    func prepare(_ directories: [URL]) throws { for url in directories { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } }
    func hasVisibleEntry(_ directory: URL) -> Bool {
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.nextObject() != nil
    }
    func snapshot(_ directory: URL) throws -> TahoeDirectorySnapshot {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var metadata: [URL: TahoeFileMetadata] = [:]
        for url in entries {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: keys)
            metadata[url] = TahoeFileMetadata(folder: values?.isDirectory == true, bytes: values?.fileSize ?? 0,
                modified: values?.contentModificationDate ?? .distantPast, kind: values?.localizedTypeDescription ?? "Document")
        }
        return TahoeDirectorySnapshot(entries: entries, metadata: metadata)
    }
    func search(_ query: String, roots: [URL], limit: Int = 12) throws -> [URL] {
        var found: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if url.lastPathComponent.localizedCaseInsensitiveContains(query) { found.append(url) }
                if found.count >= limit { return found }
            }
        }
        return found
    }
    private func records(_ trash: URL) -> [String: TrashRecord] {
        guard let data = try? Data(contentsOf: trash.appendingPathComponent(".original-locations.json")),
              let records = try? JSONDecoder().decode([String: TrashRecord].self, from: data) else { return [:] }
        return records
    }
    private func save(_ records: [String: TrashRecord], trash: URL) throws {
        try JSONEncoder().encode(records).write(to: trash.appendingPathComponent(".original-locations.json"), options: .atomic)
    }
    func trash(_ source: URL, in trash: URL) throws {
        trashRoots.insert(trash)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = TahoeFileOperations.unique(source.lastPathComponent, in: trash)
        var index = records(trash)
        try FileManager.default.moveItem(at: source, to: destination)
        index[destination.lastPathComponent] = TrashRecord(original: source, deleted: Date())
        do { try save(index, trash: trash) }
        catch { try? FileManager.default.moveItem(at: destination, to: source); throw error }
        remember(Undo(source: destination, destination: source, title: "Move to Trash"))
    }
    func restore(_ source: URL, fallback: URL, allowedRoot: URL) throws {
        trashRoots.insert(source.deletingLastPathComponent())
        var index = records(source.deletingLastPathComponent())
        let original = index[source.lastPathComponent]?.original
        let directory = original?.deletingLastPathComponent()
        let base = allowedRoot.resolvingSymlinksInPath().path + "/"
        let permitted = directory.map { $0.resolvingSymlinksInPath().path.hasPrefix(base) && FileManager.default.fileExists(atPath: $0.path) } ?? false
        let destination = TahoeFileOperations.unique(original?.lastPathComponent ?? source.lastPathComponent, in: permitted ? directory! : fallback)
        try FileManager.default.moveItem(at: source, to: destination)
        index.removeValue(forKey: source.lastPathComponent)
        try save(index, trash: source.deletingLastPathComponent())
        remember(Undo(source: destination, destination: source, title: "Restore from Trash"))
    }
    func empty(_ trash: URL) throws {
        let entries = try snapshot(trash).entries
        var index = records(trash)
        for url in entries {
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: url)
            index.removeValue(forKey: url.lastPathComponent)
            try save(index, trash: trash)
        }
        undo.removeAll { $0.moves.contains { $0.source.deletingLastPathComponent() == trash || $0.destination.deletingLastPathComponent() == trash } }
    }
    func rename(_ source: URL, name: String) throws -> URL {
        guard TahoeFileOperations.validName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if source == destination { return source }
        try FileManager.default.moveItem(at: source, to: destination)
        remember(Undo(source: destination, destination: source, title: "Rename"))
        return destination
    }
    func move(_ source: URL, to directory: URL) throws -> URL {
        let from = source.resolvingSymlinksInPath().standardizedFileURL.path
        let to = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard from != to, !to.hasPrefix(from + "/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let destination = TahoeFileOperations.unique(source.lastPathComponent, in: directory)
        try FileManager.default.moveItem(at: source, to: destination)
        remember(Undo(source: destination, destination: source, title: "Move"))
        return destination
    }
    func copy(_ source: URL, name: String, to directory: URL) throws {
        try Task.checkCancellation(); try TahoeFileOperations.copy(source, name: name, to: directory)
    }
    @discardableResult func undoLast() throws -> [(URL, URL)] {
        guard let item = undo.last else { return [] }
        guard item.moves.allSatisfy({ !FileManager.default.fileExists(atPath: $0.destination.path) }) else {
            throw NSError(domain: "SideOS.Files", code: 1, userInfo: [NSLocalizedDescriptionKey: "The original name is already in use. Rename or move that item before undoing."])
        }
        while let move = undo.last?.moves.first {
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: move.source, to: move.destination)
            undo[undo.count - 1].moves.removeFirst()
            let from = move.source.deletingLastPathComponent(), to = move.destination.deletingLastPathComponent()
            if trashRoots.contains(from) { var index = records(from); index.removeValue(forKey: move.source.lastPathComponent); try save(index, trash: from) }
            if trashRoots.contains(to) { var index = records(to); index[move.destination.lastPathComponent] = TrashRecord(original: move.source, deleted: Date()); try save(index, trash: to) }
        }
        undo.removeLast()
        return item.moves.map { ($0.source, $0.destination) }
    }
    func batchRename(_ urls: [URL], prefix: String) throws -> [(URL, URL)] {
        guard TahoeFileOperations.validName(prefix) else { throw CocoaError(.fileWriteInvalidFileName) }
        let plan = urls.enumerated().map { index, url -> (source: URL, temporary: URL, destination: URL) in
            let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
            return (url, url.deletingLastPathComponent().appendingPathComponent(".rename-" + UUID().uuidString), url.deletingLastPathComponent().appendingPathComponent("\(prefix) \(index + 1)" + ext))
        }.filter { $0.source != $0.destination }
        guard plan.allSatisfy({ !FileManager.default.fileExists(atPath: $0.destination.path) }) else { throw CocoaError(.fileWriteFileExists) }
        var staged = 0, published = 0
        do {
            for item in plan { try Task.checkCancellation(); try FileManager.default.moveItem(at: item.source, to: item.temporary); staged += 1 }
            for item in plan { try FileManager.default.moveItem(at: item.temporary, to: item.destination); published += 1 }
        } catch {
            var remaining: [String] = []
            for (index, item) in plan.prefix(staged).enumerated() {
                let location = index < published ? item.destination : item.temporary
                do { try FileManager.default.moveItem(at: location, to: item.source) } catch { remaining.append(location.path) }
            }
            if !remaining.isEmpty { throw NSError(domain: "SideOS.Files", code: 2, userInfo: [NSLocalizedDescriptionKey: "Rename stopped. These files could not be returned to their original names:\n" + remaining.joined(separator: "\n")]) }
            throw error
        }
        if !plan.isEmpty { remember(Undo(moves: plan.map { Move(source: $0.destination, destination: $0.source) }, title: "Rename \(plan.count) Items")) }
        return plan.map { ($0.source, $0.destination) }
    }
    private func remember(_ item: Undo) { undo.append(item); if undo.count > 30 { undo.removeFirst() } }
}
