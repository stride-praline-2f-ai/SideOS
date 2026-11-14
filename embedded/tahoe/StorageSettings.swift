import SwiftUI
import UniformTypeIdentifiers

struct TahoeWorkspaceBackup: Codable, Sendable {
    var version = 1
    var created = Date()
    var workspace: TahoeSavedWorkspace
    var bookmarks: [TahoeWebLink]
    var webApps: [TahoeWebLink]
}
struct TahoeBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var backup: TahoeWorkspaceBackup
    init(backup: TahoeWorkspaceBackup) { self.backup = backup }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 4_194_304 else { throw CocoaError(.fileReadCorruptFile) }
        backup = try JSONDecoder().decode(TahoeWorkspaceBackup.self, from: data)
        guard backup.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}
struct TahoeStorageSettings: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var library = TahoeBrowserLibrary.shared
    @ObservedObject private var downloads = TahoeDownloads.shared
    @State private var exporting = false
    @State private var importing = false
    @State private var document: TahoeBackupDocument?
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TahoeStrings.ui("Storage & Recovery")).font(.title2.bold())
            Text(TahoeStrings.ui("Layout backups include eligible browser addresses, window geometry, bookmarks and web-app links. Private pages, credentials, website cookies, chat text, custom image files and update-trust settings are excluded.")).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(TahoeStrings.ui("Export Layout & Bookmarks")) {
                    document = TahoeBackupDocument(backup: TahoeWorkspaceBackup(workspace: workspace.makeSnapshot(), bookmarks: workspace.bookmarks.map(clean), webApps: workspace.pinned.map(clean)))
                    exporting = true
                }
                Button(TahoeStrings.ui("Import Backup…")) { importing = true }
            }.buttonStyle(TahoeControlStyle())
            Button(TahoeStrings.ui("Open Previous Session Snapshot")) {
                do {
                    guard let snapshot = try TahoeStorage.read("workspace.json.previous", as: TahoeSavedWorkspace.self), snapshot.version == 1 else { message = "No previous session snapshot is available."; return }
                    workspace.openArrangement(TahoeArrangement(title: "Previous Session", snapshot: snapshot))
                    message = "Previous windows opened alongside your current work."
                } catch { message = error.localizedDescription }
            }.buttonStyle(TahoeControlStyle())
            Text("Local browser history: \(library.visits.count) entries. Download history: \(downloads.items.count) items.").font(.callout)
            Button(TahoeStrings.ui("Clear Browser History and Closed Tabs…"), role: .destructive) {
                TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Clear Local History?", message: "Personal and Work history and recently closed tabs will be removed. Open tabs, cookies, bookmarks and downloaded files are kept.", primary: "Clear", destructive: true, accept: { _ in library.clear() })
            }.buttonStyle(TahoeControlStyle())
            Button(TahoeStrings.ui("Clear Finished Download History")) { downloads.clearFinished(); message = "Finished history cleared. Downloaded files remain in Finder." }.buttonStyle(TahoeControlStyle())
            Button(TahoeStrings.ui("Open Downloaded Files")) { workspace.openFiles(TahoeFileStore.shared.downloads) }.buttonStyle(TahoeControlStyle())
            if let recovered = UserDefaults.standard.string(forKey: "TahoeRecoveredFile") { Text("The last-known-good backup was used to recover \(recovered).").font(.caption).foregroundStyle(.secondary) }
            if let message { Text(message).font(.callout).textSelection(.enabled) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "SideOS-Workspace") { result in if case .failure(let error) = result { message = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            Task {
                do {
                    let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let backup = try await Task.detached(priority: .userInitiated) {
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4_194_304 else { throw CocoaError(.fileReadTooLarge) }
                        let value = try JSONDecoder().decode(TahoeWorkspaceBackup.self, from: Data(contentsOf: url))
                        guard value.version == 1, value.workspace.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                        guard value.workspace.windows.count <= 200,
                              value.workspace.browsers.reduce(0, { $0 + max($1.addresses.count, $1.tabs?.count ?? 0) }) <= 5000 else { throw CocoaError(.fileReadTooLarge) }
                        return value
                    }.value
                    TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Import Workspace Backup?", message: "This opens \(backup.workspace.windows.count) saved windows alongside your current work and merges bookmarks/web-app links. It does not change permissions, update keys, credentials or cookies.", primary: "Import", accept: { _ in
                        workspace.importLinks(bookmarks: backup.bookmarks.map(clean), webApps: backup.webApps.map(clean))
                        workspace.openArrangement(TahoeArrangement(title: "Imported Backup", snapshot: backup.workspace))
                        message = "Backup imported. Existing windows were kept."
                    })
                } catch { message = error.localizedDescription }
            }
        }
    }
    private func clean(_ link: TahoeWebLink) -> TahoeWebLink {
        var copy = link; copy.iconData = nil; copy.customIcon = false
        copy.iconZoom = nil; copy.iconOffsetX = nil; copy.iconOffsetY = nil; return copy
    }
}
