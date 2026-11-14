import SwiftUI
import Network
import MediaPlayer
import UniformTypeIdentifiers

struct TahoeDesktopOverlay: View {
    @ObservedObject var workspace: TahoeWorkspace
    private var panelWidth: CGFloat { min(340, max(1, workspace.state.canvas.width - 24)) }
    private var panelTop: CGFloat { workspace.state.menuHeight + 8 }
    var body: some View {
        ZStack {
            Color.black.opacity(workspace.overlay == .overview ? 0.08 : workspace.overlay == .launchpad ? 0.001 : 0.12).onTapGesture { workspace.overlay = nil }
            switch workspace.overlay {
            case .spotlight: TahoeSpotlight(workspace: workspace).padding(.bottom, 100)
            case .launchpad: TahoeLaunchpad(workspace: workspace)
            case .overview: TahoeOverview(workspace: workspace)
            case .controlCenter:
                TahoeControlCenter().frame(width: panelWidth).padding(.top, panelTop).padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            case .calendar:
                TahoeCalendar().frame(width: panelWidth).padding(.top, panelTop).padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            case .about:
                ScrollView { TahoeAboutView() }
                    .frame(width: min(420, max(1, workspace.state.canvas.width - 48)), height: min(780, max(1, workspace.state.canvas.height - 64)))
                    .padding(12).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 16)).shadow(radius: 30)
            case .library: TahoeBrowserLibraryView(workspace: workspace)
            case .siteInfo: if let page = workspace.activeBrowserPage { TahoeSiteInformation(page: page) }
            case nil: EmptyView()
            }
        }
    }
}

private struct TahoeSpotlightResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
}

