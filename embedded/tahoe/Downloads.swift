import SwiftUI
import WebKit
import QuickLook

@MainActor final class TahoeDownload: NSObject, ObservableObject, Identifiable, WKDownloadDelegate {
    let id: UUID
    let tabID: UUID
    let profile: TahoeBrowserProfile
    let date: Date
    @Published var name = "Preparing download…"
    @Published var fraction = 0.0
    @Published var status = "Downloading"
    @Published var file: URL?
    @Published private(set) var received: Int64 = 0
    @Published private(set) var total: Int64 = 0
    @Published private(set) var bytesPerSecond: Double = 0
    @Published private(set) var paused = false
    @Published private(set) var preparing = false
    private var controlToken = UUID()
    private(set) var resumeData: Data?
    private var resumeName: String?
    private var sourceURL: URL?
    private var pendingFile: URL?
    private var transfer: WKDownload?
    private var source: WKWebView?
    private var observation: NSKeyValueObservation?
    private var lastProgress = (time: ProcessInfo.processInfo.systemUptime, bytes: Int64(0))
    var changed: (() -> Void)?
    var active: Bool { transfer != nil || preparing }
    var resumable: Bool { paused || resumeData != nil || resumeName != nil }
    var retryable: Bool { !active && file == nil && sourceURL != nil }
    var record: TahoeDownloadRecord? {
        guard profile != .privateBrowsing else { return nil }
        return TahoeDownloadRecord(id: id, tabID: tabID, name: name,
            status: active ? "Interrupted — retry to restart" : status, file: file, sourceURL: sourceURL,
            profile: profile.rawValue, resumeName: resumeData == nil ? resumeName : id.uuidString + ".resume", stagingName: pendingFile?.lastPathComponent, date: date)
    }
    init(_ download: WKDownload, tabID: UUID, source: WKWebView, profile: TahoeBrowserProfile) {
        id = UUID(); self.tabID = tabID; self.source = source; self.profile = profile; date = Date()
        super.init(); bind(download)
    }
    init(record: TahoeDownloadRecord) {
        id = record.id; tabID = record.tabID; profile = TahoeBrowserProfile(rawValue: record.profile) ?? .personal; date = record.date
        name = record.name; status = record.status; file = record.file; sourceURL = record.sourceURL
        resumeName = record.resumeName; paused = record.resumeName != nil
        if let staging = record.stagingName, staging == ".download-" + record.id.uuidString { pendingFile = TahoeStorage.root.appendingPathComponent(staging) }
        super.init()
        if let file, !FileManager.default.fileExists(atPath: file.path) { self.file = nil; status = "Saved file moved or removed" }
    }
    private func bind(_ download: WKDownload) {
        transfer = download; preparing = false; paused = false; status = "Downloading"; download.delegate = self
        lastProgress = (ProcessInfo.processInfo.systemUptime, 0)
        observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self, self.transfer === download else { return }
                let now = ProcessInfo.processInfo.systemUptime, interval = now - self.lastProgress.time
                if interval > 0.2 {
                    self.bytesPerSecond = max(0, Double(progress.completedUnitCount - self.lastProgress.bytes) / interval)
                    self.lastProgress = (now, progress.completedUnitCount)
                }
                self.received = progress.completedUnitCount; self.total = progress.totalUnitCount
                self.fraction = progress.fractionCompleted
            }
        }
        changed?()
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard transfer === download else { completionHandler(nil); return }
        do {
            try TahoeFileStore.shared.prepare()
            sourceURL = response.url
            let candidate = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            name = candidate.isEmpty || candidate == "." || candidate == ".." ? "Download" : candidate
            let staging = TahoeStorage.root.appendingPathComponent(".download-" + id.uuidString)
            pendingFile = staging; completionHandler(staging); changed?()
        } catch { status = error.localizedDescription; completionHandler(nil); finish() }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard transfer === download else { return }
        do {
            guard let pendingFile else { throw CocoaError(.fileNoSuchFile) }
            let folder = TahoePreferences.shared.value.downloadToDocuments == true ? TahoeFileStore.shared.root : TahoeFileStore.shared.downloads
            let target = TahoeFileStore.shared.unique(name, in: folder)
            try FileManager.default.moveItem(at: pendingFile, to: target)
            self.pendingFile = nil; file = target; name = target.lastPathComponent
            resumeData = nil; resumeName = nil; fraction = 1; status = "Completed"
            TahoeFileStore.shared.revision += 1
        } catch { status = error.localizedDescription; file = nil }
        finish()
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard transfer === download else { return }
        self.resumeData = resumeData; paused = resumeData != nil
        status = resumeData == nil ? error.localizedDescription : "Interrupted — ready to resume"
        file = nil; finish(keepingPartial: resumeData != nil)
    }
    func pause() {
        guard let transfer else { return }
        controlToken = UUID(); let token = controlToken
        self.transfer = nil; preparing = true; observation = nil
        transfer.cancel { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.controlToken == token else { return }
                self.preparing = false
                self.resumeData = data; self.paused = data != nil
                self.status = data == nil ? "Paused — server requires restart" : "Paused"
                self.changed?()
            }
        }
    }
    func resume(restart: Bool = false) {
        guard !active else { return }
        preparing = true; controlToken = UUID(); let token = controlToken
        status = "Preparing download…"
        Task { [weak self] in
            guard let self else { return }
            if source == nil {
                let configuration = WKWebViewConfiguration()
                switch profile {
                case .personal: configuration.websiteDataStore = .default()
                case .work: configuration.websiteDataStore = TahoeBrowserSession.workStore
                case .privateBrowsing: configuration.websiteDataStore = .nonPersistent()
                }
                source = WKWebView(frame: .zero, configuration: configuration)
            }
            guard let source, controlToken == token else { preparing = false; return }
            var data = resumeData
            if !restart, data == nil, let resumeName { data = try? await TahoeDownloadStorage.shared.resumeData(resumeName) }
            guard controlToken == token else { return }
            if !restart, let data {
                source.resumeDownload(fromResumeData: data) { [weak self] download in guard let self, self.controlToken == token else { download.cancel { _ in }; return }; self.bind(download) }
            } else if let sourceURL {
                if let pendingFile { try? FileManager.default.removeItem(at: pendingFile) }; pendingFile = nil
                resumeData = nil; resumeName = nil
                source.startDownload(using: URLRequest(url: sourceURL)) { [weak self] download in guard let self, self.controlToken == token else { download.cancel { _ in }; return }; self.bind(download) }
            } else { preparing = false; status = "Open the source page to restart this download."; changed?() }
        }
    }
    func cancel() {
        controlToken = UUID(); preparing = false
        let transfer = transfer; self.transfer = nil
        transfer?.cancel { _ in }
        resumeData = nil; resumeName = nil; paused = false
        status = "Cancelled"; file = nil; finish()
    }
    private func finish(keepingPartial: Bool = false) {
        if !keepingPartial, let pendingFile { try? FileManager.default.removeItem(at: pendingFile); self.pendingFile = nil }
        observation = nil; transfer = nil
        if !resumable { source = nil }
        changed?()
    }
}

