#if canImport(SwiftUI)
import SwiftUI
#else
import Foundation
#endif

extension Notification.Name {
    static let tahoeFileCommand = Notification.Name("TahoeFileCommand")
    static let tahoeDesktopCommand = Notification.Name("TahoeDesktopCommand")
    static let tahoeFileMoved = Notification.Name("TahoeFileMoved")
}

/// File selection clipboard is separate from the system text clipboard. File
/// copies publish atomically; cut/paste moves never replace an existing file.
@MainActor final class TahoeFileClipboard: ObservableObject {
    static let shared = TahoeFileClipboard()
    @Published private(set) var urls: [URL] = []
    @Published private(set) var cut = false
    @Published private(set) var pasting = false
    private var revision = UUID()
    func set(_ urls: [URL], cut: Bool) { revision = UUID(); self.urls = urls; self.cut = cut }
    func paste(to directory: URL, progress: (Int, Int) -> Void = { _, _ in }) async throws {
        guard !pasting else { throw CocoaError(.fileWriteUnknown) }
        let values = urls, moving = cut, consumedRevision = revision
        var completed = Set<URL>()
        pasting = true
        defer { pasting = false }
        defer {
            if moving && revision == consumedRevision {
                urls = values.filter { !completed.contains($0) }
                if urls.isEmpty { cut = false }
            }
        }
        for (index, url) in values.enumerated() {
            try Task.checkCancellation()
            progress(index, values.count)
            if moving {
                if url.deletingLastPathComponent() == directory { completed.insert(url); continue }
                let destination = try await TahoeFileWorker.shared.move(url, to: directory)
                NotificationCenter.default.post(name: .tahoeFileMoved, object: nil, userInfo: ["from": url, "to": destination])
                completed.insert(url)
            } else { try await TahoeFileWorker.shared.copy(url, name: url.lastPathComponent, to: directory) }
        }
    }
}
