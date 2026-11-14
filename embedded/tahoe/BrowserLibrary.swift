import SwiftUI

struct TahoeVisit: Codable, Identifiable, Sendable {
    var id = UUID()
    var url: URL
    var title: String
    var profile: String
    var date = Date()
}

struct TahoeReopenShortcut: View {
    @ObservedObject private var library = TahoeBrowserLibrary.shared
    @EnvironmentObject private var workspace: TahoeWorkspace
    var body: some View {
        Button("Reopen Closed Tab") { if let item = library.closed.first { workspace.reopen(item) } }
            .keyboardShortcut("t", modifiers: [.command, .shift]).disabled(library.closed.isEmpty)
    }
}
struct TahoeClosedBrowser: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var tabs: [TahoeSavedTab]
    var date = Date()
}
private struct TahoeLibrarySnapshot: Codable, Sendable {
    var visits: [TahoeVisit]
    var closed: [TahoeClosedBrowser]
}

@MainActor final class TahoeBrowserLibrary: ObservableObject {
    static let shared = TahoeBrowserLibrary()
    @Published private(set) var visits: [TahoeVisit] = []
    @Published private(set) var closed: [TahoeClosedBrowser] = []
    private var revision: UInt64 = 0
    private var saveTask: Task<Void, Never>?
    init() {
        if let snapshot = try? TahoeStorage.read("browser-library.json", as: TahoeLibrarySnapshot.self) {
            visits = snapshot.visits.filter { $0.profile != TahoeBrowserProfile.privateBrowsing.rawValue }
            closed = snapshot.closed.filter { !$0.tabs.contains { $0.profile == TahoeBrowserProfile.privateBrowsing.rawValue } }
        }
    }
    func record(url: URL, title: String, profile: TahoeBrowserProfile) {
        guard profile != .privateBrowsing, TahoeStorage.isWebURL(url), TahoePreferences.shared.value.saveHistory ?? true else { return }
        visits.removeAll { $0.url == url && $0.profile == profile.rawValue && Date().timeIntervalSince($0.date) < 300 }
        visits.insert(TahoeVisit(url: url, title: String(title.prefix(200)), profile: profile.rawValue), at: 0)
        visits = Array(visits.prefix(2000)); save()
    }
    func remember(title: String, tabs: [TahoeSavedTab]) {
        let safe = tabs.filter { $0.profile != TahoeBrowserProfile.privateBrowsing.rawValue }
        guard !safe.isEmpty else { return }
        closed.insert(TahoeClosedBrowser(title: String(title.prefix(200)), tabs: safe), at: 0)
        closed = Array(closed.prefix(30)); save()
    }
    func removeClosed(_ id: UUID) { closed.removeAll { $0.id == id }; save() }
    func clear(profile: TahoeBrowserProfile? = nil) {
        if let profile {
            visits.removeAll { $0.profile == profile.rawValue }
            closed = closed.compactMap { group in
                var group = group
                if group.tabs.contains(where: { $0.profile == profile.rawValue }) { group.tabs.removeAll { $0.profile == profile.rawValue }; group.title = "Browser Window" }
                return group.tabs.isEmpty ? nil : group
            }
        }
        else { visits.removeAll(); closed.removeAll() }
        save()
    }
    private func save() {
        saveTask?.cancel(); revision &+= 1
        let revision = revision, snapshot = TahoeLibrarySnapshot(visits: visits, closed: closed)
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(200)); try await TahoeStorageWriter.shared.write(snapshot, to: "browser-library.json", revision: revision) }
            catch is CancellationError { }
            catch { TahoeWorkspace.shared.error = "Browser history could not be saved: \(error.localizedDescription)" }
        }
    }
}