@MainActor final class TahoeDownloads: ObservableObject {
    static let shared = TahoeDownloads()
    @Published var items: [TahoeDownload] = []
    private var revision: UInt64 = 0
    init() {
        if let saved = try? TahoeStorage.read("downloads.json", as: [TahoeDownloadRecord].self) {
            items = saved.filter { $0.profile != TahoeBrowserProfile.privateBrowsing.rawValue }.map(TahoeDownload.init(record:))
            items.forEach { wire($0) }
        }
    }
    private func wire(_ item: TahoeDownload) { item.changed = { [weak self] in self?.objectWillChange.send(); self?.save() } }
    func track(_ download: WKDownload, tabID: UUID, source: WKWebView, profile: TahoeBrowserProfile) {
        let item = TahoeDownload(download, tabID: tabID, source: source, profile: profile)
        wire(item); items.insert(item, at: 0); save()
    }
    func isActive(_ tabID: UUID) -> Bool { items.contains { $0.tabID == tabID && $0.active } }
    func clearFinished() { items.removeAll { !$0.active && !$0.resumable }; save() }
    private func save() {
        revision &+= 1; let revision = revision
        let retained = items.filter { $0.active || $0.resumable } + Array(items.filter { !$0.active && !$0.resumable }.prefix(100))
        let records = retained.compactMap(\.record)
        let data = Dictionary(uniqueKeysWithValues: items.filter { $0.profile != .privateBrowsing }.compactMap { item in item.resumeData.map { (item.id, $0) } })
        Task { do { try await TahoeDownloadStorage.shared.save(records, data: data, revision: revision) } catch { TahoeWorkspace.shared.error = "Download history could not be saved: \(error.localizedDescription)" } }
    }
}

