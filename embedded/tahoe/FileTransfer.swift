import SwiftUI
import UniformTypeIdentifiers

@MainActor final class TahoeFileTransfer {
    static let shared = TahoeFileTransfer()
    static let type = "com.aault.sideos.file-transfer"
    private var token = UUID()
    private var values: [URL] = []
    private var started = Date.distantPast
    func provider(_ urls: [URL]) -> NSItemProvider {
        token = UUID(); values = urls; started = Date()
        let token = token.uuidString
        let provider = urls.first.flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.type, visibility: .ownProcess) { completion in completion(Data(token.utf8), nil); return nil }
        return provider
    }
    func receive(_ providers: [NSItemProvider], to directory: URL) {
        let job = TahoeActivityCenter.shared.begin("Transfer Files", owner: "Finder")
        let task = Task {
            do {
                let urls: [URL], moving: Bool
                if let own = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.type) }) {
                    let data: Data? = await withCheckedContinuation { continuation in own.loadDataRepresentation(forTypeIdentifier: Self.type) { data, _ in continuation.resume(returning: data) } }
                    guard let data, data.count <= 64, String(data: data, encoding: .utf8) == token.uuidString, Date().timeIntervalSince(started) < 120 else { throw CocoaError(.userCancelled) }
                    urls = values; moving = true; values = []
                } else {
                    var imported: [URL] = []
                    for provider in providers {
                        let url: URL? = await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                if let url = item as? URL { continuation.resume(returning: url) }
                                else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                                else { continuation.resume(returning: nil) }
                            }
                        }
                        if let url { imported.append(url) }
                    }
                    urls = imported; moving = false
                }
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    TahoeActivityCenter.shared.update(job, detail: url.lastPathComponent, progress: Double(index) / Double(max(1, urls.count)))
                    if moving {
                        if url.deletingLastPathComponent() == directory { continue }
                        let destination = try await TahoeFileWorker.shared.move(url, to: directory)
                        NotificationCenter.default.post(name: .tahoeFileMoved, object: nil, userInfo: ["from": url, "to": destination])
                    } else { try await TahoeFileStore.shared.importFiles([url], to: directory) }
                }
                await TahoeFileStore.shared.synchronizeUndo(); TahoeFileStore.shared.revision += 1; TahoeActivityCenter.shared.finish(job)
            } catch is CancellationError { TahoeActivityCenter.shared.finish(job, cancelled: true) }
            catch { TahoeActivityCenter.shared.finish(job, error: error); TahoeWorkspace.shared.error = error.localizedDescription; TahoeFileStore.shared.revision += 1 }
        }
        TahoeActivityCenter.shared.setCancellation(job) { task.cancel() }
    }
}
struct TahoeFileDropTarget: ViewModifier {
    var directory: URL?
    @State private var targeted = false
    @ViewBuilder func body(content: Content) -> some View {
        if let directory {
            content.onDrop(of: [TahoeFileTransfer.type, UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                guard !providers.isEmpty else { return false }; TahoeFileTransfer.shared.receive(providers, to: directory); return true
            }.overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? TahoeDesign.accent : .clear, lineWidth: 2).allowsHitTesting(false) }
        } else { content }
    }
}