struct TahoeBrowserLibraryView: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var library = TahoeBrowserLibrary.shared
    @State private var query = ""
    @State private var section = "tabs"
    @State private var profileFilter = "all"
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(TahoeStrings.ui("Browser Library")).font(.title3.bold()); Spacer()
                Button(TahoeStrings.ui("Done")) { workspace.overlay = nil }.buttonStyle(TahoeControlStyle())
            }
            TahoeSearchField(text: $query, active: true)
            Picker(TahoeStrings.ui("Library"), selection: $section) {
                Text(TahoeStrings.ui("Open Tabs")).tag("tabs"); Text(TahoeStrings.ui("History")).tag("history")
                Text(TahoeStrings.ui("Recently Closed")).tag("closed"); Text(TahoeStrings.ui("Bookmarks")).tag("bookmarks")
            }.pickerStyle(.segmented)
            if section == "history" {
                Picker("Profile", selection: $profileFilter) { Text("All Profiles").tag("all"); Text("Personal").tag("personal"); Text("Work").tag("work") }.pickerStyle(.segmented)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    switch section {
                    case "history":
                        ForEach(library.visits.filter { (profileFilter == "all" || $0.profile == profileFilter) && matches($0.title, $0.url.absoluteString) }) { visit in
                            row(visit.title, subtitle: "\(visit.profile.capitalized) · \(visit.url.host ?? "") · \(visit.date.formatted(date: .abbreviated, time: .shortened))", symbol: "clock") {
                                workspace.openHistory(visit)
                            }
                        }
                    case "closed":
                        ForEach(library.closed.filter { matches($0.title, $0.tabs.first?.url.absoluteString ?? "") }) { item in
                            row(item.title, subtitle: "\(item.tabs.count) tab(s) · \(item.date.formatted(date: .abbreviated, time: .shortened))", symbol: "arrow.uturn.backward") {
                                workspace.reopen(item)
                            }
                        }
                    case "bookmarks":
                        ForEach(workspace.bookmarks.filter { matches($0.title, $0.url.absoluteString) }) { link in
                            HStack {
                                row(link.title, subtitle: "\(link.folder ?? "Bookmarks") · \(link.url.host ?? "")", symbol: "bookmark") { workspace.openBrowser(url: link.url); workspace.overlay = nil }
                                Menu {
                                    Button(TahoeStrings.ui("Rename…")) { workspace.editBookmark(link, folder: false) }
                                    Button(TahoeStrings.ui("Move to Folder…")) { workspace.editBookmark(link, folder: true) }
                                    Button(TahoeStrings.ui("Delete"), role: .destructive) { workspace.removeBookmark(link.id) }
                                } label: { Image(systemName: "ellipsis.circle").padding(10) }
                            }
                        }
                    default:
                        ForEach(workspace.state.windows.filter { $0.kind == .browser }) { window in
                            if let session = workspace.browsers[window.id] {
                                ForEach(session.tabs.filter { matches($0.title, $0.address) }) { tab in
                                    row(tab.title, subtitle: "\(tab.profile.title) · \(tab.currentURL?.host ?? "")\(tab.isSleeping ? " · Sleeping" : "")", symbol: tab.pinned ? "pin.fill" : "rectangle.on.rectangle") {
                                        workspace.state.focus(window.id); session.selectProfile(tab.profile); session.selectedID = tab.id; workspace.overlay = nil
                                    }
                                }
                            }
                        }
                    }
                }
            }.frame(minHeight: 240, maxHeight: 480)
            if section == "history" || section == "closed" {
                Button(TahoeStrings.ui("Clear History and Recently Closed…"), role: .destructive) {
                    TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Clear browser history?", message: "This removes local history and recently closed tabs for the selected profile filter. Downloaded files and open tabs are kept.", primary: "Clear", destructive: true, accept: { _ in library.clear(profile: section == "history" ? TahoeBrowserProfile(rawValue: profileFilter) : nil) })
                }.buttonStyle(TahoeControlStyle())
            }
        }.padding(20).frame(maxWidth: 720).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 24).padding(24).onAppear { section = workspace.librarySection }
    }
    private func matches(_ title: String, _ url: String) -> Bool { query.isEmpty || title.localizedCaseInsensitiveContains(query) || url.localizedCaseInsensitiveContains(query) }
    private func row(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(TahoeDesign.accent)
                VStack(alignment: .leading, spacing: 4) { Text(title).lineLimit(1); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer(); Image(systemName: "arrow.up.forward").foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle(surface: true))
    }
}