private struct TahoeSpotlight: View {
    @ObservedObject var workspace: TahoeWorkspace
    @EnvironmentObject private var model: SharedModel
    @FocusState private var focused: Bool
    @State private var selected = 0
    @State private var files: [URL] = []
    private var results: [TahoeSpotlightResult] {
        let query = workspace.search.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = [TahoeWindowKind.files, .browser, .settings, .applications, .downloads]
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.map { kind in
                TahoeSpotlightResult(id: kind.rawValue, title: kind.title, subtitle: "Application", symbol: kind.symbol) { workspace.open(kind) }
            }
        var seen: Set<URL> = []
        for link in workspace.pinned + workspace.bookmarks where seen.insert(link.url).inserted && (query.isEmpty || link.title.localizedCaseInsensitiveContains(query) || link.url.absoluteString.localizedCaseInsensitiveContains(query)) {
            list.append(TahoeSpotlightResult(id: link.id.uuidString, title: link.title, subtitle: link.url.host ?? "Web App", symbol: link.symbol) { workspace.openWebApp(link) })
        }
        for app in model.apps where !app.uiIsHidden && (query.isEmpty || app.displayName.localizedCaseInsensitiveContains(query)) {
            list.append(TahoeSpotlightResult(id: app.bundleIdentifier, title: app.displayName, subtitle: "Native Application", symbol: "app.fill") { Task { await workspace.launch(app) } })
        }
        let apps = Array(list.prefix(8)); list = []
        for window in workspace.state.windows where query.isEmpty || window.title.localizedCaseInsensitiveContains(query) {
            list.append(TahoeSpotlightResult(id: "window-\(window.id)", title: window.title, subtitle: "Open window · \(workspace.applicationName(for: window))", symbol: "macwindow") { workspace.state.focus(window.id) })
        }
        for (id, session) in workspace.browsers {
            for tab in session.tabs {
                if let chats = tab.chatWorkspace {
                    for chat in chats.state.items where !query.isEmpty && chat.title.localizedCaseInsensitiveContains(query) {
                        list.append(TahoeSpotlightResult(id: "chat-\(chat.id)", title: chat.title, subtitle: "Open chat · \(tab.profile.title)", symbol: "bubble.left.and.bubble.right") {
                            workspace.state.focus(id); session.selectProfile(tab.profile); session.selectedID = tab.id; chats.selectChat(chat.id)
                        })
                    }
                } else if !query.isEmpty && tab.title.localizedCaseInsensitiveContains(query) {
                    list.append(TahoeSpotlightResult(id: "tab-\(tab.id)", title: tab.title, subtitle: "Open tab · \(tab.profile.title)", symbol: "rectangle.on.rectangle") { workspace.state.focus(id); session.selectProfile(tab.profile); session.selectedID = tab.id })
                }
            }
        }
        list = Array(list.prefix(8)) + apps
        for url in files.prefix(6) {
            list.append(TahoeSpotlightResult(id: url.absoluteString, title: url.lastPathComponent, subtitle: "File · \(url.deletingLastPathComponent().lastPathComponent)", symbol: "doc.text") { workspace.openFiles(url.deletingLastPathComponent(), reveal: url) })
        }
        if !query.isEmpty, let url = TahoeAddress.url(for: query, provider: TahoePreferences.shared.value.searchProvider ?? .google) {
            list.append(TahoeSpotlightResult(id: "web-search", title: query.contains(".") ? "Open \(query)" : "Search the web for “\(query)”", subtitle: "Browser", symbol: "magnifyingglass") { workspace.openBrowser(url: url) })
        }
        return list
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 23, weight: .light)).foregroundStyle(.secondary)
                TextField(TahoeStrings.ui("Spotlight Search"), text: $workspace.search).font(.system(size: 23, weight: .light)).focused($focused)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { activate(selected) }
                if !workspace.search.isEmpty { Button { workspace.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(TahoePressStyle()).accessibilityLabel("Clear search") }
            }.padding(20)
            Divider().opacity(0.4)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button { activate(index) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: result.symbol).font(.system(size: 22)).foregroundStyle(selected == index ? .white : TahoeDesign.accent).frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                    Text(result.subtitle).font(.system(size: 11)).opacity(0.7).lineLimit(1)
                                }
                                Spacer()
                                if index == selected { Image(systemName: "return").font(.system(size: 12)).opacity(0.7) }
                            }.padding(.horizontal, 12).frame(height: 48)
                                .foregroundStyle(selected == index ? Color.white : .primary)
                                .background(selected == index ? TahoeDesign.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(TahoePressStyle())
                    }
                }.padding(8)
            }.frame(maxHeight: max(60, min(360, workspace.state.canvas.height - 180)))
        }
        .frame(maxWidth: 640).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12).padding(24)
        .onAppear { focused = true }
        .onChange(of: workspace.search) { _, _ in selected = 0 }
        .onKeyPress(.downArrow) { selected = max(0, min(results.count - 1, selected + 1)); return .handled }
        .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
        .task(id: workspace.search) {
            let query = workspace.search
            files = []
            guard !query.isEmpty else { files = []; return }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let roots = [TahoeFileStore.shared.root, TahoeFileStore.shared.downloads, TahoeFileStore.shared.desktop]
            if let found = try? await TahoeFileWorker.shared.search(query, roots: roots), !Task.isCancelled { files = found }
        }
    }
    private func activate(_ index: Int) {
        let values = results
        guard values.indices.contains(index) else { return }
        workspace.overlay = nil
        values[index].action()
    }
}

