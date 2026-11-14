import SwiftUI
import WebKit

private struct TahoeMenuFrames: PreferenceKey {
    static var defaultValue: [TahoeMenuKind: CGRect] = [:]
    static func reduce(value: inout [TahoeMenuKind: CGRect], nextValue: () -> [TahoeMenuKind: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct TahoeMenuBar: View {
    @State private var hoveredMenu: TahoeMenuKind?
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var menus = TahoeMenuCoordinator.shared
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var status = TahoeSystemStatus.shared
    private var appName: String {
        guard let active = workspace.state.windows.first(where: { $0.id == workspace.state.activeID }) else { return "Finder" }
        return workspace.applicationName(for: active)
    }
    // Focus does not change the desktop's chrome. Fullscreen keeps its own
    // existing menu-bar treatment, including when this preference is enabled.
    private var clearOnDesktop: Bool {
        TahoeChromePolicy.clearMenu(enabled: preferences.value.desktopMenuIsClear,
                                    fullscreen: workspace.state.fullscreenID != nil,
                                    reduceTransparency: opaque)
    }
    private var compact: Bool { !TahoeDisplayMetrics.shared.current.innerDisplay && workspace.state.canvas.width < 600 }
    private var shortClock: Bool { workspace.state.canvas.width < 850 }
    var body: some View {
        HStack(spacing: 0) {
            menuButton(.apple) { Image(systemName: "apple.logo").font(.system(size: 16)).frame(width: 20) }
            menuButton(.app) { Text(appName).fontWeight(.semibold).lineLimit(1).frame(maxWidth: compact ? 90 : 130, alignment: .leading) }
            if compact {
                Menu {
                    ForEach(Array(workspace.menuKinds.dropFirst(2)), id: \.self) { kind in
                        Button(kind.rawValue.capitalized) { workspace.overlay = nil; workspace.menu = kind }
                    }
                } label: {
                    Image(systemName: "menubar.rectangle").frame(width: 32, height: TahoeDesign.menuBarHeight)
                }
                .buttonStyle(TahoeMenuStatusStyle()).accessibilityLabel("Application menus")
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: TahoeMenuFrames.self,
                            value: Dictionary(uniqueKeysWithValues: workspace.menuKinds.dropFirst(2).map {
                                ($0, geometry.frame(in: .named("tahoe-desktop")))
                            }))
                    }
                }
            } else {
                // Retain the iPad menu headings on the inner screen. At a
                // narrow native resolution the headings can scroll instead
                // of becoming a different phone-style menu.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(workspace.menuKinds.dropFirst(2)), id: \.self) { kind in menuButton(kind) { Text(kind.rawValue.capitalized) } }
                    }.fixedSize(horizontal: true, vertical: false)
                }.frame(height: TahoeDesign.menuBarHeight)
            }
            Spacer(minLength: 6)
            if !compact && status.battery >= 0 {
                Button { workspace.present(.controlCenter) } label: { Image(systemName: status.battery < 0.25 ? "battery.25" : status.battery < 0.6 ? "battery.50" : "battery.100").font(.system(size: 17)) }
                    .buttonStyle(TahoeMenuStatusStyle()).padding(.horizontal, 2).accessibilityLabel("Battery \(Int(status.battery * 100)) percent")
            }
            if !compact {
            Button { workspace.present(.controlCenter) } label: { Image(systemName: status.network.contains("Cellular") ? "antenna.radiowaves.left.and.right" : "wifi").font(.system(size: 14, weight: .regular)) }
                .buttonStyle(TahoeMenuStatusStyle()).padding(.horizontal, 2).accessibilityLabel(status.network)
            }
            Button { workspace.present(.spotlight) } label: { Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .regular)) }
                .buttonStyle(TahoeMenuStatusStyle()).padding(.horizontal, 2).accessibilityLabel("Spotlight")
            Button { workspace.present(.controlCenter) } label: { Image(systemName: "switch.2").font(.system(size: 14)) }
                .buttonStyle(TahoeMenuStatusStyle()).padding(.horizontal, 2).accessibilityLabel("Control Center")
            if !compact || workspace.state.canvas.width >= 420 {
                Button { workspace.present(.calendar) } label: {
                    TimelineView(.everyMinute) { context in
                        if shortClock { Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 13, weight: .medium)).monospacedDigit() }
                        else { Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()).font(.system(size: 13, weight: .medium)).monospacedDigit() }
                    }
                }.buttonStyle(TahoeMenuStatusStyle()).padding(.horizontal, shortClock ? 4 : 10).accessibilityLabel("Date and Calendar")
            }
        }
        // Safari's menu-bar proportions: one continuous 30-point strip,
        // compact regular labels and a semibold active application name.
        .font(.system(size: TahoeDesign.menuFontSize, weight: .regular)).padding(.horizontal, 8)
        .frame(maxWidth: .infinity).frame(height: TahoeDesign.menuBarHeight)
        .foregroundStyle(clearOnDesktop ? Color.white : .primary)
        .shadow(color: clearOnDesktop ? .black.opacity(0.32) : .clear, radius: 1, y: 1)
        .background {
            if !clearOnDesktop {
                Color.clear.modifier(TahoeGlass(radius: 0, clear: workspace.state.fullscreenID == nil, transparency: preferences.value.menuGlass))
                    // A neutral under-tint prevents wallpapers from turning
                    // the menu bar pink or blue while preserving native blur.
                    .overlay {
                        if workspace.state.fullscreenID != nil {
                            (scheme == .dark ? Color.black : Color.white).opacity(0.12)
                        }
                    }
            }
        }
        .onPreferenceChange(TahoeMenuFrames.self) { workspace.menuFrames = $0 }
    }
    private func menuButton<Label: View>(_ kind: TahoeMenuKind, @ViewBuilder label: () -> Label) -> some View {
        Button { workspace.overlay = nil; workspace.menu = workspace.menu == kind ? nil : kind } label: {
            label().padding(.horizontal, 9).frame(height: TahoeDesign.menuBarHeight).contentShape(Rectangle())
                .background(workspace.menu == kind ? Color.primary.opacity(0.13) : hoveredMenu == kind ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(TahoePressStyle()).accessibilityLabel(kind == .apple ? "Apple menu" : kind == .app ? "\(appName) menu" : "\(kind.rawValue.capitalized) menu")
            .onHover { over in
                if over { hoveredMenu = kind } else if hoveredMenu == kind { hoveredMenu = nil }
                // A menu already open should follow the pointer immediately, as on macOS.
                // The first menu still requires an explicit click.
                if over && workspace.menu != nil && workspace.menu != kind {
                    withTransaction(Transaction(animation: nil)) { workspace.menu = kind }
                }
            }
            .background { GeometryReader { geometry in Color.clear.preference(key: TahoeMenuFrames.self, value: [kind: geometry.frame(in: .named("tahoe-desktop"))]) } }
    }
}

struct TahoeMenuPopup: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var menus = TahoeMenuCoordinator.shared
    @Binding var performanceTarget: UUID?
    @ObservedObject private var preferences = TahoePreferences.shared
    var body: some View {
        let frame = menus.request?.anchor ?? workspace.menu.flatMap { workspace.menuFrames[$0] } ?? CGRect(x: 12, y: 0, width: 30, height: TahoeDesign.menuBarHeight)
        TahoeMenuSurface(anchor: frame, entries: menus.request?.entries ?? entries, canvas: workspace.state.canvas,
                         transparency: preferences.value.menuDropdownGlass,
                         dismiss: { menus.dismiss() }, switchMenu: { delta in
            let kinds = workspace.menuKinds
            guard let kind = workspace.menu, let index = kinds.firstIndex(of: kind) else { return }
            workspace.menu = kinds[(index + delta + kinds.count) % kinds.count]
        }, revision: menus.session.revision)
    }
    private var entries: [TahoeMenuEntry] {
        guard let kind = workspace.menu else { return [] }
        let active = workspace.state.windows.first(where: { $0.id == workspace.state.activeID })
        switch kind {
        case .apple:
            return [
                TahoeMenuEntry(title: TahoeStrings.ui("About SideOS"), action: { workspace.present(.about) }), .line(0),
                TahoeMenuEntry(title: TahoeStrings.ui("System Settings…"), symbol: "gearshape", action: { workspace.open(.settings) }),
                TahoeMenuEntry(title: TahoeStrings.ui("Applications…"), action: { workspace.present(.launchpad) }), .line(1),
                TahoeMenuEntry(title: TahoeStrings.ui("Show Desktop"), action: { workspace.state.showDesktop() }),
                TahoeMenuEntry(title: TahoeStrings.ui("Window Overview"), action: { workspace.present(.overview) }), .line(2),
                TahoeMenuEntry(title: TahoeStrings.ui("LiveContainer & SideInstaller…"), action: { workspace.showManagement = true })
            ]
        case .app:
            let appTitle = active.map { workspace.applicationName(for: $0) } ?? "Finder"
            return [TahoeMenuEntry(title: "About \(appTitle)", action: { workspace.present(.about) }), .line(0),
                    TahoeMenuEntry(title: TahoeStrings.ui("Settings…"), action: { workspace.open(.settings) }), .line(1),
                    TahoeMenuEntry(title: TahoeStrings.ui("Close Tab"), shortcut: "⌘W", enabled: active != nil, action: { workspace.closeActive() }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Close Window"), shortcut: "⇧⌘W", enabled: active != nil, action: { if let active { workspace.close(active.id) } }),
                    TahoeMenuEntry(title: "Quit \(appTitle)", enabled: active != nil, action: { if let active { workspace.closeWindows(workspace.applicationWindows(for: active).map(\.id)) } })]
        case .file:
            return [TahoeMenuEntry(title: TahoeStrings.ui("New Browser Window"), shortcut: "⌘N", action: { workspace.openBrowser() }),
                    TahoeMenuEntry(title: TahoeStrings.ui("New Tab"), shortcut: "⌘T", action: { workspace.newTab() }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Open iCloud Notes"), action: { workspace.open(.notes) }),
                    TahoeMenuEntry(title: TahoeStrings.ui("New Folder in Documents"), action: {
                        do { try TahoeFileStore.shared.prepare(); try TahoeFileStore.shared.createFolder(in: TahoeFileStore.shared.root); workspace.openFiles(TahoeFileStore.shared.root) }
                        catch { workspace.error = error.localizedDescription }
                    }), .line(0),
                    TahoeMenuEntry(title: TahoeStrings.ui("Open Location…"), shortcut: "⌘L", enabled: active?.kind == .browser && active?.isWebApp != true, action: { workspace.focusAddress() }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Save Workspace"), shortcut: "⌘S", action: { workspace.saveWorkspace() }), .line(1),
                    TahoeMenuEntry(title: TahoeStrings.ui("Close"), shortcut: "⌘W", enabled: active != nil, action: { workspace.closeActive() })]
        case .edit:
            return [TahoeMenuEntry(title: "Undo", shortcut: "⌘Z", action: { edit("undo:") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Cut"), shortcut: "⌘X", action: { edit("cut:") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Copy"), shortcut: "⌘C", action: { edit("copy:") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Paste"), shortcut: "⌘V", action: { edit("paste:") }), .line(0),
                    TahoeMenuEntry(title: TahoeStrings.ui("Select All"), shortcut: "⌘A", action: { edit("selectAll:") })]
        case .view:
            return [TahoeMenuEntry(title: TahoeStrings.ui("Show Desktop"), checked: workspace.state.desktopExposed, action: { workspace.state.showDesktop() }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Window Overview"), action: { workspace.present(.overview) }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Launchpad"), action: { workspace.present(.launchpad) }), .line(0),
                    TahoeMenuEntry(title: workspace.state.fullscreenID == nil ? "Enter Fullscreen" : "Exit Fullscreen", shortcut: "⌃⌘F", enabled: active != nil, action: { if let active { workspace.state.toggleFullscreen(active.id) } }), .line(1),
                    TahoeMenuEntry(title: TahoeStrings.ui("Show Desktop Icons"), checked: preferences.value.desktopIcons, action: { preferences.value.desktopIcons.toggle() }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Automatically Hide Dock"), checked: preferences.value.autoHideDock, action: { preferences.value.autoHideDock.toggle() })]
        case .history:
            guard let active, let session = workspace.browsers[active.id], let tab = session.tabs.first(where: { $0.id == session.selectedID }), let web = tab.webView else { return [] }
            var items = [TahoeMenuEntry(title: TahoeStrings.ui("Back"), enabled: web.canGoBack, action: { web.goBack() }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Forward"), enabled: web.canGoForward, action: { web.goForward() }), .line(0)]
            items += web.backForwardList.backList.reversed().enumerated().map { index, item in
                TahoeMenuEntry(title: item.title ?? item.url.host ?? item.url.absoluteString, key: "history-\(index)", action: { web.go(to: item) })
            }
            return items
        case .bookmarks:
            guard let active, let session = workspace.browsers[active.id], let tab = session.tabs.first(where: { $0.id == session.selectedID }) else { return [] }
            var items = [TahoeMenuEntry(title: TahoeStrings.ui("Add Bookmark"), symbol: "bookmark", enabled: tab.currentURL != nil, action: {
                if let url = tab.currentURL { workspace.addBookmark(title: tab.title, url: url) }
            }), .line(0)]
            items += workspace.bookmarks.map { link in
                TahoeMenuEntry(title: link.title, key: link.id.uuidString, action: { tab.address = link.url.absoluteString; tab.navigate() })
            }
            return items
        case .go:
            return [TahoeMenuEntry(title: TahoeStrings.ui("Documents"), symbol: "folder", action: { workspace.openFiles(TahoeFileStore.shared.root) }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Downloads"), symbol: "arrow.down.circle", action: { workspace.openFiles(TahoeFileStore.shared.downloads) }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Applications"), symbol: "square.grid.2x2", action: { workspace.open(.applications) }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Trash"), symbol: "trash", action: { workspace.openFiles(TahoeFileStore.shared.trash) })]
        case .window:
            var values = [TahoeMenuEntry(title: TahoeStrings.ui("Minimise"), shortcut: "⌘M", enabled: active != nil, action: { if let active { workspace.minimize(active.id) } }),
                          TahoeMenuEntry(title: TahoeStrings.ui("Zoom"), enabled: active != nil, action: { if let active { workspace.state.toggleMaximize(active.id) } }),
                          TahoeMenuEntry(title: TahoeStrings.ui("Tile Left"), enabled: active != nil, action: { if let active { workspace.state.setLayout(.left, for: active.id) } }),
                          TahoeMenuEntry(title: TahoeStrings.ui("Tile Right"), enabled: active != nil, action: { if let active { workspace.state.setLayout(.right, for: active.id) } }),
                          TahoeMenuEntry(title: TahoeStrings.ui("Restore Size"), enabled: active != nil, action: { if let active { workspace.state.setLayout(.floating, for: active.id) } }),
                          TahoeMenuEntry(title: TahoeStrings.ui("Performance Fullscreen…"), enabled: active != nil, action: { performanceTarget = active?.id }), .line(0)]
            values.insert(TahoeMenuEntry(title: TahoeStrings.ui("Arrange Window"), symbol: "rectangle.split.2x2", enabled: active != nil, children: TahoeWindowLayout.allCases.map { layout in
                TahoeMenuEntry(title: layout.title, enabled: workspace.state.canApply(layout), checked: active?.layout == layout, key: "layout-\(layout.rawValue)", action: { if let active { workspace.state.setLayout(layout, for: active.id) } })
            }), at: 1)
            values.insert(TahoeMenuEntry(title: TahoeStrings.ui("Keep on Top"), enabled: active != nil, checked: active?.alwaysOnTop == true, action: { if let active { workspace.state.setAlwaysOnTop(active.id) } }), at: 2)
            values.insert(TahoeMenuEntry(title: "Show on All Desktops", enabled: active != nil, checked: active?.allSpaces == true, action: { if let active { workspace.state.toggleAllSpaces(active.id) } }), at: 3)
            values.append(TahoeMenuEntry(title: "Assign New App Windows to This Desktop", enabled: active != nil, action: { if let active { workspace.assignApplication(active, space: workspace.state.currentSpace) } }))
            values.append(TahoeMenuEntry(title: "Clear App Desktop Assignment", enabled: active != nil, action: { if let active { workspace.assignApplication(active, space: nil) } }))
            let spaces = (0..<workspace.state.spaceCount).map { space in
                TahoeMenuEntry(title: "Desktop \(space + 1)", enabled: active != nil, checked: active?.space == space, action: { if let active { workspace.state.moveToSpace(active.id, space: space) } })
            }
            values.append(TahoeMenuEntry(title: TahoeStrings.ui("Move to Desktop"), enabled: active != nil, children: spaces))
            values.append(TahoeMenuEntry(title: active?.onWirelessDisplay == true ? "Bring to Main Display" : "Move to Wireless Display", symbol: "display.2",
                enabled: active != nil && workspace.state.wirelessCanvas != nil, action: { if let active { TahoeWirelessDisplay.shared.move(active.id, remote: active.onWirelessDisplay != true) } }))
            values.append(TahoeMenuEntry(title: "Wireless Display Settings…", action: { if let settings = workspace.state.windows.first(where: { $0.kind == .settings && $0.onWirelessDisplay == true }) { TahoeWirelessDisplay.shared.move(settings.id, remote: false) }; workspace.selectSettings("Wireless Display"); workspace.open(.settings) }))
            values.append(TahoeMenuEntry(title: "Stop Wireless Display", enabled: workspace.state.wirelessCanvas != nil, action: { TahoeWirelessDisplay.shared.stop() }))
            values.append(.line(1))
            values += workspace.state.windows.map { window in TahoeMenuEntry(title: window.title, symbol: window.onWirelessDisplay == true ? "display.2" : window.minimized ? "diamond" : "", checked: window.id == active?.id, key: window.id.uuidString, action: { workspace.state.focus(window.id) }) }
            return values
        case .help:
            return [TahoeMenuEntry(title: TahoeStrings.ui("Commands…"), shortcut: "⇧⌘P", action: { workspace.openTools("Actions") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Getting Started and Keyboard Shortcuts"), action: { workspace.openTools("Help") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Activity Center"), action: { workspace.openTools("Activity") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("Saved Arrangements"), action: { workspace.openTools("Layouts") }),
                    TahoeMenuEntry(title: TahoeStrings.ui("About SideOS"), action: { workspace.present(.about) })]
        }
    }
    private func edit(_ action: String) {
        let responder = TahoeResponderBox()
        UIApplication.shared.sendAction(#selector(UIResponder.tahoeCaptureResponder(_:)), to: nil, from: responder, for: nil)
        if responder.value is UITextInput { UIApplication.shared.sendAction(Selector(action), to: nil, from: nil, for: nil); return }
        if workspace.state.activeID == nil {
            NotificationCenter.default.post(name: .tahoeDesktopCommand, object: action)
        } else if workspace.state.windows.first(where: { $0.id == workspace.state.activeID })?.kind == .files {
            NotificationCenter.default.post(name: .tahoeFileCommand, object: action)
        } else { UIApplication.shared.sendAction(Selector(action), to: nil, from: nil, for: nil) }
    }
}

private struct TahoeMenuStatusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TahoePressStyle(radius: 4).makeBody(configuration: configuration)
            .frame(minWidth: 30, minHeight: TahoeDesign.menuBarHeight).contentShape(Rectangle())
    }
}

