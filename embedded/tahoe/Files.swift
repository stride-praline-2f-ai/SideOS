import SwiftUI
import UniformTypeIdentifiers
import QuickLook

@MainActor final class TahoeFileStore: ObservableObject {
    static let shared = TahoeFileStore()
    @Published var revision = 0
    @Published private(set) var undoTitle: String?
    let root = TahoeStorage.root.appendingPathComponent("Files", isDirectory: true)
    let downloads = TahoeStorage.root.appendingPathComponent("Downloads", isDirectory: true)
    let trash = TahoeStorage.root.appendingPathComponent("Trash", isDirectory: true)
    let desktop = TahoeStorage.root.appendingPathComponent("Desktop", isDirectory: true)
    func prepare() throws {
        for folder in [root, downloads, trash, desktop] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }
    func snapshot(_ directory: URL) async throws -> TahoeDirectorySnapshot {
        try await TahoeFileWorker.shared.prepare([root, downloads, trash, desktop])
        return try await TahoeFileWorker.shared.snapshot(directory)
    }
    func synchronizeUndo() async { undoTitle = await TahoeFileWorker.shared.undoTitle }
    func contents(_ directory: URL) throws -> [URL] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
    }
    func isDirectory(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    func unique(_ name: String, in directory: URL) -> URL {
        TahoeFileOperations.unique(name, in: directory)
    }
    func createFolder(in directory: URL) throws {
        try FileManager.default.createDirectory(at: unique("New Folder", in: directory), withIntermediateDirectories: false)
        revision += 1
    }
    func importFiles(_ urls: [URL], to directory: URL) async throws {
        defer { revision += 1 }
        for url in urls {
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await TahoeFileWorker.shared.copy(url, name: url.lastPathComponent, to: directory)
        }
    }
    func rename(_ url: URL, to name: String) async throws {
        let target = try await TahoeFileWorker.shared.rename(url, name: name)
        NotificationCenter.default.post(name: .tahoeFileMoved, object: nil, userInfo: ["from": url, "to": target])
        undoTitle = await TahoeFileWorker.shared.undoTitle
        revision += 1
    }
    func duplicate(_ url: URL) async throws {
        let ext = url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent + " copy" + (ext.isEmpty ? "" : ".\(ext)")
        try await TahoeFileWorker.shared.copy(url, name: name, to: url.deletingLastPathComponent())
        revision += 1
    }
    func moveToTrash(_ url: URL) async throws {
        try await TahoeFileWorker.shared.trash(url, in: trash)
        undoTitle = await TahoeFileWorker.shared.undoTitle
        revision += 1
    }
    func restore(_ url: URL) async throws {
        try await TahoeFileWorker.shared.restore(url, fallback: root, allowedRoot: TahoeStorage.root)
        undoTitle = await TahoeFileWorker.shared.undoTitle
        revision += 1
    }
    func emptyTrash() async throws {
        try await TahoeFileWorker.shared.empty(trash)
        undoTitle = await TahoeFileWorker.shared.undoTitle
        revision += 1
    }
    func undo() async throws {
        let moves = try await TahoeFileWorker.shared.undoLast()
        for (from, to) in moves { NotificationCenter.default.post(name: .tahoeFileMoved, object: nil, userInfo: ["from": from, "to": to]) }
        undoTitle = await TahoeFileWorker.shared.undoTitle
        revision += 1
    }
}