private struct TahoeLaunchpad: View {
    @ObservedObject var workspace: TahoeWorkspace
    @EnvironmentObject private var model: SharedModel
    @ObservedObject private var preferences = TahoePreferences.shared
    @State private var query = ""
    @State private var category = "All"
    @State private var adding = false
    @State private var choosingIcon = false
    @State private var iconDraft: TahoeWebIconDraft?
    @State private var name = ""
    @State private var address = ""
    private let kinds: [TahoeWindowKind] = [.settings, .browser, .files, .livecontainer, .installer, .downloads]
    private func webCategory(_ link: TahoeWebLink) -> String {
        let host = link.url.host?.lowercased() ?? ""
        if ["youtube", "instagram", "facebook", "reddit", "tiktok", "bsky"].contains(where: { host.contains($0) }) { return "Social" }
        if ["google", "icloud", "office", "notion", "chatgpt"].contains(where: { host.contains($0) }) { return "Productivity" }
        return "Other"
    }
    private var visibleKinds: [TahoeWindowKind] { kinds.filter { (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) && (category == "All" || category == "Utilities" && $0 != .notes && $0 != .browser || category == "Productivity" && ($0 == .notes || $0 == .browser)) } }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                HStack(spacing: 8) {
                    ForEach(["Utilities", "Social", "Productivity", "Other"], id: \.self) { value in
                        Button { category = category == value ? "All" : value } label: {
                            Text(value).font(.system(size: 14)).frame(maxWidth: .infinity).frame(minHeight: 44).contentShape(Rectangle())
                                .background(category == value ? Color.white.opacity(0.22) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(TahoePressStyle()).foregroundStyle(.primary).accessibilityAddTraits(category == value ? [.isSelected] : [])
                    }
                }.padding(.horizontal, 20).padding(.bottom, 12)
                Divider().opacity(0.3)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 16)], spacing: 22) {
                        ForEach(visibleKinds, id: \.self) { kind in
                            launchButton(kind.title) { workspace.open(kind); workspace.overlay = nil } icon: { TahoeAppIcon(kind: kind, size: preferences.value.compactDesktop ? 54 : 64) }
                                .contextMenu { Button(TahoeStrings.ui("Keep in Dock")) { preferences.value.hiddenDockKinds = (preferences.value.hiddenDockKinds ?? []).filter { $0 != kind.rawValue } } }
                        }
                        ForEach(workspace.pinned.filter { (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) && (category == "All" || category == webCategory($0)) }) { link in
                            launchButton(link.title) { workspace.openWebApp(link) } icon: { TahoeWebAppIcon(link: link, size: preferences.value.compactDesktop ? 54 : 64) }
                                .contextMenu {
                                    Button(TahoeStrings.ui("Edit Icon…")) { workspace.editingWebIcon = link }
                                    Button(TahoeStrings.ui("Remove Web App"), role: .destructive) { workspace.unpin(link.id) }
                                }
                        }
                        if category == "All" || category == "Other" {
                            ForEach(model.apps.filter { !$0.uiIsHidden && (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)) }, id: \.self) { app in
                                launchButton(app.displayName) { workspace.overlay = nil; Task { await workspace.launch(app) } } icon: { TahoeNativeAppIcon(app: app, size: preferences.value.compactDesktop ? 54 : 64) }
                            }
                        }
                    }.padding(20)
                }
            }.frame(width: min(878, max(280, geometry.size.width - 40)), height: min(602, max(240, geometry.size.height - 160)))
                .modifier(TahoeLauncherMaterial()).environment(\.colorScheme, .dark)
                .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.35), lineWidth: 0.5).allowsHitTesting(false) }
                .clipShape(RoundedRectangle(cornerRadius: 26)).shadow(color: .black.opacity(0.3), radius: 25, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge").font(.system(size: 22))
            TextField(TahoeStrings.ui("Applications"), text: $query, prompt: Text(TahoeStrings.ui("Applications")).foregroundColor(.primary)).font(.system(size: 26, weight: .medium)).textFieldStyle(.plain).autocorrectionDisabled()
            Menu {
                Button(TahoeStrings.ui("Add Web App…")) { adding = true }
                Button(TahoeStrings.ui("Show All Applications")) { category = "All" }
                Button(TahoeStrings.ui("Show All Dock Apps")) { preferences.value.hiddenDockKinds = [] }
                Button(TahoeStrings.ui("Manage Native Apps…")) { workspace.overlay = nil; workspace.showManagement = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.buttonStyle(TahoePressStyle(surface: true, radius: 100)).accessibilityLabel("Application actions")
        }.padding(20).popover(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 14) {
                Text(TahoeStrings.ui("Add Web App")).font(.headline)
                TextField(TahoeStrings.ui("Name"), text: $name).textFieldStyle(.roundedBorder)
                TextField(TahoeStrings.ui("Website URL"), text: $address).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    if let iconDraft, let data = iconDraft.png(side: 64), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    Button(iconDraft == nil ? "Choose Icon…" : "Adjust Icon…") { choosingIcon = true }
                }
                Button(TahoeStrings.ui("Add to Dock")) {
                    if let url = URL(string: address), TahoeStorage.isWebURL(url) { workspace.pinWebApp(title: name, url: url, icon: iconDraft); adding = false; name = ""; address = ""; iconDraft = nil }
                }.buttonStyle(TahoeControlStyle(variant: .accent)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (URL(string: address).map { !TahoeStorage.isWebURL($0) } ?? true))
            }.padding(20).frame(width: 320).presentationCompactAdaptation(.popover)
                .sheet(isPresented: $choosingIcon) { TahoeWebIconEditor(draft: iconDraft) { iconDraft = $0 } }
        }
    }
    private func launchButton<Icon: View>(_ title: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) { VStack(spacing: 9) { icon(); Text(title).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, minHeight: 96, alignment: .top) }
            .buttonStyle(TahoePressStyle()).accessibilityLabel("Launch \(title)")
    }
}