struct TahoeDownloadsView: View {
    @ObservedObject private var downloads = TahoeDownloads.shared
    @State private var preview: URL?
    @Environment(\.tahoeTrafficInset) private var trafficInset
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(TahoeStrings.ui("Downloads")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(TahoeStrings.ui("Show in Finder")) { TahoeWorkspace.shared.openFiles(TahoeFileStore.shared.downloads) }.buttonStyle(TahoeControlStyle())
                Button(TahoeStrings.ui("Clear Finished")) { downloads.clearFinished() }.buttonStyle(TahoeControlStyle())
            }.tahoeGlassGroup().padding(14).padding(.leading, trafficInset).tahoeWindowDragRegion().background(TahoeDesign.window)
            Divider()
            if downloads.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(.tertiary)
                    Text(TahoeStrings.ui("Your downloads appear here")).foregroundStyle(.secondary)
                    Text(TahoeStrings.ui("Saved files remain available in Finder → Downloads.")).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(downloads.items) { item in TahoeDownloadRow(item: item, preview: $preview) }.listStyle(.plain)
            }
        }.background(TahoeDesign.content).quickLookPreview($preview)
    }
}
private struct TahoeDownloadRow: View {
    @ObservedObject var item: TahoeDownload
    @Binding var preview: URL?
    private var progressText: String {
        let received = ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file)
        let total = item.total > 0 ? " of " + ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file) : ""
        let speed = item.bytesPerSecond > 0 ? " · " + ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file) + "/s" : ""
        let remaining = item.total > item.received && item.bytesPerSecond > 0 ? " · " + String(Int(Double(item.total - item.received) / item.bytesPerSecond)) + "s left" : ""
        return received + total + speed + remaining
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill").font(.title2).foregroundStyle(TahoeDesign.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if item.active {
                    TahoeProgress(value: item.fraction, label: "Download progress")
                    Text(progressText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(item.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if item.active {
                Button { item.pause() } label: { Image(systemName: "pause.circle") }.accessibilityLabel("Pause download")
                Button { item.cancel() } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Cancel download")
            } else if let file = item.file {
                Button(TahoeStrings.ui("Open")) { preview = file }.buttonStyle(TahoeControlStyle())
                Button(TahoeStrings.ui("Reveal")) { TahoeWorkspace.shared.openFiles(file.deletingLastPathComponent(), reveal: file) }.buttonStyle(TahoeControlStyle())
                ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
            } else if item.resumable || item.retryable {
                Button(item.resumable ? "Resume" : "Retry") { item.resume() }.buttonStyle(TahoeControlStyle())
                Menu { Button(TahoeStrings.ui("Restart Download")) { item.resume(restart: true) }; Button(TahoeStrings.ui("Cancel"), role: .destructive) { item.cancel() } } label: { Image(systemName: "ellipsis.circle") }
            }
        }.padding(.vertical, 6)
    }
}