struct TahoeFilesView: View {
    var windowID: UUID?
    @ObservedObject private var store = TahoeFileStore.shared
    @EnvironmentObject private var workspace: TahoeWorkspace
    @ObservedObject private var clipboard = TahoeFileClipboard.shared
    @ObservedObject private var preferences = TahoePreferences.shared
    @State private var directory = TahoeFileStore.shared.root
    @State private var entries: [URL] = []
    @State private var metadata: [URL: TahoeFileMetadata] = [:]
    @State private var history: [URL] = []
    @State private var forwardHistory: [URL] = []
    @State private var query = ""
    @AppStorage("TahoeFinderView") private var viewMode = "icons"
    @State private var sortColumn = "name"
    @State private var ascending = true
    @State private var importing = false
    @State private var preview: URL?
    @State private var selection = TahoeSelection<URL>()
    @State private var dialog: TahoeDialog?
    @State private var operating = false
    @State private var loading = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshID = UUID()
    @State private var gridColumns = 1
    @FocusState private var focused: Bool
    private var active: Bool { (windowID ?? workspace.state.windows.first(where: { $0.kind == .files })?.id) == workspace.state.activeID }
    private var requestedDirectory: URL? { windowID.flatMap { workspace.finderLocations[$0] } }
    private var requestedReveal: URL? { windowID.flatMap { workspace.finderReveal[$0] } }
    @State private var filtered: [URL] = []
    private func updateFiltered() {
        filtered = entries.filter { query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(query) }.sorted { a, b in
            let left = metadata[a], right = metadata[b]
            let result: ComparisonResult
            switch sortColumn {
            case "modified": result = (left?.modified ?? .distantPast).compare(right?.modified ?? .distantPast)
            case "size": result = (left?.bytes ?? 0) == (right?.bytes ?? 0) ? .orderedSame : (left?.bytes ?? 0) < (right?.bytes ?? 0) ? .orderedAscending : .orderedDescending
            case "kind": result = (left?.kind ?? "").localizedStandardCompare(right?.kind ?? "")
            default:
                if left?.folder != right?.folder { return left?.folder == true }
                result = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
            }
            if result == .orderedSame { return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
    @Environment(\.tahoeTrafficInset) private var trafficInset
    var body: some View {
        TahoeSidebar {
            VStack(alignment: .leading, spacing: 4) {
                Text(TahoeStrings.ui("Favourites")).padding(.top, trafficInset > 0 ? 34 : 0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.vertical, 8)
                sidebar("Documents", symbol: "folder", url: store.root)
                sidebar("Desktop", symbol: "desktopcomputer", url: store.desktop)
                sidebar("Downloads", symbol: "arrow.down.circle", url: store.downloads)
                sidebar("Trash", symbol: "trash", url: store.trash)
                ForEach(preferences.value.fileFavorites ?? [], id: \.self) { value in
                    if let url = URL(string: value) { sidebar(url.lastPathComponent, symbol: "star", url: url) }
                }
                Text(TahoeStrings.ui("Locations")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 20).padding(.bottom, 8)
                Button { importing = true } label: { Label(TahoeStrings.ui("Import from Files…"), systemImage: "ipad") }.padding(8)
                Spacer()
                TahoeBadge(title: "\(entries.count) items") .padding(8)
            }.font(.system(size: 13)).padding(10)
        } content: {
            VStack(spacing: 0) {
                toolbar.tahoeGlassGroup().tahoeWindowDragRegion()
                Divider().opacity(0.4)
                if loading && entries.isEmpty { ProgressView("Loading folder…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if filtered.isEmpty { empty }
                else if viewMode == "icons" { icons }
                else { table }
                Divider().opacity(0.4)
                pathBar
            }.background(TahoeDesign.content)
                .focusable().focused($focused).focusEffectDisabled()
                .onKeyPress { key in handle(key) }
        }
        .buttonStyle(TahoePressStyle())
        .modifier(TahoeFileDropTarget(directory: directory == store.trash ? nil : directory))
        .onAppear { followRequest(); refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .tahoeFileCommand)) { notification in
            guard active, let command = notification.object as? String else { return }
            fileCommand(command)
        }
        .onChange(of: store.revision) { _, _ in refresh() }
        .onChange(of: workspace.finderLocation) { _, _ in followRequest() }
        .onChange(of: requestedDirectory) { _, _ in followRequest() }
        .onChange(of: requestedReveal) { _, value in if value != nil { refresh() } }
        .onChange(of: active) { _, active in if !active { focused = false } }
        .onChange(of: query) { _, _ in updateFiltered(); selection.reconcile(filtered) }
        .onChange(of: sortColumn) { _, _ in updateFiltered() }
        .onChange(of: ascending) { _, _ in updateFiltered() }
        .onDisappear { refreshTask?.cancel() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): let destination = directory; performAsync { try await store.importFiles(urls, to: destination) }
            case .failure(let error): showError(error)
            }
        }
        .quickLookPreview($preview).tahoeDialog($dialog)
    }
    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: directory == store.trash ? "trash" : "folder").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? "This folder is empty" : "No matching files").foregroundStyle(.secondary)
            if query.isEmpty && directory != store.trash { Button(TahoeStrings.ui("Import Files…")) { importing = true }.buttonStyle(TahoeControlStyle()) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var icons: some View {
        GeometryReader { geometry in
          ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14)], spacing: 24) {
                    ForEach(filtered, id: \.self) { url in iconCell(url) }
                }.padding(24)
            }.onChange(of: selection.lead) { _, url in if let url { proxy.scrollTo(url) } }
              .onChange(of: geometry.size.width, initial: true) { _, width in gridColumns = max(1, Int((width - 48 + 14) / 124)) }
          }
        }
    }
    private func iconSelectionColor(_ url: URL) -> Color {
        guard selection.selected.contains(url) else { return .clear }
        return active ? TahoeDesign.accent.opacity(0.18) : Color.primary.opacity(0.08)
    }
    private func iconCell(_ url: URL) -> some View {
        VStack(spacing: 8) {
            fileIcon(url, size: 48)
            Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center)
        }.padding(8).frame(maxWidth: .infinity, minHeight: 94)
            .background(iconSelectionColor(url), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                GeometryReader { geometry in
                    TahoePointerSurface(click: { select(url, modifiers: $0) }, doubleClick: { open(url) }, touchOpen: { open(url) }, context: { point in
                        if !selection.selected.contains(url) { select(url, modifiers: []) }
                        let frame = geometry.frame(in: .named("tahoe-desktop"))
                        TahoeMenuCoordinator.shared.show(anchor: CGRect(x: frame.minX + point.x, y: frame.minY + point.y, width: 1, height: 1), entries: fileCommands(url))
                    })
                }
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(selection.selected.contains(url) ? [.isButton, .isSelected] : [.isButton])
            .onDrag { TahoeFileTransfer.shared.provider(selection.selected.contains(url) ? filtered.filter { selection.selected.contains($0) } : [url]) }
            .modifier(TahoeFileDropTarget(directory: metadata[url]?.folder == true && directory != store.trash ? url : nil))
            .accessibilityAction { select(url, modifiers: []) }.accessibilityAction(named: "Open") { open(url) }
            .accessibilityAction(named: "Add to selection") { select(url, modifiers: .command) }
            .accessibilityIdentifier("finder-item-\(url.lastPathComponent)")
            .id(url)
    }
    private var table: some View {
        TahoeTable(rows: filtered, id: \.self,
                   columns: [TahoeTableColumn(id: "name", title: "Name", width: 240, minimum: 150), TahoeTableColumn(id: "modified", title: "Date Modified", width: 170), TahoeTableColumn(id: "size", title: "Size", width: 95), TahoeTableColumn(id: "kind", title: "Kind", width: 130)],
                   selected: selection.selected, context: { fileCommands($0) }, sortColumn: sortColumn, ascending: ascending,
                   select: { select($0, modifiers: $1) }, open: open, sort: sort) { url, column in
            fileCell(url, column: column)
        }
    }
    @ViewBuilder private func fileCell(_ url: URL, column: String) -> some View {
        switch column {
        case "modified": Text(metadata[url]?.modified.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()) ?? "—")
        case "size": Text(metadata[url]?.folder == true ? "—" : ByteCountFormatter.string(fromByteCount: Int64(metadata[url]?.bytes ?? 0), countStyle: .file))
        case "kind": Text(metadata[url]?.kind ?? "Document")
        default: HStack(spacing: 7) { fileIcon(url, size: 17); Text(url.lastPathComponent) }
        }
    }
    private var toolbar: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                TahoeToolbarButton(symbol: "chevron.left", label: "Back") { goBack() }.disabled(history.isEmpty)
                TahoeToolbarButton(symbol: "chevron.right", label: "Forward") { goForward() }.disabled(forwardHistory.isEmpty)
                Text(directory == store.root ? "Documents" : directory.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1).frame(maxWidth: 150, alignment: .leading)
                if operating { TahoeSpinner() }
                Spacer(minLength: 0)
                TahoeToolbarActions(commands: toolbarCommands).frame(minWidth: 28, maxWidth: 180)
            }
            HStack(spacing: 12) {
                TahoeSegments(options: [TahoeChoice(id: "icons", title: "", symbol: "square.grid.2x2"), TahoeChoice(id: "list", title: "", symbol: "list.bullet")], selection: $viewMode, label: "Finder view").frame(width: 84)
                Spacer(minLength: 4)
                TahoeSearchField(text: $query, active: active).frame(maxWidth: 210)
            }
        }.padding(.horizontal, 12).padding(.vertical, 8).background(TahoeDesign.window)
    }
    private var toolbarCommands: [TahoeMenuEntry] {
        var commands = [TahoeMenuEntry(title: TahoeStrings.ui("Sort"), symbol: "arrow.up.arrow.down", children: [
            TahoeMenuEntry(title: TahoeStrings.ui("Name"), checked: sortColumn == "name", action: { sort("name") }),
            TahoeMenuEntry(title: TahoeStrings.ui("Date Modified"), checked: sortColumn == "modified", action: { sort("modified") }),
            TahoeMenuEntry(title: TahoeStrings.ui("Size"), checked: sortColumn == "size", action: { sort("size") }),
            TahoeMenuEntry(title: TahoeStrings.ui("Kind"), checked: sortColumn == "kind", action: { sort("kind") })])]
        if let title = store.undoTitle { commands.append(TahoeMenuEntry(title: "Undo \(title)", symbol: "arrow.uturn.backward", action: { performAsync { try await store.undo() } })) }
        if directory == store.trash {
            commands.append(TahoeMenuEntry(title: TahoeStrings.ui("Empty Trash…"), symbol: "trash", enabled: !entries.isEmpty, action: confirmEmptyTrash))
        } else {
            commands += [TahoeMenuEntry(title: TahoeStrings.ui("New Folder"), symbol: "folder.badge.plus", enabled: !operating, action: { perform { try store.createFolder(in: directory) } }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Import Files…"), symbol: "square.and.arrow.down", enabled: !operating, action: { importing = true })]
        }
        commands.append(TahoeMenuEntry(title: TahoeStrings.ui("Paste Items"), symbol: "doc.on.clipboard", enabled: !clipboard.urls.isEmpty && directory != store.trash && !operating, action: { fileCommand("paste:") }))
        commands.append(TahoeMenuEntry(title: TahoeStrings.ui("Selection Actions"), symbol: "ellipsis.circle", enabled: !selection.selected.isEmpty, children: selection.lead.map { fileCommands($0) } ?? []))
        let recent = (preferences.value.recentFileLocations ?? []).compactMap(URL.init(string:)).filter { $0.isFileURL && $0 != directory }
        if !recent.isEmpty { commands.append(TahoeMenuEntry(title: "Recent Folders", symbol: "clock", children: recent.map { url in TahoeMenuEntry(title: url.lastPathComponent, symbol: "folder", action: { navigate(url) }) })) }
        commands.append(TahoeMenuEntry(title: (preferences.value.fileFavorites ?? []).contains(directory.absoluteString) ? "Remove Folder from Favorites" : "Add Folder to Favorites", symbol: "star", action: {
            var favorites = preferences.value.fileFavorites ?? []
            if favorites.contains(directory.absoluteString) { favorites.removeAll { $0 == directory.absoluteString } } else { favorites.append(directory.absoluteString) }
            preferences.value.fileFavorites = favorites
        }))
        return commands
    }
    private var pathBar: some View {
        HStack(spacing: 5) {
            TahoeCheckbox(title: "", state: Binding(get: { selection.selected.isEmpty ? .off : selection.selected.count == filtered.count ? .on : .mixed }, set: { if $0 == .on { selection.selectAll(filtered) } else { selection.clear() } }), size: .small).accessibilityLabel("Select all files")
            TahoePopupButton(entries: [TahoeMenuEntry(title: TahoeStrings.ui("Documents"), action: { navigate(store.root) }), TahoeMenuEntry(title: TahoeStrings.ui("Downloads"), action: { navigate(store.downloads) }), TahoeMenuEntry(title: TahoeStrings.ui("Trash"), action: { navigate(store.trash) })]) { Image(systemName: "internaldrive") }
                .accessibilityLabel("Finder locations")
            Text(TahoeStrings.ui("Desktop")); Image(systemName: "chevron.right").font(.system(size: 8))
            Text(directory.lastPathComponent).lineLimit(1)
            Spacer()
            Text(selection.selected.isEmpty ? "\(filtered.count) items" : "\(selection.selected.count) of \(filtered.count) selected")
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(8).background(TahoeDesign.window)
    }
    private func sidebar(_ title: String, symbol: String, url: URL) -> some View {
        Button { navigate(url) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 28)
                .tahoeSidebarSelection(directory == url)
        }
    }
    private func fileIcon(_ url: URL, size: CGFloat) -> some View {
        Image(systemName: metadata[url]?.folder == true ? "folder.fill" : UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? "photo" : "doc.text.fill")
            .font(.system(size: size, weight: .light)).foregroundStyle(metadata[url]?.folder == true ? Color.cyan : selection.selected.contains(url) && active ? .white : .secondary)
    }
    private func fileCommands(_ url: URL) -> [TahoeMenuEntry] {
        let targets = selection.selected.contains(url) ? filtered.filter { selection.selected.contains($0) } : [url]
        var commands = [TahoeMenuEntry(title: TahoeStrings.ui("Open"), shortcut: "⌘O", action: { for target in targets { open(target) } }),
                        TahoeMenuEntry(title: TahoeStrings.ui("Get Info"), shortcut: "⌘I", symbol: "info.circle", action: { showInfo(url) }),
                        TahoeMenuEntry(title: TahoeStrings.ui("Quick Look"), shortcut: "Space", action: { preview = url }),
                        TahoeMenuEntry(title: TahoeStrings.ui("Share…"), symbol: "square.and.arrow.up", action: { TahoeShare.present(targets, window: workspace.hostWindow, sourceRect: TahoeMenuCoordinator.shared.lastAnchor) })]
        if directory == store.trash {
            commands += [.line(0), TahoeMenuEntry(title: TahoeStrings.ui("Restore Original Location"), action: { performAsync { for target in targets { try await store.restore(target) } } })]
        } else {
            commands += [.line(0), TahoeMenuEntry(title: TahoeStrings.ui("Cut"), shortcut: "⌘X", action: { clipboard.set(targets, cut: true) }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Copy"), shortcut: "⌘C", action: { clipboard.set(targets, cut: false) }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Rename…"), enabled: targets.count == 1, action: { rename(url) }),
                         TahoeMenuEntry(title: "Rename \(targets.count) Items…", enabled: targets.count > 1, action: { batchRename(targets) }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Duplicate"), shortcut: "⌘D", enabled: !operating, action: { performAsync { for target in targets { try await store.duplicate(target) } } }), .line(1),
                         TahoeMenuEntry(title: TahoeStrings.ui("Move to Trash"), shortcut: "⌘⌫", symbol: "trash", destructive: true, action: { performAsync { for target in targets { try await store.moveToTrash(target) } } })]
        }
        return commands
    }
    private func select(_ url: URL, modifiers: UIKeyModifierFlags) {
        selection.select(url, ordered: filtered, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command)); focused = true
    }
    private func sort(_ column: String) { if sortColumn == column { ascending.toggle() } else { sortColumn = column; ascending = column != "modified" } }
    private func followRequest() {
        if let id = windowID {
            guard let url = workspace.finderLocations[id] ?? workspace.state.windows.first(where: { $0.id == id })?.resourceID.flatMap(URL.init(string:)) else { return }
            if url != directory { navigate(url) }
            else if requestedReveal != nil { refresh() }
        } else if active, let url = workspace.finderLocation, url != directory { navigate(url) }
    }
    private func navigate(_ url: URL) {
        if directory != url { history.append(directory); forwardHistory.removeAll(); directory = url }
        if let id = windowID { workspace.finderLocations[id] = url; workspace.state.setResource(url.absoluteString, for: id) }
        var recent = preferences.value.recentFileLocations ?? []; recent.removeAll { $0 == url.absoluteString }; recent.insert(url.absoluteString, at: 0); preferences.value.recentFileLocations = Array(recent.prefix(12))
        selection.clear(); query = ""; refresh()
    }
    private func goBack() { if let url = history.popLast() { forwardHistory.append(directory); directory = url; selection.clear(); query = ""; refresh() } }
    private func goForward() { if let url = forwardHistory.popLast() { history.append(directory); directory = url; selection.clear(); query = ""; refresh() } }
    private func open(_ url: URL) { if store.isDirectory(url) { navigate(url) } else { preview = url } }
    private func refresh() {
        refreshTask?.cancel(); let token = UUID(); refreshID = token
        let requested = directory; loading = true
        refreshTask = Task {
            do {
                let snapshot = try await store.snapshot(requested)
                guard !Task.isCancelled, refreshID == token, directory == requested else { return }
                entries = snapshot.entries; metadata = snapshot.metadata; updateFiltered(); selection.reconcile(entries)
                if let id = windowID, let reveal = workspace.finderReveal[id], entries.contains(reveal) { selection.select(reveal, ordered: filtered); workspace.finderReveal.removeValue(forKey: id) }
            } catch is CancellationError { }
            catch { if refreshID == token { showError(error) } }
            if refreshID == token { loading = false }
        }
    }
    private func rename(_ url: URL) {
        dialog = TahoeDialog(title: "Rename", message: "Choose a new name for this item.", symbol: "doc.text", primary: "Rename", initialText: url.lastPathComponent,
                             validate: TahoeFileOperations.validName, accept: { name in if let name { performAsync { try await store.rename(url, to: name) } } })
    }
    private func showInfo(_ url: URL) {
        let item = metadata[url]
        dialog = TahoeDialog(title: url.lastPathComponent, message: "Kind: \(item?.kind ?? "Document")\nSize: \(item?.folder == true ? "Folder" : ByteCountFormatter.string(fromByteCount: Int64(item?.bytes ?? 0), countStyle: .file))\nModified: \(item?.modified.formatted() ?? "Unknown")\nLocation: \(url.path)", symbol: "info.circle", cancel: nil, accept: { _ in })
    }
    private func batchRename(_ urls: [URL]) {
        dialog = TahoeDialog(title: "Rename \(urls.count) Items", message: "Choose a prefix. Names will become Prefix 1, Prefix 2, and so on; extensions are retained. Existing files are never replaced.", primary: "Preview", initialText: "File", validate: TahoeFileOperations.validName, accept: { prefix in
            guard let prefix else { return }
            let preview = urls.enumerated().map { index, url in "\(url.lastPathComponent) → \(prefix) \(index + 1)\(url.pathExtension.isEmpty ? "" : "." + url.pathExtension)" }.joined(separator: "\n")
            dialog = TahoeDialog(title: "Apply Rename?", message: preview, primary: "Rename", accept: { _ in
                performAsync {
                    let moved = try await TahoeFileWorker.shared.batchRename(urls, prefix: prefix)
                    for (from, to) in moved { NotificationCenter.default.post(name: .tahoeFileMoved, object: nil, userInfo: ["from": from, "to": to]) }
                    store.revision += 1
                }
            })
        })
    }
    private func confirmEmptyTrash() {
        dialog = TahoeDialog(title: "Empty Trash?", message: "All items in Trash will be permanently deleted. This cannot be undone.", symbol: "trash", primary: "Empty Trash", destructive: true, accept: { _ in performAsync { try await store.emptyTrash() } })
    }
    private func showError(_ error: Error) { dialog = TahoeDialog(title: "File operation failed", message: error.localizedDescription, symbol: "exclamationmark.triangle", cancel: nil, accept: { _ in }) }
    private func perform(_ work: () throws -> Void) { do { try work() } catch { showError(error) } }
    private func performAsync(_ work: @escaping () async throws -> Void) {
        guard !operating else { return }; operating = true
        let job = TahoeActivityCenter.shared.begin("File Operation", owner: "Finder")
        let task = Task {
            defer { operating = false }
            do { try await work(); await store.synchronizeUndo(); TahoeActivityCenter.shared.finish(job) }
            catch is CancellationError { TahoeActivityCenter.shared.finish(job, cancelled: true) }
            catch { TahoeActivityCenter.shared.finish(job, error: error); showError(error) }
        }
        TahoeActivityCenter.shared.setCancellation(job) { task.cancel() }
    }
    private func fileCommand(_ command: String) {
        guard dialog == nil else { return }
        let targets = filtered.filter { selection.selected.contains($0) }
        switch command {
        case "selectAll:": selection.selectAll(filtered)
        case "copy:": if !targets.isEmpty { clipboard.set(targets, cut: false) }
        case "cut:": if !targets.isEmpty && directory != store.trash { clipboard.set(targets, cut: true) }
        case "paste:":
            guard directory != store.trash, !clipboard.urls.isEmpty else { return }
            let destination = directory
            performAsync { defer { store.revision += 1 }; try await clipboard.paste(to: destination) }
        case "undo:": if store.undoTitle != nil { performAsync { try await store.undo() } }
        default: break
        }
    }
    private func handle(_ key: KeyPress) -> KeyPress.Result {
        guard active, dialog == nil else { return .ignored }
        if key.modifiers.contains(.command) {
            switch key.characters.lowercased() {
            case "a": selection.selectAll(filtered)
            case "o": for url in filtered where selection.selected.contains(url) { open(url) }
            case "c": fileCommand("copy:")
            case "x": fileCommand("cut:")
            case "v": fileCommand("paste:")
            case "z": fileCommand("undo:")
            case "i": if let url = selection.lead { showInfo(url) }
            case "d": let urls = filtered.filter { selection.selected.contains($0) }; performAsync { for url in urls { try await store.duplicate(url) } }
            default:
                guard key.key == .delete, directory != store.trash else { return .ignored }
                let targets = filtered.filter { selection.selected.contains($0) }
                performAsync { for url in targets { try await store.moveToTrash(url) } }
            }
            return .handled
        }
        switch key.key {
        case .upArrow: selection.move(viewMode == "icons" ? -gridColumns : -1, ordered: filtered, extending: key.modifiers.contains(.shift))
        case .downArrow: selection.move(viewMode == "icons" ? gridColumns : 1, ordered: filtered, extending: key.modifiers.contains(.shift))
        case .leftArrow: selection.move(-1, ordered: filtered, extending: key.modifiers.contains(.shift))
        case .rightArrow: selection.move(1, ordered: filtered, extending: key.modifiers.contains(.shift))
        case .space: preview = selection.lead
        case .return: if let url = selection.lead { rename(url) }
        case .escape: selection.clear()
        default: return .ignored
        }
        return .handled
    }
}