private struct TahoeOverview: View {
    @ObservedObject var workspace: TahoeWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var windows: [TahoeWindow] { workspace.state.windows.filter { workspace.state.belongs($0, to: workspace.state.currentSpace) && !$0.minimized } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<workspace.state.spaceCount, id: \.self) { space in
                            Button { workspace.state.switchSpace(space); workspace.refreshOverview() } label: {
                                Text(workspace.spaceName(space)).font(.system(size: 13))
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(workspace.state.currentSpace == space ? .white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(TahoePressStyle())
                                .accessibilityLabel("Switch to Desktop \(space + 1)")
                                .contextMenu {
                                    Button(TahoeStrings.ui("Remove Desktop"), role: .destructive) { workspace.removeSpace(space); workspace.refreshOverview() }.disabled(workspace.state.spaceCount <= 1)
                                }
                                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                    guard let provider = providers.first else { return false }
                                    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                                        guard let value = value as? String, let id = UUID(uuidString: value) else { return }
                                        DispatchQueue.main.async { workspace.state.moveToSpace(id, space: space); workspace.refreshOverview() }
                                    }
                                    return true
                                }
                        }
                    }.frame(maxWidth: .infinity)
                }.frame(maxWidth: 700)
                Spacer(minLength: 0)
                Button { workspace.state.addSpace(); workspace.refreshOverview() } label: { Image(systemName: "plus").font(.system(size: 25, weight: .light)).frame(width: 36, height: 40) }
                    .buttonStyle(TahoePressStyle()).disabled(workspace.state.spaceCount >= 6).accessibilityLabel("Add Desktop")
            }.padding(.horizontal, 10).frame(height: 44).background(.regularMaterial)
            GeometryReader { geometry in
                let frames = TahoeOverviewLayout.frames(sizes: windows.map { workspace.state.displayFrame($0).size }, canvas: geometry.size)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(windows.prefix(frames.count).enumerated()), id: \.element.id) { index, window in
                        let rect = frames[index]
                        Button {
                            if let full = workspace.state.fullscreenID, full != window.id { workspace.state.toggleFullscreen(full) }
                            workspace.state.focus(window.id); workspace.overlay = nil
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(TahoeDesign.window)
                                if let image = workspace.thumbnails[window.id] { Image(uiImage: image).resizable().scaledToFit() }
                                else { VStack(spacing: 8) { TahoeAppIcon(kind: window.kind, size: 48); Text(window.title).font(.system(size: 13)); Text(TahoeStrings.ui("Preview unavailable")).font(.caption).foregroundStyle(.secondary) } }
                            }.clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        }.buttonStyle(TahoePressStyle()).frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .accessibilityLabel("Show \(window.title)")
                            .onDrag { NSItemProvider(object: window.id.uuidString as NSString) }
                            .contextMenu {
                                ForEach(0..<workspace.state.spaceCount, id: \.self) { space in Button("Move to Desktop \(space + 1)") { workspace.state.moveToSpace(window.id, space: space); workspace.refreshOverview() } }
                                Button(TahoeStrings.ui("Close Window")) { workspace.close(window.id) }
                            }
                    }
                    if windows.isEmpty { Text(TahoeStrings.ui("No windows on this desktop")).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.secondary) }
                }.animation(reduced ? nil : .smooth(duration: 0.22), value: windows.map(\.id))
            }.padding(.bottom, workspace.state.dockInset + 10)
        }.foregroundStyle(.white).accessibilityIdentifier("mission-control")
    }
}

