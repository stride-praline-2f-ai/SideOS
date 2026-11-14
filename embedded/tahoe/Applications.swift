import SwiftUI

struct TahoeApplicationsView: View {
    @ObservedObject var workspace: TahoeWorkspace
    var filter = ""
    @EnvironmentObject private var model: SharedModel
    @ObservedObject private var preferences = TahoePreferences.shared
    @State private var query = ""
    @FocusState private var searching: Bool
    private let builtins: [TahoeWindowKind] = [.files, .browser, .livecontainer, .installer, .downloads, .settings, .utilities]
    private var search: String { filter.isEmpty ? query : filter }
    @Environment(\.tahoeTrafficInset) private var trafficInset
    var body: some View {
        TahoeSidebar {
            VStack(alignment: .leading, spacing: 6) {
                Text(TahoeStrings.ui("Favourites")).padding(.top, trafficInset > 0 ? 34 : 0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(8)
                Label(TahoeStrings.ui("Applications"), systemImage: "square.grid.2x2.fill").padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .tahoeSidebarSelection(true)
                Button { workspace.openFiles(TahoeFileStore.shared.root) } label: { Label(TahoeStrings.ui("Documents"), systemImage: "folder").padding(8) }
                Button { workspace.open(.downloads) } label: { Label(TahoeStrings.ui("Downloads"), systemImage: "arrow.down.circle").padding(8) }
                Spacer()
                Button(TahoeStrings.ui("Manage Native Apps…")) { workspace.showManagement = true }.padding(8)
            }.font(.system(size: 13)).padding(10)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Text(TahoeStrings.ui("Applications")).font(.system(size: 15, weight: .semibold))
                    if !(preferences.value.recentNativeApps ?? []).isEmpty {
                        Menu("Recent Apps") {
                            ForEach(preferences.value.recentNativeApps ?? [], id: \.self) { path in
                                if let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == path }) { Button(app.displayName) { Task { await workspace.launch(app) } } }
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(TahoeStrings.ui("Search"), text: $query).focused($searching).textFieldStyle(.plain).tahoeField(focused: searching, search: true).frame(maxWidth: 160)
                }.padding(14).tahoeWindowDragRegion().background(TahoeDesign.window)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        section("Desktop Apps") {
                            ForEach(builtins.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }, id: \.self) { kind in
                                tile(kind.title) { workspace.open(kind); workspace.overlay = nil } icon: { TahoeAppIcon(kind: kind, size: preferences.value.compactDesktop ? 44 : 52) }
                            }
                        }
                        section("Web Apps") {
                            ForEach(workspace.pinned.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { link in
                                tile(link.title) { workspace.openWebApp(link) } icon: { TahoeWebAppIcon(link: link, size: preferences.value.compactDesktop ? 44 : 52) }
                                    .contextMenu {
                                        Button(TahoeStrings.ui("Open in New Window")) { workspace.openWebApp(link, newWindow: true) }
                                        Button(TahoeStrings.ui("Edit Icon…")) { workspace.editingWebIcon = link }
                                        Button(TahoeStrings.ui("Remove from Dock")) { workspace.unpin(link.id) }
                                    }
                            }
                        }
                        section("Native Apps") {
                            ForEach(model.apps.filter { !$0.uiIsHidden && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)) }, id: \.self) { app in
                                tile(app.displayName) { workspace.overlay = nil; Task { await workspace.launch(app) } } icon: {
                                    TahoeNativeAppIcon(app: app, size: preferences.value.compactDesktop ? 44 : 52).overlay(alignment: .bottomTrailing) {
                                        if app.uiIsLocked { Image(systemName: "lock.fill").font(.caption).padding(3).background(.regularMaterial, in: Circle()) }
                                    }
                                }.contextMenu {
                                    Button((TahoePreferences.shared.value.nativePins ?? []).contains(app.appInfo.relativeBundlePath) ? "Unpin from Dock" : "Keep in Dock") {
                                        var pins = TahoePreferences.shared.value.nativePins ?? []
                                        if pins.contains(app.appInfo.relativeBundlePath) { pins.removeAll { $0 == app.appInfo.relativeBundlePath } }
                                        else { pins.append(app.appInfo.relativeBundlePath) }
                                        TahoePreferences.shared.value.nativePins = pins
                                    }
                                }
                            }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.background(TahoeDesign.content)
        }.buttonStyle(TahoePressStyle())
            .onChange(of: workspace.state.activeID) { _, id in if id != workspace.state.windows.first(where: { $0.kind == .applications })?.id { searching = false } }
            .onChange(of: workspace.state.windows.first(where: { $0.kind == .applications }).map { workspace.state.isVisible($0) } ?? false) { _, visible in if !visible { searching = false } }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: preferences.value.compactDesktop ? 88 : 100), spacing: 16)], spacing: 24, content: content)
        }
    }
    private func tile<Icon: View>(_ title: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 8) { icon(); Text(title).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center) }
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .top)
        }.accessibilityLabel("Open \(title)")
    }
}

struct TahoeNativeAppIcon: View {
    @ObservedObject var app: LCAppModel
    var size: CGFloat = 48
    @State private var image: UIImage?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22)) }
            else { TahoeAppIcon(kind: .guest, size: size) }
        }.task(id: "\(app.appInfo.relativeBundlePath ?? app.bundleIdentifier)-\(scheme)") {
            guard let source = app.appInfo.iconIsDarkIcon(scheme == .dark) else { image = nil; return }
            let prepared = await source.byPreparingForDisplay()
            guard !Task.isCancelled else { return }
            image = prepared ?? source
        }.accessibilityHidden(true)
    }
}

struct TahoeWebAppIcon: View {
    @State private var image: UIImage?
    let link: TahoeWebLink
    var size: CGFloat = 48
    var body: some View {
        let red = link.url.host?.contains("youtube") == true
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill((red ? Color.red : Color.blue).gradient)
            if link.customIcon == true, let image { Image(uiImage: image).resizable().scaledToFill() }
            else if link.url.host == "www.icloud.com", link.url.path.hasPrefix("/notes") { TahoeAppIcon(kind: .notes, size: size) }
            else if link.url.host == "www.desmos.com", link.url.path.hasPrefix("/scientific") { TahoeAppIcon(kind: .calculator, size: size) }
            else if let image { Image(uiImage: image).resizable().scaledToFit().padding(size * 0.10) }
            else { Image(systemName: link.symbol).font(.system(size: size * 0.55, weight: .medium)).foregroundStyle(.white) }
        }.clipShape(RoundedRectangle(cornerRadius: size * 0.23)).task(id: link.iconData) { image = link.iconData.flatMap { UIImage(data: $0) } }.frame(width: size, height: size)
            .overlay { RoundedRectangle(cornerRadius: size * 0.23).strokeBorder(.white.opacity(0.4), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 2).accessibilityHidden(true)
    }
}

