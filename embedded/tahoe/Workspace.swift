import SwiftUI
import WebKit
import ImageIO

extension Notification.Name { static let tahoeFocusAddress = Notification.Name("TahoeFocusAddress") }
enum TahoeOverlay { case spotlight, overview, launchpad, controlCenter, calendar, about, library, siteInfo }
enum TahoeMenuKind: String, CaseIterable { case apple, app, file, edit, view, go, history, bookmarks, window, help }

@MainActor
final class TahoeWorkspace: ObservableObject {
    static let shared = TahoeWorkspace()
    weak var hostWindow: UIWindow?
    @Published var state = TahoeWindowState() {
        didSet {
            if oldValue.activeID != state.activeID { resumeFocusedBrowser() }
            scheduleSave()
        }
    }
    // Compatibility for existing menu/deep-link entry points. Management is
    // now an ordinary singleton window; it never replaces the desktop.
    var showManagement: Bool {
        get { false }
        set { if newValue { open(.livecontainer); overlay = nil } }
    }
    @Published var search = ""
    @Published var toolsSection = "Actions"
    private var toolsTarget: UUID?
    var librarySection = "tabs"
    @Published var overlay: TahoeOverlay? { didSet { if overlay != .overview { overviewTask?.cancel() } } }
    @Published var tabTransfer: TahoeBrowserTabTransfer?
    var menu: TahoeMenuKind? {
        get { TahoeMenuCoordinator.shared.bar }
        set { TahoeMenuCoordinator.shared.selectBar(newValue) }
    }
    @Published var snapPreview: TahoeWindowLayout?
    @Published var thumbnails: [UUID: UIImage] = [:]
    @Published var finderLocation: URL?
    @Published var finderLocations: [UUID: URL] = [:]
    @Published var finderReveal: [UUID: URL] = [:]
    @Published var pinned: [TahoeWebLink] = []
    @Published var editingWebIcon: TahoeWebLink?
    @Published var bookmarks: [TahoeWebLink] = []
    @Published private(set) var settingsSection = "Appearance"
    @Published private(set) var settingsBackStack: [String] = []
    @Published private(set) var settingsForwardStack: [String] = []
    var menuFrames: [TahoeMenuKind: CGRect] = [:]
    var menuKinds: [TahoeMenuKind] {
        let browser = state.windows.first(where: { $0.id == state.activeID })?.kind == .browser
        return [.apple, .app, .file, .edit, .view] + (browser ? [.history, .bookmarks] : [.go]) + [.window, .help]
    }
    var dockFrames: [String: CGRect] = [:]
    private(set) var minimizeTargets: [UUID: CGPoint] = [:]
    var showSpotlight: Bool {
        get { overlay == .spotlight }
        set { if newValue { present(.spotlight) } else if overlay == .spotlight { overlay = nil } }
    }
    var showOverview: Bool {
        get { overlay == .overview }
        set { if newValue { present(.overview) } else if overlay == .overview { overlay = nil } }
    }
    @Published var error: String?
    @Published private(set) var launching = false
    private(set) var browsers: [UUID: TahoeBrowserSession] = [:]
    private(set) var guests: [UUID: TahoeGuestSession] = [:]
    private(set) var runningApps = TahoeRunningApps()
    private var iconRequests: Set<UUID> = []
    private var hasOpenedInitialWindow = false
    private var saveWork: DispatchWorkItem?
    private var saveRevision: UInt64 = 0
    private var linksRevision: UInt64 = 0
    private var iconRevision: UInt64 = 0
    private var iconEditRevisions: [UUID: UInt64] = [:]
    private var overviewTask: Task<Void, Never>?
    private var overviewRevision = UUID()
    private var thumbnailOrder: [UUID] = []
    private struct LaunchRequest { let id: UUID; let app: LCAppModel; let completion: CheckedContinuation<Void, Never> }
    private var launchQueue: [LaunchRequest] = []
    var activeBrowserPage: TahoeBrowserTab? {
        guard let id = state.activeID, let session = browsers[id] else { return nil }
        return session.tabs.first(where: { $0.id == session.selectedID })?.activePage
    }
    func openTools(_ section: String) {
        if state.windows.first(where: { $0.id == state.activeID })?.kind != .utilities { toolsTarget = state.activeID }
        toolsSection = section; open(.utilities); overlay = nil
    }
    var commands: [TahoeCommand] {
        let targetID = state.windows.first(where: { $0.id == state.activeID })?.kind == .utilities ? toolsTarget : state.activeID
        let target = state.windows.first(where: { $0.id == targetID })
        let session = targetID.flatMap { browsers[$0] }
        let page = session.flatMap { session in session.tabs.first { $0.id == session.selectedID } }?.activePage
        var list = [
            TahoeCommand(title: "New Browser Window", shortcut: "⌘N", action: { self.openBrowser() }),
            TahoeCommand(title: "New Finder Window", action: { self.openFiles(TahoeFileStore.shared.root, newWindow: true) }),
            TahoeCommand(title: "Find on Page", shortcut: "⌘F", enabled: page != nil, action: { if let targetID { self.state.focus(targetID) }; page?.findOnPage() }),
            TahoeCommand(title: "Search Open Tabs", action: { self.showLibrary() }),
            TahoeCommand(title: "Browser History", action: { self.showLibrary("history") }),
            TahoeCommand(title: "Manage Bookmarks", action: { self.showLibrary("bookmarks") }),
            TahoeCommand(title: "Downloads", action: { self.open(.downloads) }),
            TahoeCommand(title: "SideInstaller", action: { self.open(.installer) }),
            TahoeCommand(title: "Saved Arrangements", action: { self.openTools("Layouts") }),
            TahoeCommand(title: "Activity Center", action: { self.openTools("Activity") }),
            TahoeCommand(title: "Browser Settings", action: { self.selectSettings("Browser"); self.open(.settings) }),
            TahoeCommand(title: "Getting Started and Shortcuts", action: { self.openTools("Help") }),
            TahoeCommand(title: "Offline Scratchpad", action: { self.openTools("Scratchpad") }),
            TahoeCommand(title: "Offline Calculator", action: { self.openTools("Calculator") }),
            TahoeCommand(title: "Diagnostics", action: { TahoeReleaseInfo.showDiagnostics() }),
            TahoeCommand(title: "Show Desktop", action: { self.state.showDesktop() })
        ]
        list += TahoeWindowLayout.allCases.map { layout in
            TahoeCommand(title: "Arrange: \(layout.title)", enabled: target != nil && self.state.canApply(layout), action: { if let targetID { self.state.setLayout(layout, for: targetID) } })
        }
        return list
    }
    func spaceName(_ index: Int) -> String { TahoePreferences.shared.value.spaceNames?[String(index)] ?? "Desktop \(index + 1)" }
    func renameSpace(_ index: Int) {
        TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Rename Space", message: "Choose a name for this desktop.", primary: "Save", initialText: spaceName(index), accept: { value in
            guard let value else { return }; var names = TahoePreferences.shared.value.spaceNames ?? [:]
            names[String(index)] = String(value.prefix(60)); TahoePreferences.shared.value.spaceNames = names
        })
    }
    func removeSpace(_ index: Int) {
        guard state.spaceCount > 1, (0..<state.spaceCount).contains(index) else { return }
        let old = TahoePreferences.shared.value
        var names: [String: String] = [:], wallpapers: [String: String] = [:]
        for space in 0..<state.spaceCount where space != index {
            let destination = String(space > index ? space - 1 : space)
            names[destination] = old.spaceNames?[String(space)]
            wallpapers[destination] = old.spaceWallpapers?[String(space)]
        }
        TahoePreferences.shared.value.spaceNames = names; TahoePreferences.shared.value.spaceWallpapers = wallpapers
        TahoePreferences.shared.value.appSpaceAssignments = old.appSpaceAssignments?.mapValues { space in space == index ? max(0, index - 1) : space > index ? space - 1 : space }
        state.removeSpace(index)
    }
    func assignApplication(_ window: TahoeWindow, space: Int?) {
        var assignments = TahoePreferences.shared.value.appSpaceAssignments ?? [:]
        assignments[window.applicationIdentity.key] = space
        TahoePreferences.shared.value.appSpaceAssignments = assignments
    }
    private func applyPlacement(_ id: UUID) {
        guard let window = state.windows.first(where: { $0.id == id }),
              let space = TahoePreferences.shared.value.appSpaceAssignments?[window.applicationIdentity.key],
              (0..<state.spaceCount).contains(space) else { return }
        state.moveToSpace(id, space: space); state.focus(id)
    }
    func openArrangement(_ item: TahoeArrangement) {
        while state.spaceCount < min(6, item.snapshot.spaces) { state.addSpace() }
        var mapped: [UUID: UUID] = [:]
        for saved in item.snapshot.windows {
            let id: UUID
            if saved.kind == .browser, let browser = item.snapshot.browsers.first(where: { $0.windowID == saved.id }) {
                var snapshot = browser
                snapshot.regenerateTabIDs()
                let session = TahoeBrowserSession(snapshot: snapshot)
                id = state.open(.browser, title: saved.title, resourceID: saved.resourceID)
                browsers[id] = session; connect(session, to: id)
            } else if saved.kind == .files {
                id = state.open(.files, title: saved.title, resourceID: saved.resourceID)
            } else if saved.kind == .livecontainer {
                open(.livecontainer); guard let management = state.windows.first(where: { $0.kind == .livecontainer }) else { continue }; id = management.id
            } else if saved.kind == .installer {
                id = openInstaller()
            } else if saved.kind != .guest && saved.kind != .notes && saved.kind != .calculator {
                id = state.open(saved.kind, title: saved.title)
            } else { continue }
            mapped[saved.id] = id
            state.moveToSpace(id, space: min(state.spaceCount - 1, max(0, saved.space)))
            if saved.allSpaces == true { state.toggleAllSpaces(id) }
            if saved.alwaysOnTop == true { state.setAlwaysOnTop(id) }
            state.setFrame(saved.preferredFrame ?? saved.frame, for: id); state.setLayout(saved.layout, for: id)
        }
        if let active = item.snapshot.active.flatMap({ mapped[$0] }) { state.focus(active) }
        else { state.switchSpace(min(state.spaceCount - 1, max(0, item.snapshot.space))) }
        overlay = nil; scheduleSave()
    }

    init() {
        do {
            pinned = try TahoeStorage.read("web-apps.json", as: [TahoeWebLink].self) ?? [
                TahoeWebLink(title: "Mail", url: URL(string: "https://mail.google.com")!, symbol: "envelope.fill"),
                TahoeWebLink(title: "YouTube", url: URL(string: "https://www.youtube.com")!, symbol: "play.rectangle.fill")
            ]
            bookmarks = try TahoeStorage.read("bookmarks.json", as: [TahoeWebLink].self) ?? []
            pinned = pinned.filter { TahoeStorage.isWebURL($0.url) }
            bookmarks = bookmarks.filter { TahoeStorage.isWebURL($0.url) }
        } catch { self.error = "Saved web apps could not be read: \(error.localizedDescription)" }
        let key = "TahoeStandaloneBuiltins.v1"
        if error == nil && !UserDefaults.standard.bool(forKey: key) {
            for link in [TahoeWebLink(title: "Notes", url: URL(string: "https://www.icloud.com/notes/")!, symbol: "note.text"),
                         TahoeWebLink(title: "Calculator", url: URL(string: "https://www.desmos.com/scientific")!, symbol: "plus.forwardslash.minus")] {
                if !pinned.contains(where: { $0.url.host == link.url.host && $0.title == link.title }) { pinned.append(link) }
            }
            do { try TahoeStorage.write(pinned, to: "web-apps.json"); UserDefaults.standard.set(true, forKey: key) }
            catch { self.error = error.localizedDescription }
        }
    }

    func present(_ overlay: TahoeOverlay) {
        TahoeMenuCoordinator.shared.dismiss()
        menu = nil; self.overlay = self.overlay == overlay ? nil : overlay
        if self.overlay == .overview { refreshOverview() }
    }
    func refreshOverview() {
        guard overlay == .overview else { return }
        overviewTask?.cancel(); overviewRevision = UUID()
        thumbnails.removeAll()
        thumbnailOrder.removeAll()
        let space = state.currentSpace, revision = overviewRevision
        let windows = Array(state.windows.reversed().filter { state.belongs($0, to: space) && !$0.minimized }.prefix(24))
        overviewTask = Task { [weak self] in
            for window in windows {
                guard let self, !Task.isCancelled, self.overviewRevision == revision, self.overlay == .overview,
                      let session = self.browsers[window.id], let view = session.tabs.first(where: { $0.id == session.selectedID })?.activePage.webView, view.bounds.width > 0 else { continue }
                let configuration = WKSnapshotConfiguration(); configuration.snapshotWidth = 360
                let image: UIImage? = await withCheckedContinuation { continuation in view.takeSnapshot(with: configuration) { image, _ in continuation.resume(returning: image) } }
                guard !Task.isCancelled, self.overviewRevision == revision, self.state.currentSpace == space, self.state.windows.contains(where: { $0.id == window.id }) else { continue }
                if let image { self.storeThumbnail(image, for: window.id) }
            }
        }
    }
    func storeThumbnail(_ image: UIImage, for id: UUID) {
        thumbnailOrder.removeAll { $0 == id }; thumbnailOrder.append(id); thumbnails[id] = image
        while thumbnailOrder.count > 24 { thumbnails.removeValue(forKey: thumbnailOrder.removeFirst()) }
    }
    func purgeThumbnails() { overviewTask?.cancel(); thumbnails.removeAll(); thumbnailOrder.removeAll(); TahoeWindowMotion.shared.cancelAll() }

    func start() {
        guard !hasOpenedInitialWindow else { return }
        hasOpenedInitialWindow = true
        TahoeBrowserResources.shared.attach(self)
        if TahoePreferences.shared.value.restoreWorkspace {
            do {
                if let saved = try TahoeStorage.read("workspace.json", as: TahoeSavedWorkspace.self), saved.version == 1 {
                    for browser in saved.browsers {
                        let session = TahoeBrowserSession(snapshot: browser)
                        browsers[browser.windowID] = session
                        connect(session, to: browser.windowID)
                    }
                    state.restore(saved.windows.filter { $0.kind != .browser || browsers[$0.id] != nil }, active: saved.active, space: saved.space, spaces: saved.spaces)
                    if let fraction = saved.tileFraction { state.setTileFraction(CGFloat(fraction)) }
                    let liveIDs = Set(state.windows.map(\.id))
                    browsers = browsers.filter { liveIDs.contains($0.key) }
                    let managementIDs = state.windows.filter { $0.kind == .livecontainer }.map(\.id)
                    for id in managementIDs.dropFirst() { state.close(id) }
                    let installerIDs = state.windows.filter { $0.kind == .installer }.map(\.id)
                    for id in installerIDs.dropFirst() { state.close(id) }
                    if let id = installerIDs.first { connectInstaller(id) }
                    let legacyKinds: [TahoeWindowKind] = [.notes, .calculator].filter { kind in state.windows.contains { $0.kind == kind } }
                    for id in state.windows.filter({ $0.kind == .notes || $0.kind == .calculator }).map(\.id) { state.close(id) }
                    for kind in legacyKinds { open(kind) }
                    if !state.windows.isEmpty { resumeFocusedBrowser(); return }
                }
            } catch { self.error = "The saved workspace could not be restored: \(error.localizedDescription)" }
        }
        // Legacy Notes windows never mount the custom editor after this upgrade.
        for id in state.windows.filter({ $0.kind == .notes }).map(\.id) { state.close(id) }
        // First launch is a clean desktop; applications open from Dock/Launchpad.
    }

    func open(_ kind: TahoeWindowKind) {
        if kind == .installer { openInstaller(); return }
        if kind == .files { openFiles(TahoeFileStore.shared.root); return }
        if kind == .calculator { openWebApp(TahoeWebLink(title: "Calculator", url: URL(string: "https://www.desmos.com/scientific")!, symbol: "plus.forwardslash.minus")); return }
        if kind == .notes { openWebApp(TahoeWebLink(title: "Notes", url: URL(string: "https://www.icloud.com/notes/")!, symbol: "note.text")); return }
        if kind != .browser, let window = state.windows.first(where: { $0.kind == kind }) {
            state.focus(window.id)
            return
        }
        if kind == .browser { openBrowser(); return }
        let id = state.open(kind, title: kind.title); applyPlacement(id)
    }

    func openBrowser(url: URL = URL(string: "https://www.apple.com")!) {
        let session = TahoeBrowserSession(url: url)
        let id = state.open(.browser, title: "Browser")
        browsers[id] = session
        connect(session, to: id)
        applyPlacement(id)
    }

    func applicationName(for window: TahoeWindow) -> String {
        if let resource = window.resourceID, let app = pinned.first(where: { $0.url.absoluteString == resource }) { return app.title }
        if window.isWebApp, let resource = window.resourceID, let host = URL(string: resource)?.host { return host == "chatgpt.com" ? "ChatGPT" : host }
        return window.kind == .guest ? window.title : window.kind.title
    }

    @discardableResult func openInstaller() -> UUID {
        showManagement = false
        if let existing = state.windows.first(where: { $0.kind == .installer }) {
            if guests[existing.id] == nil || guests[existing.id]?.terminated == true {
                guests[existing.id]?.close(); connectInstaller(existing.id)
            }
            state.focus(existing.id); overlay = nil; return existing.id
        }
        let id = state.open(.installer, title: "SideInstaller", resourceID: TahoeInstallerRuntime.bundle)
        connectInstaller(id); applyPlacement(id); overlay = nil; return id
    }
    private func connectInstaller(_ id: UUID) {
        let session = TahoeGuestSession(relativeBundlePath: TahoeInstallerRuntime.bundle, dataUUID: TahoeInstallerRuntime.container, completion: nil)
        guests[id] = session
        session.lifecycleChanged = { [weak self] in self?.objectWillChange.send() }
    }
    func applicationWindows(for window: TahoeWindow) -> [TahoeWindow] {
        state.windows.filter { $0.applicationIdentity == window.applicationIdentity }
    }
    func beginTabTransfer(_ id: UUID, session: TahoeBrowserSession, token: String, strip: CGRect) {
        guard let source = browsers.first(where: { $0.value === session }) else { return }
        tabTransfer = TahoeBrowserTabTransfer(tabID: id, windowID: source.key, token: token, strip: strip)
    }
    func beginChatTransfer(_ chats: TahoeChatWorkspace, id: UUID, token: String, strip: CGRect) {
        guard let host = chats.host, let source = browsers.first(where: { $0.value.tabs.contains { $0 === host } }) else { return }
        tabTransfer = TahoeBrowserTabTransfer(tabID: id, windowID: source.key, token: token, strip: strip, chats: chats)
    }
    @discardableResult func moveTransfer(_ transfer: TahoeBrowserTabTransfer, to windowID: UUID, before target: UUID? = nil, chats destinationChats: TahoeChatWorkspace? = nil) -> Bool {
        guard let source = browsers[transfer.windowID], let destination = browsers[windowID] else { return false }
        if let sourceChats = transfer.chats, sourceChats === destinationChats, let target {
            sourceChats.move(transfer.tabID, before: target); return true
        }
        if transfer.chats == nil, source === destination, let target { source.move(transfer.tabID, before: target); return true }
        guard let page = transfer.chats?.pages[transfer.tabID] ?? source.tabs.first(where: { $0.id == transfer.tabID }),
              destinationChats.map({ $0.canAdopt(page) }) ?? destination.canAdopt(page) else { return false }
        let emptyHost = transfer.chats.flatMap { $0.state.items.count == 1 ? $0.host : nil }
        let moved = transfer.chats?.extract(transfer.tabID) ?? source.extract(transfer.tabID)
        guard let moved else { return false }
        if let destinationChats { destinationChats.adopt(moved, before: target) }
        else { destination.adopt(moved, before: target) }
        if let emptyHost { source.extract(emptyHost.id)?.release() }
        if source.tabs.isEmpty { closeConfirmed(transfer.windowID) }
        else {
            let home = state.windows.first(where: { $0.id == transfer.windowID })?.resourceID.flatMap(URL.init(string:))
            source.ensureTab(url: home); source.changed?()
        }
        state.focus(windowID); scheduleSave(); return true
    }
    func detachBrowserTab(_ id: UUID, session: TahoeBrowserSession) {
        guard let source = browsers.first(where: { $0.value === session }) else { return }
        detachBrowserTab(id, from: source.key)
    }
    /// A transfer moves ownership, not just the URL: do not call release on
    /// the extracted page, which would destroy its draft and live response.
    func detachBrowserTab(_ id: UUID, from sourceID: UUID, screenPoint: CGPoint? = nil) {
        guard let source = browsers[sourceID], source.visibleTabs.contains(where: { $0.id == id }) else { return }
        if source.visibleTabs.count == 1 { placeWindow(sourceID, screenPoint: screenPoint); return }
        guard let page = source.extract(id) else { return }
        let resource = state.windows.first(where: { $0.id == sourceID })?.resourceID
        installDetachedPage(page, resourceID: resource, screenPoint: screenPoint)
        source.changed?()
    }
    func detachChat(_ chats: TahoeChatWorkspace, id: UUID, screenPoint: CGPoint? = nil) {
        guard let host = chats.host,
              let source = browsers.first(where: { _, session in session.tabs.contains { $0 === host } }) else { return }
        guard source.value.visibleTabs.contains(where: { $0 === host }) else { return }
        if chats.state.items.count == 1 && source.value.visibleTabs.count == 1 {
            placeWindow(source.key, screenPoint: screenPoint); return
        }
        let wasLast = chats.state.items.count == 1
        guard let page = chats.extract(id) else { return }
        let resource = state.windows.first(where: { $0.id == source.key })?.resourceID
        installDetachedPage(page, resourceID: resource, screenPoint: screenPoint)
        if wasLast { source.value.close(host.id) }
        source.value.changed?()
    }
    private func installDetachedPage(_ page: TahoeBrowserTab, resourceID: String?, screenPoint: CGPoint?) {
        let session = TahoeBrowserSession(adopting: page)
        let id = state.open(.browser, title: page.title, resourceID: resourceID)
        browsers[id] = session; connect(session, to: id)
        placeWindow(id, screenPoint: screenPoint)
        scheduleSave()
    }
    private func placeWindow(_ id: UUID, screenPoint: CGPoint?) {
        state.focus(id)
        guard let point = screenPoint else { return }
        if state.fullscreenID == id { state.toggleFullscreen(id) }
        state.setLayout(.floating, for: id)
        guard let window = state.windows.first(where: { $0.id == id }) else { return }
        state.move(id, from: window.frame, translation: CGSize(width: point.x-window.frame.midX, height: point.y-window.frame.minY-32))
    }

    func openFiles(_ url: URL, newWindow: Bool = false, reveal: URL? = nil) {
        let existing = newWindow ? nil : state.windows.last(where: { $0.kind == .files })?.id
        let id = existing ?? state.open(.files, title: "Finder", resourceID: url.absoluteString)
        if existing == nil { applyPlacement(id) }
        finderLocations[id] = url
        if let reveal { finderReveal[id] = reveal }
        state.focus(id); finderLocation = url; overlay = nil
    }
    func selectSettings(_ section: String) {
        guard section != settingsSection else { return }
        settingsBackStack.append(settingsSection); settingsForwardStack.removeAll(); settingsSection = section
    }
    func settingsBack() {
        guard let section = settingsBackStack.popLast() else { return }
        settingsForwardStack.append(settingsSection); settingsSection = section
    }
    func settingsForward() {
        guard let section = settingsForwardStack.popLast() else { return }
        settingsBackStack.append(settingsSection); settingsSection = section
    }
    func minimize(_ id: UUID) {
        guard let window = state.windows.first(where: { $0.id == id }) else { return }
        TahoeKeyboard.dismiss()
        let key = window.kind == .guest ? runningApps.application(for: id)?.dockID ?? "guest-\(id)" :
            window.isWebApp ? pinned.first(where: { $0.url.absoluteString == window.resourceID })?.id.uuidString ?? "web-running-\(window.resourceID ?? "")" : window.kind.rawValue
        if let rect = dockFrames[key] { minimizeTargets[id] = CGPoint(x: rect.midX, y: rect.midY) }
        if let session = browsers[id], let tab = session.tabs.first(where: { $0.id == session.selectedID }), let view = tab.activePage.webView, view.bounds.width > 0 {
            let config = WKSnapshotConfiguration(); config.snapshotWidth = 240
            view.takeSnapshot(with: config) { [weak self] image, _ in
                guard let image else { return }
                DispatchQueue.main.async { if self?.state.windows.contains(where: { $0.id == id && $0.minimized }) == true { self?.storeThumbnail(image, for: id) } }
            }
        }
        TahoeWindowMotion.shared.prepare(window, workspace: self,
            target: minimizeTargets[id] ?? CGPoint(x: state.canvas.width / 2, y: state.canvas.height - 40))
        state.minimize(id)
    }
    func closeActive() {
        guard let id = state.activeID else { return }
        if let session = browsers[id], session.visibleTabs.count > 1, let tab = session.selectedID { session.close(tab) }
        else { close(id) }
    }
    func nextTab(_ delta: Int) {
        guard let id = state.activeID, let session = browsers[id], !session.visibleTabs.isEmpty else { return }
        let visible = session.visibleTabs
        let index = visible.firstIndex(where: { $0.id == session.selectedID }) ?? 0
        session.selectedID = visible[(index + delta + visible.count) % visible.count].id
    }
    func newTab() { if let id = state.activeID, state.windows.first(where: { $0.id == id })?.isWebApp == true { openBrowser(); return }; if let id = state.activeID, let session = browsers[id] { session.add() } else { openBrowser() } }
    func escape() { if menu != nil { menu = nil } else if overlay != nil { overlay = nil } else if let id = state.fullscreenID { state.toggleFullscreen(id) } }
    func focusAddress() { if let id = state.activeID { NotificationCenter.default.post(name: .tahoeFocusAddress, object: id) } }

    func pinWebApp(title: String, url: URL, icon: TahoeWebIconDraft? = nil) {
        guard TahoeStorage.isWebURL(url), !pinned.contains(where: { $0.url == url }) else { return }
        pinned.append(TahoeWebLink(title: title.isEmpty ? url.host ?? "Web App" : String(title.prefix(50)), url: url))
        saveLinks()
        if let link = pinned.last {
            if let icon { setWebIcon(link.id, draft: icon) } else { loadWebIcon(link) }
        }
    }
    func setWebIcon(_ id: UUID, draft: TahoeWebIconDraft?) {
        guard pinned.contains(where: { $0.id == id }) else { return }
        iconRevision &+= 1; let revision = iconRevision; iconEditRevisions[id] = revision
        let destination = TahoeWebIconEditor.sourceURL(id)
        Task {
            do {
                let icon = try await TahoeWebIconWriter.shared.save(draft, id: id, destination: destination, revision: revision)
                guard iconEditRevisions[id] == revision, let index = pinned.firstIndex(where: { $0.id == id }) else { return }
                pinned[index].iconData = icon; pinned[index].customIcon = draft != nil
                pinned[index].iconZoom = draft?.crop.zoom; pinned[index].iconOffsetX = draft?.crop.x; pinned[index].iconOffsetY = draft?.crop.y
                saveLinks(); if draft == nil { loadWebIcon(pinned[index]) }
            } catch { if iconEditRevisions[id] == revision { self.error = error.localizedDescription } }
        }
    }
    private func loadWebIcon(_ link: TahoeWebLink) {
        guard link.iconData == nil, iconRequests.insert(link.id).inserted,
              var parts = URLComponents(url: link.url, resolvingAgainstBaseURL: false) else { return }
        parts.path = "/favicon.ico"; parts.query = nil; parts.fragment = nil
        guard let url = parts.url else { iconRequests.remove(link.id); return }
        Task {
            defer { iconRequests.remove(link.id) }
            do {
                let (file, response) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: file) }
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                      (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576,
                      let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary),
                      let index = pinned.firstIndex(where: { $0.id == link.id }), pinned[index].customIcon != true else { return }
                pinned[index].iconData = UIImage(cgImage: cg).pngData(); saveLinks()
            } catch { /* The symbol remains available when a website has no icon. */ }
        }
    }
    func unpin(_ id: UUID) { pinned.removeAll { $0.id == id }; try? FileManager.default.removeItem(at: TahoeWebIconEditor.sourceURL(id)); saveLinks() }
    func reorderPinned(_ id: UUID, before target: UUID) {
        guard id != target, let from = pinned.firstIndex(where: { $0.id == id }), pinned.contains(where: { $0.id == target }) else { return }
        let link = pinned.remove(at: from)
        if let index = pinned.firstIndex(where: { $0.id == target }) { pinned.insert(link, at: index) }
        saveLinks()
    }
    func addBookmark(title: String, url: URL) {
        guard TahoeStorage.isWebURL(url), !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.append(TahoeWebLink(title: title.isEmpty ? url.host ?? "Bookmark" : String(title.prefix(80)), url: url))
        saveLinks()
    }
    func removeBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; saveLinks() }
    func importLinks(bookmarks incomingMarks: [TahoeWebLink], webApps incomingApps: [TahoeWebLink]) {
        for link in incomingMarks where TahoeStorage.isWebURL(link.url) && !bookmarks.contains(where: { $0.url == link.url }) {
            bookmarks.append(TahoeWebLink(title: String(link.title.prefix(120)), url: link.url, folder: link.folder.map { String($0.prefix(80)) }))
        }
        for link in incomingApps where TahoeStorage.isWebURL(link.url) && !pinned.contains(where: { $0.url == link.url }) {
            pinned.append(TahoeWebLink(title: String(link.title.prefix(80)), url: link.url))
        }
        saveLinks()
    }
    func editBookmark(_ link: TahoeWebLink, folder: Bool) {
        TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: folder ? "Bookmark Folder" : "Rename Bookmark",
            message: folder ? "Enter a folder name, or leave it empty for Bookmarks." : "Choose a bookmark name.",
            primary: "Save", initialText: folder ? link.folder ?? "" : link.title, accept: { [weak self] value in
                guard let self, let value, let index = self.bookmarks.firstIndex(where: { $0.id == link.id }) else { return }
                if folder { self.bookmarks[index].folder = value.isEmpty ? nil : String(value.prefix(80)) }
                else { self.bookmarks[index].title = String(value.prefix(120)) }
                self.saveLinks()
            })
    }
    func showLibrary(_ section: String = "tabs") { librarySection = section; present(.library) }
    func saveChatWorkspace(_ page: TahoeBrowserTab) {
        guard let descriptor = page.chatHost.savedDescriptor,
              let owner = browsers.first(where: { $0.value.tabs.contains { $0 === page.chatHost } })?.key,
              let window = state.windows.first(where: { $0.id == owner }) else { return }
        let browser = TahoeSavedBrowser(windowID: owner, addresses: [descriptor.url], selected: 0, tabs: [descriptor], profile: descriptor.profile, selectedTabID: descriptor.id)
        let snapshot = TahoeSavedWorkspace(windows: [window], browsers: [browser], active: owner, space: window.space, spaces: state.spaceCount)
        TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Save Chat Workspace", message: "Save these chat addresses and split layout as a named arrangement. Conversation text and drafts are not exported.", primary: "Save", initialText: "Chat Workspace", accept: { value in
            if let value { TahoeArrangements.shared.save(value, snapshot: snapshot) }
        })
    }
    func openHistory(_ visit: TahoeVisit) {
        let profile = visit.profile == TahoeBrowserProfile.work.rawValue ? TahoeBrowserProfile.work : .personal
        let descriptor = TahoeSavedTab(id: UUID(), url: visit.url, profile: profile.rawValue, zoom: 1,
            identity: TahoePreferences.shared.value.browserIdentity.rawValue, pinned: false)
        let session = TahoeBrowserSession(snapshot: TahoeSavedBrowser(windowID: UUID(), addresses: [visit.url], selected: 0, tabs: [descriptor], profile: profile.rawValue, selectedTabID: descriptor.id))
        let id = state.open(.browser, title: visit.title); browsers[id] = session; connect(session, to: id); applyPlacement(id); overlay = nil
    }
    func reopen(_ item: TahoeClosedBrowser) {
        if item.tabs.count == 1, let descriptor = item.tabs.first, let id = state.activeID,
           state.windows.first(where: { $0.id == id })?.isWebApp == false, let session = browsers[id], session.restoreTab(descriptor) {
            state.focus(id); TahoeBrowserLibrary.shared.removeClosed(item.id); overlay = nil; return
        }
        let snapshot = TahoeSavedBrowser(windowID: UUID(), addresses: item.tabs.map(\.url), selected: 0, tabs: item.tabs,
            profile: item.tabs.first?.profile, selectedTabID: item.tabs.first?.id)
        let session = TahoeBrowserSession(snapshot: snapshot)
        let id = state.open(.browser, title: item.title); browsers[id] = session; connect(session, to: id)
        applyPlacement(id)
        TahoeBrowserLibrary.shared.removeClosed(item.id); overlay = nil
    }
    func openWebApp(_ link: TahoeWebLink, newWindow: Bool = false) {
        loadWebIcon(link)
        if !newWindow, let window = state.windows.last(where: { $0.kind == .browser && $0.resourceID == link.url.absoluteString }) { state.focus(window.id) }
        else {
            let session = TahoeBrowserSession(url: link.url)
            let id = state.open(.browser, title: link.title, resourceID: link.url.absoluteString)
            browsers[id] = session
            connect(session, to: id)
            applyPlacement(id)
        }
        overlay = nil
    }
    private func connect(_ session: TahoeBrowserSession, to id: UUID) {
        session.attach(to: self)
        session.changed = { [weak self, weak session] in
            guard let self, let session else { return }
            if let tab = session.tabs.first(where: { $0.id == session.selectedID }) {
                if let window = self.state.windows.first(where: { $0.id == id }), (!window.isWebApp || tab.currentURL?.host == "chatgpt.com"), window.title != tab.title { self.state.rename(id, title: tab.title) }
                if self.state.activeID == id, !tab.hasWebContent { tab.resumeIfNeeded(priority: true) }
            }
            self.scheduleSave()
            TahoeBrowserResources.shared.schedule()
        }
    }
    private func resumeFocusedBrowser() {
        guard let id = state.activeID, let session = browsers[id], let tab = session.tabs.first(where: { $0.id == session.selectedID }), !tab.hasWebContent else { return }
        tab.resumeIfNeeded(priority: true)
    }
    private func saveLinks() {
        linksRevision &+= 1; let revision = linksRevision, links = pinned, marks = bookmarks
        Task {
            do {
                try await TahoeStorageWriter.shared.write(links, to: "web-apps.json", revision: revision)
                try await TahoeStorageWriter.shared.write(marks, to: "bookmarks.json", revision: revision)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func scheduleSave() {
        guard hasOpenedInitialWindow else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveWorkspace() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    func saveWorkspace() {
        guard hasOpenedInitialWindow, TahoePreferences.shared.value.restoreWorkspace else { return }
        saveWork?.cancel()
        let snapshot = makeSnapshot()
        saveRevision &+= 1
        let revision = saveRevision
        Task {
            do { try await TahoeStorageWriter.shared.write(snapshot, to: "workspace.json", revision: revision) }
            catch { self.error = error.localizedDescription }
        }
    }

    func makeSnapshot() -> TahoeSavedWorkspace {
        let restoreWork = TahoePreferences.shared.value.restoreWorkTabs ?? false
        let snapshots = state.windows.compactMap { window -> TahoeSavedBrowser? in
            guard let session = browsers[window.id] else { return nil }
            let restorable = session.tabs.filter { $0.profile == .personal || (restoreWork && $0.profile == .work) }
            let descriptors = restorable.compactMap(\.savedDescriptor)
            guard !descriptors.isEmpty else { return nil }
            let selected = descriptors.firstIndex(where: { $0.id == session.selectedID }) ?? 0
            return TahoeSavedBrowser(windowID: window.id, addresses: descriptors.map(\.url), selected: selected,
                chatWorkspaces: descriptors.map(\.chatWorkspace), tabs: descriptors,
                profile: descriptors.contains(where: { $0.profile == session.profile.rawValue }) ? session.profile.rawValue : descriptors[selected].profile,
                selectedTabID: descriptors[selected].id,
                selectedGroup: descriptors.contains(where: { $0.id == session.selectedID }) ? session.selectedGroup : descriptors[selected].group)
        }
        let savedIDs = Set(snapshots.map(\.windowID))
        let safeWindows = state.windows.filter { $0.kind != .guest && ($0.kind != .browser || savedIDs.contains($0.id)) }.map { window -> TahoeWindow in
            var clean = window
            if let session = browsers[window.id], session.profile == .privateBrowsing || (session.profile == .work && !restoreWork) {
                clean.title = window.isWebApp ? applicationName(for: window) : "Browser"
                if !window.isWebApp { clean.resourceID = nil }
            }
            return clean
        }
        return TahoeSavedWorkspace(windows: safeWindows, browsers: snapshots, active: state.activeID, space: state.currentSpace, spaces: state.spaceCount, tileFraction: Double(state.tileFraction))
    }

    func setChatTabsEnabled(_ enabled: Bool) {
        let pages = browsers.values.flatMap(\.tabs)
        let count = enabled ? 0 : pages.reduce(0) { $0 + $1.protectedChatCount }
        TahoeClosePolicy.perform(owner: UUID(uuidString: "40EEA196-2EF5-47FB-8CC7-B4B970C06920")!, protectedCount: count,
            title: "Turn off ChatGPT chat tabs?") {
            TahoePreferences.shared.value.chatGPTTabs = enabled
            for root in pages {
                if !enabled, let owner = root.chatWorkspace, let page = owner.focusedPage { owner.leave(using: page, confirmed: true) }
                else if enabled, let view = root.webView {
                    view.evaluateJavaScript("window.__sideosChat?.configure({enabled:true});window.__sideosChat?.inspect();", in: nil, in: .defaultClient) { _ in }
                }
            }
        }
    }
    func close(_ id: UUID) { closeWindows([id]) }
    func closeWindows(_ ids: [UUID]) {
        if state.windows.contains(where: { ids.contains($0.id) && $0.kind == .installer }) {
            do {
                guard try TahoeInstallerRuntime.canClose() else {
                    error = "SideInstaller is installing or refreshing an app. Wait for it to finish, or cancel from SideInstaller, before closing its window."
                    return
                }
            } catch { self.error = "Unable to check SideInstaller's current operation: \(error.localizedDescription)"; return }
        }
        guard let owner = ids.first else { return }
        let count = ids.compactMap { browsers[$0] }.flatMap(\.tabs).reduce(0) { $0 + $1.protectedChatCount }
        TahoeClosePolicy.perform(owner: owner, protectedCount: count, title: ids.count == 1 ? "Close window?" : "Close these windows?") { [weak self] in
            for id in ids { self?.closeConfirmed(id) }
        }
    }
    private func closeConfirmed(_ id: UUID) {
        if let session = browsers[id] {
            let title = session.profile == .privateBrowsing ? "Browser Window" : state.windows.first(where: { $0.id == id })?.title ?? "Browser Window"
            TahoeBrowserLibrary.shared.remember(title: title, tabs: session.tabs.compactMap(\.savedDescriptor))
        }
        TahoeWindowMotion.shared.cancel(id)
        if state.activeID == id { TahoeKeyboard.dismiss() }
        minimizeTargets.removeValue(forKey: id); thumbnails.removeValue(forKey: id)
        finderLocations.removeValue(forKey: id); finderReveal.removeValue(forKey: id)
        guests.removeValue(forKey: id)?.close()
        runningApps.detach(id)
        browsers.removeValue(forKey: id)?.tabs.forEach { $0.release() }
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: TahoeMotionSpec.resolve(.presentOverlay, reduced: false).duration)) { state.close(id) }
    }

    func receiveGuest(name: String, bundleID: String, dataUUID: String, completion: ((NSNumber?, Error?) -> Void)?) {
        if let existing = state.windows.first(where: { $0.kind == .guest && $0.resourceID == dataUUID }) {
            if guests[existing.id]?.terminated == true { close(existing.id) }
            else {
                state.focus(existing.id)
                guests[existing.id]?.addCompletion(completion)
                showManagement = false
                return
            }
        }
        let session = TahoeGuestSession(relativeBundlePath: bundleID, dataUUID: dataUUID, completion: completion)
        let id = state.open(.guest, title: name, resourceID: dataUUID)
        state.setApplication(bundleID, for: id)
        applyPlacement(id)
        guests[id] = session
        runningApps.attach(id, to: bundleID)
        session.lifecycleChanged = { [weak self] in self?.objectWillChange.send() }
        showManagement = false
    }

    func focusGuest(dataUUID: String, url: String?) -> Bool {
        guard let window = state.windows.first(where: { $0.kind == .guest && $0.resourceID == dataUUID }),
              let session = guests[window.id], !session.terminated else { return false }
        state.focus(window.id)
        showManagement = false
        if let url { session.controller?.openURLScheme(url) }
        return true
    }

    func launch(_ app: LCAppModel) async {
        await withCheckedContinuation { continuation in
            let id = TahoeActivityCenter.shared.begin("Open \(app.displayName)", owner: "Native apps", queued: true)
            launchQueue.append(LaunchRequest(id: id, app: app, completion: continuation))
            TahoeActivityCenter.shared.setCancellation(id) { [weak self] in
                guard let self, let index = self.launchQueue.firstIndex(where: { $0.id == id }) else { return }
                self.launchQueue.remove(at: index).completion.resume()
            }
            if !launching { launching = true; Task { await self.drainLaunchQueue() } }
        }
    }
    private func drainLaunchQueue() async {
        while !launchQueue.isEmpty {
            let request = launchQueue.removeFirst()
            TahoeActivityCenter.shared.setCancellation(request.id, action: nil)
            await performLaunch(request.app, job: request.id)
            request.completion.resume()
        }
        launching = false
    }
    private func performLaunch(_ app: LCAppModel, job: UUID) async {
        TahoeActivityCenter.shared.update(job, detail: "Checking launch requirements")
        do {
            if app.uiIsJITNeeded { open(.livecontainer) }
            if app.uiIsLocked, !(try await LCUtils.authenticateUser()) { TahoeActivityCenter.shared.finish(job, cancelled: true); return }
            if app.appInfo.helperProcessesSupport {
                showManagement = true
                error = "This app enables LiveContainer helper processes (including RAM donors). The current nightly supports those in classic launch mode. Enable Classic Mode in this app's LiveContainer settings and launch it from the management Apps page."
                TahoeActivityCenter.shared.finish(job, error: NSError(domain: "SideOS.Launch", code: 2, userInfo: [NSLocalizedDescriptionKey: error!]))
                return
            }
            guard app.appInfo.defaultClassicMode == 0, !app.uiIs32bit else {
                showManagement = true
                error = "This guest needs the original LiveContainer launch path. Open it from the management Apps page."
                TahoeActivityCenter.shared.finish(job, error: NSError(domain: "SideOS.Launch", code: 1, userInfo: [NSLocalizedDescriptionKey: error!]))
                return
            }
            if app.uiIsJITNeeded && app.delegate == nil {
                throw NSError(domain: "TahoeDesktop.JIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "The LiveContainer JIT launcher is not ready. Configure your JIT provider in management settings, then try the desktop launcher again."])
            }
            TahoeActivityCenter.shared.update(job, detail: "Preparing JIT and opening application")
            try await app.runApp(multitask: true)
            var recent = TahoePreferences.shared.value.recentNativeApps ?? []
            recent.removeAll { $0 == app.appInfo.relativeBundlePath }; recent.insert(app.appInfo.relativeBundlePath, at: 0)
            TahoePreferences.shared.value.recentNativeApps = Array(recent.prefix(12))
            TahoeActivityCenter.shared.finish(job)
        } catch { self.error = error.localizedDescription; TahoeActivityCenter.shared.finish(job, error: error) }
    }

    func performanceFullscreen(_ id: UUID) {
        thumbnails.removeAll()
        for (windowID, browser) in browsers where windowID != id { browser.hibernate() }
        if state.fullscreenID != id { state.toggleFullscreen(id) }
    }
}

/// Called at LCUtils' presentation boundary, after LCAppModel has prepared the guest.
/// No signing or JIT logic is duplicated here. All PID callbacks belong to a session.
@objc(TahoeGuestRouter)
@MainActor final class TahoeGuestRouter: NSObject {
    @objc(openWithDisplayName:bundleID:dataUUID:completion:)
    static func open(displayName: String, bundleID: String?, dataUUID: String?, completion: ((NSNumber?, Error?) -> Void)?) -> Bool {
        guard let bundleID, let dataUUID, !bundleID.isEmpty, !dataUUID.isEmpty else { return false }
        TahoeWorkspace.shared.receiveGuest(name: displayName, bundleID: bundleID, dataUUID: dataUUID, completion: completion)
        return true
    }
}