@MainActor final class TahoeSystemStatus: ObservableObject {
    static let shared = TahoeSystemStatus()
    @Published var network = "Checking connection…"
    @Published var battery = UIDevice.current.batteryLevel
    private let monitor = NWPathMonitor()
    private var observations: [NSObjectProtocol] = []
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        battery = UIDevice.current.batteryLevel
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.battery = UIDevice.current.batteryLevel }
            })
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let label = path.status != .satisfied ? "Not Connected" : path.usesInterfaceType(.wifi) ? "Wi-Fi Connected" : path.usesInterfaceType(.cellular) ? "Cellular Connected" : "Connected"
            DispatchQueue.main.async { self?.network = label }
        }
        monitor.start(queue: DispatchQueue(label: "TahoeNetworkStatus"))
    }
}

private struct TahoeControlCenter: View {
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var status = TahoeSystemStatus.shared
    @State private var brightness = 0.5
    private var screen: UIScreen? { TahoeWorkspace.shared.hostWindow?.windowScene?.screen }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "wifi").font(.title2).padding(10).background(TahoeDesign.accent, in: Circle()).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) { Text(TahoeStrings.ui("Network")).fontWeight(.semibold); Text(status.network).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if status.battery >= 0 { Text("\(Int(status.battery * 100))%").font(.caption); Image(systemName: "battery.100") }
            }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                tile("Appearance", symbol: "circle.lefthalf.filled") { preferences.value.appearance = ["dark", "oled"].contains(preferences.value.appearance) ? "light" : "dark" }
                tile("Show Desktop", symbol: "desktopcomputer") { TahoeWorkspace.shared.state.showDesktop(); TahoeWorkspace.shared.overlay = nil }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(TahoeStrings.ui("Display")).fontWeight(.semibold)
                HStack { Image(systemName: "sun.min.fill"); TahoeSlider(value: $brightness, label: "Display brightness").onChange(of: brightness) { _, value in screen?.brightness = CGFloat(value) }; Image(systemName: "sun.max.fill") }
            }.padding(14).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                Text(TahoeStrings.ui("Sound")).fontWeight(.semibold)
                TahoeVolumeControl().frame(height: 30)
            }.padding(14).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Toggle(TahoeStrings.ui("Automatically hide Dock"), isOn: $preferences.value.autoHideDock).toggleStyle(TahoeSwitchStyle()).padding(6)
            Button(TahoeStrings.ui("Desktop Settings…")) { TahoeWorkspace.shared.open(.settings); TahoeWorkspace.shared.overlay = nil }.buttonStyle(TahoeControlStyle())
        }.font(.system(size: 13)).padding(14).modifier(TahoeGlass(radius: 18)).shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .onAppear { if let screen { brightness = Double(screen.brightness) } }
    }
    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 8) { Image(systemName: symbol).font(.title2); Text(title).font(.system(size: 11)) }.frame(maxWidth: .infinity).padding(14).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(TahoePressStyle())
    }
}
private struct TahoeVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { MPVolumeView() }
    func updateUIView(_ view: MPVolumeView, context: Context) { }
}

