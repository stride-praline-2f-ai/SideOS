import SwiftUI
import QuickLook

/// macos-ui's selected icon/label and Enter/Space activation, extended with
/// native range/toggle selection, rubber-band selection and persisted placement.
struct TahoeDesktopIcons: View {
    @ObservedObject private var store = TahoeFileStore.shared
    @ObservedObject private var clipboard = TahoeFileClipboard.shared
    @EnvironmentObject private var workspace: TahoeWorkspace
    @ObservedObject private var preferences = TahoePreferences.shared
    @State private var entries: [URL] = []
    @State private var metadata: [URL: TahoeFileMetadata] = [:]
    @State private var selection = TahoeSelection<URL>()
    @State private var positions: [String: CGPoint] = [:]
    @State private var dragOrigins: [URL: CGPoint] = [:]
    @State private var positionsBeforeDrag: [String: CGPoint] = [:]
    @State private var rubber: CGRect?
    @State private var hovered: URL?
    @State private var preview: URL?
    @FocusState private var focused: Bool
    private var urls: [URL] { [store.root, store.downloads] + entries }
    private var desktopDirectory: URL { preferences.value.separateDesktop == true ? store.desktop : store.root }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                TahoePointerSurface(feedback: false, click: { _ in activate(); selection.clear() }, drag: { state, point, translation in
                    if state == .began { activate(); selection.clear() }
                    if state == .began || state == .changed {
                        let start = CGPoint(x: point.x - translation.width, y: point.y - translation.height)
                        let rect = TahoeDesktopLayout.selection(from: start, to: point)
                        rubber = rect
                        selection.selected = Set(urls.enumerated().filter { rect.intersects(frame($0.element, index: $0.offset, size: geometry.size)) }.map(\.element))
                        selection.lead = urls.first(where: { selection.selected.contains($0) })
                    } else { rubber = nil }
                }, context: { point in
                    activate()
                    let parent = geometry.frame(in: .named("tahoe-desktop"))
                    TahoeMenuCoordinator.shared.show(anchor: CGRect(x: parent.minX + point.x, y: parent.minY + point.y, width: 1, height: 1), entries: backgroundCommands)
                })
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    let rect = frame(url, index: index, size: geometry.size)
                    icon(url, index: index, size: geometry.size)
                        .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                }
                if let rubber {
                    Rectangle().fill(Color.white.opacity(0.13)).overlay { Rectangle().strokeBorder(.white.opacity(0.7), lineWidth: 1) }
                        .frame(width: rubber.width, height: rubber.height).offset(x: rubber.minX, y: rubber.minY).allowsHitTesting(false)
                }
            }.modifier(TahoeFileDropTarget(directory: desktopDirectory)).clipped().focusable().focused($focused).focusEffectDisabled().onKeyPress { key in handle(key) }
                .task(id: "\(store.revision)-\(preferences.value.separateDesktop == true)") {
                    do {
                        let snapshot = try await store.snapshot(desktopDirectory)
                        entries = snapshot.entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }; metadata = snapshot.metadata
                        selection.reconcile(urls)
                        let current = Set(urls.map(\.absoluteString)); positions = positions.filter { current.contains($0.key) }
                    } catch { workspace.error = error.localizedDescription }
                }
                .onAppear { positions = (try? TahoeStorage.read("desktop-icons.json", as: [String: CGPoint].self)) ?? [:] }
                .onReceive(NotificationCenter.default.publisher(for: .tahoeDesktopCommand)) { notification in
                    if workspace.state.activeID == nil, let command = notification.object as? String { fileCommand(command) }
                }
                .onChange(of: workspace.state.activeID) { _, id in if id != nil { focused = false } }
                .onReceive(NotificationCenter.default.publisher(for: .tahoeFileMoved)) { notification in
                    guard let from = notification.userInfo?["from"] as? URL, let to = notification.userInfo?["to"] as? URL,
                          let position = positions.removeValue(forKey: from.absoluteString) else { return }
                    positions[to.absoluteString] = position; savePositions()
                }
        }.quickLookPreview($preview)
    }
    private func icon(_ url: URL, index: Int, size: CGSize) -> some View {
        let folder = url == store.root || url == store.downloads || metadata[url]?.folder == true
        let name = url == store.root ? "Documents" : url == store.downloads ? "Downloads" : url.lastPathComponent
        return VStack(spacing: 6) {
            ZStack {
                if folder { TahoeFolderIcon(size: preferences.value.compactDesktop ? 48 : 60) }
                else { Image(systemName: "doc.text.fill").font(.system(size: 44, weight: .light)).foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 2, y: 2) }
            }.frame(width: 68, height: 60)
                .background(selection.selected.contains(url) ? Color.black.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(selection.selected.contains(url) ? Color.white.opacity(0.38) : Color.clear, lineWidth: 0.5) }
            Text(name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.9), radius: 2, y: 1).padding(.horizontal, 4).padding(.vertical, 2)
                .background(selection.selected.contains(url) ? focused ? TahoeDesign.accent : Color.gray.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }.padding(4)
            .overlay {
                GeometryReader { item in
                    TahoePointerSurface(click: { modifiers in
                        activate(); selection.select(url, ordered: urls, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
                    }, doubleClick: { open(url) }, touchOpen: { open(url) }, drag: { state, _, translation in
                        drag(url, state: state, translation: translation, size: size)
                    }, context: { point in
                        activate()
                        if !selection.selected.contains(url) { selection.select(url, ordered: urls) }
                        let anchor = item.frame(in: .named("tahoe-desktop"))
                        TahoeMenuCoordinator.shared.show(anchor: CGRect(x: anchor.minX + point.x, y: anchor.minY + point.y, width: 1, height: 1), entries: commands(url))
                    })
                }
            }.onDrag { TahoeFileTransfer.shared.provider(selection.selected.contains(url) ? urls.filter { selection.selected.contains($0) && $0 != store.root && $0 != store.downloads } : [url]) }
            .modifier(TahoeFileDropTarget(directory: folder ? url : nil))
            .onHover { over in hovered = over ? url : hovered == url ? nil : hovered }
            .accessibilityElement(children: .ignore).accessibilityLabel(name).accessibilityAddTraits(selection.selected.contains(url) ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { open(url) }
            .accessibilityAction(named: "Add to selection") { activate(); selection.select(url, ordered: urls, toggling: true) }
            .accessibilityAction(named: "Show in Finder") { workspace.openFiles(url.deletingLastPathComponent()) }
    }
    private func activate() { workspace.state.activateDesktop(); focused = true; workspace.menu = nil; workspace.overlay = nil; TahoeMenuCoordinator.shared.dismiss() }
    private func frame(_ url: URL, index: Int, size: CGSize) -> CGRect { TahoeDesktopLayout.frame(index: index, canvas: size, saved: positions[url.absoluteString]) }
    private func open(_ url: URL) { if store.isDirectory(url) { workspace.openFiles(url) } else { preview = url } }
    private func drag(_ url: URL, state: UIGestureRecognizer.State, translation: CGSize, size: CGSize) {
        if state == .began {
            activate()
            if !selection.selected.contains(url) { selection.select(url, ordered: urls) }
            positionsBeforeDrag = positions
            dragOrigins = Dictionary(uniqueKeysWithValues: urls.enumerated().filter { selection.selected.contains($0.element) }.map { index, url in
                let rect = frame(url, index: index, size: size); return (url, CGPoint(x: rect.midX, y: rect.midY))
            })
        }
        if state == .began || state == .changed {
            for (url, origin) in dragOrigins {
                let next = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)
                let rect = TahoeDesktopLayout.frame(index: 0, canvas: size, saved: next)
                positions[url.absoluteString] = CGPoint(x: rect.midX, y: rect.midY)
            }
        } else {
            if state == .cancelled || state == .failed { positions = positionsBeforeDrag }
            else { savePositions() }
            dragOrigins.removeAll(); positionsBeforeDrag.removeAll()
        }
    }
    private func savePositions() { do { try TahoeStorage.write(positions, to: "desktop-icons.json") } catch { workspace.error = error.localizedDescription } }
    private var backgroundCommands: [TahoeMenuEntry] {
        [TahoeMenuEntry(title: TahoeStrings.ui("New Folder"), symbol: "folder.badge.plus", action: {
            do { try store.createFolder(in: desktopDirectory) } catch { workspace.error = error.localizedDescription }
        }), TahoeMenuEntry(title: TahoeStrings.ui("Clean Up"), action: { positions.removeAll(); savePositions() }),
         TahoeMenuEntry(title: TahoeStrings.ui("Paste Items"), enabled: !clipboard.urls.isEmpty, action: { fileCommand("paste:") }),
         TahoeMenuEntry(title: TahoeStrings.ui("Select All"), shortcut: "⌘A", action: { selection.selectAll(urls) }), .line(0),
         TahoeMenuEntry(title: TahoeStrings.ui("Change Wallpaper…"), action: { workspace.open(.settings) })]
    }
    private func commands(_ url: URL) -> [TahoeMenuEntry] {
        var values = [TahoeMenuEntry(title: TahoeStrings.ui("Open"), action: { open(url) }), TahoeMenuEntry(title: TahoeStrings.ui("Show in Finder"), action: { workspace.openFiles(url.deletingLastPathComponent()) })]
        if url != store.root && url != store.downloads {
            values += [TahoeMenuEntry(title: TahoeStrings.ui("Cut"), shortcut: "⌘X", action: { fileCommand("cut:") }),
                       TahoeMenuEntry(title: TahoeStrings.ui("Copy"), shortcut: "⌘C", action: { fileCommand("copy:") }),
                       TahoeMenuEntry(title: TahoeStrings.ui("Quick Look"), shortcut: "Space", action: { preview = url }),
                       TahoeMenuEntry(title: TahoeStrings.ui("Rename…"), action: {
                           TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Rename", message: "Choose a name for this desktop item.", symbol: "doc", primary: "Rename", initialText: url.lastPathComponent, validate: TahoeFileOperations.validName, accept: { name in
                               if let name { Task { do { try await store.rename(url, to: name) } catch { workspace.error = error.localizedDescription } } }
                           })
                       }), .line(0), TahoeMenuEntry(title: TahoeStrings.ui("Move Selection to Trash"), shortcut: "⌘⌫", symbol: "trash", destructive: true, action: trashSelection)]
        }
        return values
    }
    private func fileCommand(_ command: String) {
        let targets = urls.filter { selection.selected.contains($0) && $0 != store.root && $0 != store.downloads }
        switch command {
        case "selectAll:": selection.selectAll(urls)
        case "copy:": if !targets.isEmpty { clipboard.set(targets, cut: false) }
        case "cut:": if !targets.isEmpty { clipboard.set(targets, cut: true) }
        case "paste:": Task { do { try await clipboard.paste(to: desktopDirectory); await store.synchronizeUndo() } catch { workspace.error = error.localizedDescription }; store.revision += 1 }
        default: break
        }
    }
    private func trashSelection() {
        let targets = urls.filter { selection.selected.contains($0) && $0 != store.root && $0 != store.downloads }
        Task { do { for url in targets { try await store.moveToTrash(url) } } catch { workspace.error = error.localizedDescription } }
    }
    private func handle(_ key: KeyPress) -> KeyPress.Result {
        guard workspace.state.activeID == nil else { return .ignored }
        if key.modifiers.contains(.command), key.characters.lowercased() == "a" { selection.selectAll(urls); return .handled }
        if key.modifiers.contains(.command), ["c", "x", "v"].contains(key.characters.lowercased()) {
            fileCommand(key.characters.lowercased() == "c" ? "copy:" : key.characters.lowercased() == "x" ? "cut:" : "paste:"); return .handled
        }
        if key.modifiers.contains(.command), key.key == .delete { trashSelection(); return .handled }
        switch key.key {
        case .upArrow, .leftArrow: selection.move(-1, ordered: urls, extending: key.modifiers.contains(.shift))
        case .downArrow, .rightArrow: selection.move(1, ordered: urls, extending: key.modifiers.contains(.shift))
        case .return: if let url = selection.lead { open(url) }
        case .space: if let url = selection.lead, !store.isDirectory(url) { preview = url }
        case .escape: selection.clear()
        default: return .ignored
        }
        return .handled
    }
}

