import SwiftUI
import WebKit

@MainActor
final class TahoeBrowserSession: ObservableObject {
    weak var workspace: TahoeWorkspace?
    func attach(to workspace: TahoeWorkspace) { self.workspace = workspace; tabs.forEach { $0.workspace = workspace; $0.chatWorkspace?.reconnect() } }
    @Published var tabs: [TahoeBrowserTab] = []
    @Published private(set) var profile: TahoeBrowserProfile = .personal
    @Published var selectedGroup: String?
    var groupNames: [String] { Array(Set(visibleTabs.compactMap(\.group))).sorted() }
    var stripTabs: [TahoeBrowserTab] {
        guard let selectedGroup else { return visibleTabs }
        let filtered = visibleTabs.filter { $0.group == selectedGroup }
        return filtered.isEmpty ? visibleTabs : filtered
    }
    func selectGroup(_ group: String?) {
        selectedGroup = group
        if !stripTabs.contains(where: { $0.id == selectedID }) { selectedID = stripTabs.first?.id }
        changed?()
    }
    @Published var selectedID: UUID? {
        didSet {
            if selectedID != oldValue {
                if let selectedGroup, let tab = tabs.first(where: { $0.id == selectedID }), tab.group != selectedGroup { self.selectedGroup = tab.group }
                tabs.first(where: { $0.id == selectedID })?.resumeIfNeeded(priority: true)
                changed?()
            }
        }
    }
    var changed: (() -> Void)?
    private var lastSelection: [TahoeBrowserProfile: UUID] = [:]
    // Private data remains memory-only and belongs to this browser session.
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    // Stable identifier means Work cookies persist across SideOS launches but
    // remain isolated from the default Personal data store.
    static let workStore = WKWebsiteDataStore(forIdentifier:
        UUID(uuidString: "52F29A07-A028-4162-A2EB-61FA62127A3C")!)

    var visibleTabs: [TahoeBrowserTab] { tabs.filter { $0.profile == profile } }
    private func dataStore(for profile: TahoeBrowserProfile) -> WKWebsiteDataStore {
        switch profile {
        case .personal: return .default()
        case .work: return Self.workStore
        case .privateBrowsing: return privateStore
        }
    }
    init(url: URL) { add(url: url) }
    init(adopting tab: TahoeBrowserTab) {
        profile = tab.profile
        if profile == .privateBrowsing { privateStore = tab.dataStoreForTransfer }
        wire(tab); tabs = [tab]; selectedID = tab.id
    }
    init(restoring urls: [URL], selected: Int, chatWorkspaces: [TahoeSavedChatWorkspace?]? = nil) {
        for (index, url) in urls.enumerated() where TahoeStorage.isWebURL(url) {
            let saved = chatWorkspaces?.indices.contains(index) == true ? chatWorkspaces?[index] : nil
            let first = saved.flatMap { value in value.urls.indices.contains(value.left) ? value.urls[value.left] : nil } ?? url
            add(url: first, load: false, profile: .personal)
            tabs.last?.restoredChatWorkspace = saved
        }
        if tabs.isEmpty { add(load: false) }
        selectedID = tabs[min(max(0, selected), tabs.count - 1)].id
    }
    convenience init(snapshot: TahoeSavedBrowser) {
        self.init(restoring: snapshot.tabs == nil ? snapshot.addresses : [], selected: snapshot.selected, chatWorkspaces: snapshot.chatWorkspaces)
        guard let descriptors = snapshot.tabs else { return }
        tabs.forEach { $0.release() }; tabs.removeAll()
        for value in descriptors where TahoeStorage.isWebURL(value.url) {
            guard let profile = TahoeBrowserProfile(rawValue: value.profile), profile != .privateBrowsing else { continue }
            let tab = TahoeBrowserTab(url: value.url, load: false,
                identity: TahoeWebsiteIdentity(rawValue: value.identity), profile: profile,
                websiteDataStore: dataStore(for: profile), id: value.id)
            tab.restoredZoom = value.zoom.isFinite ? min(3, max(0.5, value.zoom)) : 1
            tab.pinned = value.pinned; tab.group = value.group; tab.restoredChatWorkspace = value.chatWorkspace
            wire(tab); tabs.append(tab)
        }
        profile = TahoeBrowserProfile(rawValue: snapshot.profile ?? "") ?? .personal
        if profile == .privateBrowsing { profile = .personal }
        if visibleTabs.isEmpty { profile = tabs.first?.profile ?? .personal }
        if visibleTabs.isEmpty { add(load: false) }
        selectedGroup = snapshot.selectedGroup
        selectedID = visibleTabs.first(where: { $0.id == snapshot.selectedTabID })?.id ?? visibleTabs.first?.id
    }
    func selectProfile(_ next: TahoeBrowserProfile) {
        guard next != profile else { return }
        selectedGroup = nil
        if let selectedID { lastSelection[profile] = selectedID }
        profile = next
        if let id = lastSelection[next], tabs.contains(where: { $0.id == id && $0.profile == next }) {
            selectedID = id
        } else if let last = visibleTabs.last {
            selectedID = last.id
        } else {
            add(profile: next)
        }
        changed?()
    }
    @discardableResult
    func add(url: URL = URL(string: "https://www.apple.com")!,
             configuration: WKWebViewConfiguration? = nil, load: Bool = true,
             identity: TahoeWebsiteIdentity? = nil,
             profile requestedProfile: TahoeBrowserProfile? = nil) -> WKWebView? {
        let target = requestedProfile ?? profile
        let tab = TahoeBrowserTab(url: url, configuration: configuration,
                                  load: load, identity: identity, profile: target,
                                  websiteDataStore: dataStore(for: target))
        wire(tab)
        if target == profile { tab.group = selectedGroup }
        tabs.append(tab)
        if target == profile { selectedID = tab.id }
        return tab.webView
    }
    private func wire(_ tab: TahoeBrowserTab) {
        tab.workspace = workspace
        tab.openTab = { [weak self, weak tab] url, configuration, identity in
            self?.add(url: url, configuration: configuration, identity: identity,
                      profile: tab?.profile)
        }
        tab.requestClose = { [weak self, weak tab] in if let tab { self?.close(tab.id) } }
        tab.changed = { [weak self] in self?.changed?() }
        tab.chatWorkspace?.reconnect()
        if tab.chatWorkspace == nil, tab.chatOwner == nil, TahoePreferences.shared.value.chatTabsEnabled {
            // A detached chat becomes an independent workspace without a
            // reload. Clear only the old workspace chrome, not page state.
            tab.configureChat(["enabled": true, "role": "primary", "items": [], "right": NSNull(), "revealed": false])
        }
    }
    func extract(_ id: UUID) -> TahoeBrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let tab = tabs.remove(at: index)
        if selectedID == id { selectedID = visibleTabs.last?.id }
        return tab
    }
    func canAdopt(_ page: TahoeBrowserTab) -> Bool {
        page.profile == profile && (profile != .privateBrowsing || page.dataStoreForTransfer === privateStore)
    }
    func adopt(_ page: TahoeBrowserTab, before target: UUID? = nil) {
        guard !tabs.contains(where: { $0.id == page.id }), canAdopt(page) else { return }
        wire(page)
        if let selectedGroup { page.group = selectedGroup }
        if let target, let index = tabs.firstIndex(where: { $0.id == target }) { tabs.insert(page, at: index) }
        else { tabs.append(page) }
        selectedID = page.id; changed?()
    }
    func ensureTab(url: URL? = nil) { if visibleTabs.isEmpty { add(url: url ?? URL(string: "https://www.apple.com")!) } }
    func restoreTab(_ descriptor: TahoeSavedTab) -> Bool {
        guard descriptor.profile == profile.rawValue, profile != .privateBrowsing,
              !tabs.contains(where: { $0.id == descriptor.id }), TahoeStorage.isWebURL(descriptor.url) else { return false }
        let page = TahoeBrowserTab(url: descriptor.url, load: false, identity: TahoeWebsiteIdentity(rawValue: descriptor.identity),
            profile: profile, websiteDataStore: dataStore(for: profile), id: descriptor.id)
        page.restoredZoom = descriptor.zoom.isFinite ? min(3, max(0.5, descriptor.zoom)) : 1
        page.pinned = descriptor.pinned; page.group = descriptor.group; page.restoredChatWorkspace = descriptor.chatWorkspace
        wire(page); tabs.append(page); selectedID = page.id; changed?(); return true
    }
    func close(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        TahoeClosePolicy.perform(owner: id, protectedCount: tab.protectedChatCount, title: "Close browser tab?") { [weak self] in
            self?.closeConfirmed(id)
        }
    }
    private func closeConfirmed(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if let saved = tab.savedDescriptor { TahoeBrowserLibrary.shared.remember(title: tab.title, tabs: [saved]) }
        tab.release()
        tabs.removeAll { $0.id == id }
        lastSelection = lastSelection.filter { key, value in
            tabs.contains { $0.id == value && $0.profile == key }
        }
        if selectedID == id { selectedID = visibleTabs.last?.id }
        if visibleTabs.isEmpty { add(profile: profile) }
        changed?()
    }
    func move(_ id: UUID, before target: UUID) {
        guard id != target, let index = tabs.firstIndex(where: { $0.id == id }),
              let targetTab = tabs.first(where: { $0.id == target }),
              tabs[index].profile == targetTab.profile else { return }
        let tab = tabs.remove(at: index)
        if let destination = tabs.firstIndex(where: { $0.id == target }) {
            tabs.insert(tab, at: destination)
        }
        changed?()
    }
    func hibernate() { tabs.forEach { $0.hibernate() } }
    func resumePages() {
        let selected = visibleTabs.first(where: { $0.id == selectedID })
        for tab in visibleTabs where tab.id != selectedID { tab.resumeIfNeeded() }
        selected?.resumeIfNeeded(priority: true)
    }
}

