import SwiftUI
import UniformTypeIdentifiers

private struct TahoeDockItem: Identifiable {
    let id: String
    let title: String
    var kind: TahoeWindowKind?
    var link: TahoeWebLink?
    var window: TahoeWindow?
    var guestPath: String?
    var trash = false
    var preview: Bool { id.hasPrefix("min-") }
    var auxiliary: Bool { preview || kind == .downloads || trash }
}

private struct TahoeDockFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct TahoeDock: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var fileStore = TahoeFileStore.shared
    @ObservedObject private var downloads = TahoeDownloads.shared
    @EnvironmentObject private var model: SharedModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchCounts: [String: Int] = [:]
    @State private var pointer: CGFloat?
    @State private var hovered: String?
    @State private var revealed = false
    @State private var pointerInside = false
    @State private var hasTrash = false
    private var items: [TahoeDockItem] {
        var result: [TahoeDockItem] = [TahoeWindowKind.files, .browser, .applications, .livecontainer, .installer, .settings].map { kind in
            TahoeDockItem(id: kind.rawValue, title: kind.title, kind: kind)
        }
        result.removeAll { preferences.value.hiddenDockKinds?.contains($0.id) == true }
        result += workspace.pinned.map { TahoeDockItem(id: $0.id.uuidString, title: $0.title, link: $0) }
        var webIdentities = Set(workspace.pinned.map { $0.url.absoluteString })
        for window in workspace.state.windows where window.isWebApp {
            guard let resource = window.resourceID, webIdentities.insert(resource).inserted, let url = URL(string: resource) else { continue }
            result.append(TahoeDockItem(id: "web-running-" + resource, title: workspace.applicationName(for: window),
                link: TahoeWebLink(title: workspace.applicationName(for: window), url: url)))
        }
        let nativePins = preferences.value.nativePins ?? []
        result += nativePins.map { path in
            let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == path })
            let running = workspace.runningApps.applications.first(where: { $0.id == path })
            let window = workspace.state.windows.last(where: { running?.windows.contains($0.id) == true })
            return TahoeDockItem(id: "guest-\(path)", title: app?.displayName ?? "Unavailable App", window: window, guestPath: path)
        }
        result += workspace.runningApps.applications.compactMap { app in
            guard !nativePins.contains(app.id) else { return nil }
            guard let window = workspace.state.windows.last(where: { app.windows.contains($0.id) }) else { return nil }
            return TahoeDockItem(id: app.dockID, title: window.title, window: window, guestPath: app.id)
        }
        result += workspace.state.windows.filter(\.minimized).sorted { $0.id.uuidString < $1.id.uuidString }.map { TahoeDockItem(id: "min-\($0.id)", title: $0.title, window: $0) }
        if preferences.value.hiddenDockKinds?.contains("downloads") != true {
            result.append(TahoeDockItem(id: "downloads", title: "Downloads", kind: .downloads))
        }
        result.append(TahoeDockItem(id: "trash", title: "Trash", trash: true))
        return result
    }
    private var containerWidth: CGFloat { max(1, workspace.state.canvas.width - 32) }
    private var visible: Bool { !preferences.value.autoHideDock || revealed }
    var body: some View {
        let items = items
        let separators = Set(items.indices.filter { $0 > 0 && items[$0].auxiliary && !items[$0 - 1].auxiliary })
        let baseline = TahoeDockGeometry.layout(count: items.count, available: containerWidth, maximum: TahoeDesign.dockMaximum,
            automatic: preferences.value.dockFitsAutomatically, separatorBefore: separators, magnification: preferences.value.magnification && !reduceMotion, minimumSlot: 44)
        let size = baseline.iconSize
        let hover = preferences.value.magnification && !reduceMotion ? pointer.map { $0 - max(0, (containerWidth - baseline.naturalWidth) / 2) } : nil
        let layout = TahoeDockGeometry.layout(count: items.count, available: containerWidth, maximum: TahoeDesign.dockMaximum,
                                             automatic: preferences.value.dockFitsAutomatically, separatorBefore: separators, magnification: preferences.value.magnification && !reduceMotion, pointer: hover, minimumSlot: 44)
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if separators.contains(index) {
                            Rectangle().fill(.primary.opacity(0.18)).frame(width: 0.5, height: size * 0.72).padding(.horizontal, 3).padding(.bottom, 10)
                        }
                        itemView(item, scaled: layout.widths[index])
                            .transition(reduceMotion ? .identity : .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                    }
                }.padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 4)
                    .modifier(TahoeNativeDockGlass())
                    .frame(minWidth: containerWidth, minHeight: size * 1.5 + 24, alignment: .bottom)
            }.frame(width: containerWidth).scrollClipDisabled()
                // Measure the pointer in the fixed viewport. The magnifying
                // panel changes width, so its moving origin cannot feed back
                // into the next magnification sample.
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): pointer = point.x; pointerInside = true
                    case .ended:
                        pointer = nil; hovered = nil; pointerInside = false
                        if preferences.value.autoHideDock { revealed = false }
                    }
                }
                .offset(y: visible ? 0 : size * 1.5 + 40).opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
            if preferences.value.autoHideDock && !visible {
                Button {
                        revealed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if !pointerInside { revealed = false } }
                } label: {
                    Capsule().fill(.primary.opacity(0.5)).frame(width: 36, height: 4)
                        .frame(width: 64, height: 44).contentShape(Rectangle())
                }.buttonStyle(TahoePressStyle()).onHover { if $0 { revealed = true } }
                    .accessibilityLabel("Reveal Dock")
            }
        }.frame(width: containerWidth, height: size * 1.5 + 24)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: visible)
            .animation(reduceMotion || !preferences.value.magnification ? nil : .spring(response: 0.22, dampingFraction: 0.9), value: pointer != nil)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: items.map(\.id))
            .onChange(of: preferences.value.autoHideDock ? CGFloat(0) : size + 33, initial: true) { _, inset in
                if workspace.state.dockInset != inset { workspace.state.setDockInset(inset) }
            }
            .onPreferenceChange(TahoeDockFrames.self) { workspace.dockFrames = $0 }
            .task(id: fileStore.revision) { hasTrash = await TahoeFileWorker.shared.hasVisibleEntry(fileStore.trash) }
    }
    private func itemView(_ item: TahoeDockItem, scaled: CGFloat) -> some View {
        return Button {
            if !reduceMotion && item.window == nil && item.kind != .applications && !isRunning(item) {
                launchCounts[item.id, default: 0] += 1
            }
            activate(item)
        } label: {
            VStack(spacing: 4) {
                icon(item, size: scaled)
                    .phaseAnimator([CGFloat(0), -CGFloat(TahoeMotionSpec.resolve(.launchApp, reduced: reduceMotion).displacement), 0], trigger: launchCounts[item.id, default: 0]) { content, phase in
                        content.offset(y: phase)
                    } animation: { _ in .easeInOut(duration: TahoeMotionSpec.resolve(.launchApp, reduced: reduceMotion).duration / 3) }
                    .overlay(alignment: .topTrailing) {
                        if item.kind == .downloads, downloads.items.contains(where: \.active) {
                            Text("\(downloads.items.filter(\.active).count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16).background(.red, in: Capsule()).offset(x: 4, y: -3)
                        }
                    }
                Circle().fill(isRunning(item) ? Color.primary.opacity(0.72) : .clear).frame(width: 3.5, height: 3.5)
            }.frame(width: max(44, scaled), height: max(44, scaled + 8)).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle(radius: 12, scale: 0.92)).accessibilityLabel(item.preview ? "Restore \(item.title)" : item.title).accessibilityIdentifier("dock-\(item.id)")
            .overlay(alignment: .top) {
                if hovered == item.id {
                    Text(item.title).font(.system(size: 12)).lineLimit(1).fixedSize().padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)).offset(y: -38).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onHover { if $0 { hovered = item.id } else if hovered == item.id { hovered = nil } }
            .background { GeometryReader { geometry in Color.clear.preference(key: TahoeDockFrames.self, value: [item.id: geometry.frame(in: .named("tahoe-desktop"))]) } }
            .contextMenu { commands(item) }
            .modifier(TahoeDockDrag(link: item.link.flatMap { link in workspace.pinned.contains(where: { $0.id == link.id }) ? link.id : nil }, workspace: workspace))
    }
    @ViewBuilder private func commands(_ item: TahoeDockItem) -> some View {
        if workspace.state.wirelessCanvas != nil, !windows(for: item).isEmpty {
            Menu("Display Placement") {
                ForEach(windows(for: item)) { candidate in
                    Button((candidate.onWirelessDisplay == true ? "Bring back: " : "Move to display: ") + candidate.title) {
                        TahoeWirelessDisplay.shared.move(candidate.id, remote: candidate.onWirelessDisplay != true)
                    }
                }
            }
            Divider()
        }
        if let link = item.link {
            Button(TahoeStrings.ui("Open")) { workspace.openWebApp(link) }
            Button(TahoeStrings.ui("Open in New Window")) { workspace.openWebApp(link, newWindow: true) }
            ForEach(windows(for: item)) { window in
                Button((window.onWirelessDisplay == true ? "Display · " : window.minimized ? "◇ " : "") + window.title) { workspace.state.focus(window.id) }
            }
            if workspace.pinned.contains(where: { $0.id == link.id }) {
                Button(TahoeStrings.ui("Edit Icon…")) { workspace.editingWebIcon = link }
                Divider(); Button(TahoeStrings.ui("Remove from Dock")) { workspace.unpin(link.id) }
            } else { Button("Keep in Dock") { workspace.pinWebApp(title: link.title, url: link.url) } }
        } else if let path = item.guestPath, item.window == nil {
            Button(TahoeStrings.ui("Open")) { if let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == path }) { Task { await workspace.launch(app) } } else { workspace.showManagement = true } }
            Button(TahoeStrings.ui("Remove from Dock")) { preferences.value.nativePins?.removeAll { $0 == path } }
            Button(TahoeStrings.ui("Manage Apps…")) { workspace.showManagement = true }
        } else if let window = item.window {
            ForEach(windows(for: item)) { candidate in
                Button((candidate.onWirelessDisplay == true ? "Display · " : candidate.minimized ? "◇ " : "") + candidate.title) { workspace.state.focus(candidate.id) }
            }
            Button(TahoeStrings.ui("Show Window")) { workspace.state.focus(window.id) }
            Button(TahoeStrings.ui("Close Window")) { workspace.close(window.id) }
            if item.guestPath != nil {
                Divider()
                if let path = item.guestPath {
                    Button((preferences.value.nativePins ?? []).contains(path) ? "Unpin from Dock" : "Keep in Dock") {
                        var pins = preferences.value.nativePins ?? []
                        if pins.contains(path) { pins.removeAll { $0 == path } } else { pins.append(path) }
                        preferences.value.nativePins = pins
                    }
                }
                Button("Quit \(item.title)") { workspace.closeWindows(windows(for: item).map(\.id)) }
            }
        } else if let kind = item.kind {
            if kind == .applications { Button(TahoeStrings.ui("Mission Control")) { workspace.present(.overview) } }
            if kind == .browser { Button(TahoeStrings.ui("New Window")) { workspace.openBrowser() } }
            if kind == .files { Button(TahoeStrings.ui("New Finder Window")) { workspace.openFiles(fileStore.root, newWindow: true) } }
            Button("Open \(kind.title)") { workspace.open(kind) }
            ForEach(workspace.state.windows.filter { $0.applicationIdentity == .builtIn(kind) }) { window in Button(window.title) { workspace.state.focus(window.id) } }
            if kind != .files && kind != .applications {
                Button(TahoeStrings.ui("Remove from Dock")) {
                    var hidden = preferences.value.hiddenDockKinds ?? []; hidden.append(kind.rawValue); preferences.value.hiddenDockKinds = hidden
                }
            }
            if workspace.state.windows.contains(where: { $0.kind == kind }) {
                Divider(); Button(TahoeStrings.ui("Quit")) { workspace.closeWindows(workspace.state.windows.filter({ $0.applicationIdentity == .builtIn(kind) }).map(\.id)) }
            }
        } else if item.trash {
            Button(TahoeStrings.ui("Open Trash")) { workspace.openFiles(fileStore.trash) }
            Button(TahoeStrings.ui("Empty Trash…"), role: .destructive) {
                TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Empty Trash?", message: "All items in Trash will be permanently deleted. This cannot be undone.", symbol: "trash", primary: "Empty Trash", destructive: true, accept: { _ in
                    Task { do { try await fileStore.emptyTrash() } catch { workspace.error = error.localizedDescription } }
                })
            }.disabled(!hasTrash)
        }
    }
    @ViewBuilder private func icon(_ item: TahoeDockItem, size: CGFloat) -> some View {
        if let link = item.link { TahoeWebAppIcon(link: link, size: size) }
        else if let path = item.guestPath, !item.preview, let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == path }) { TahoeNativeAppIcon(app: app, size: size) }
        else if let window = item.window {
            if item.preview { miniature(window, size: size) }
            else { appIcon(window, size: size) }
        } else if item.kind == .downloads { TahoeFolderIcon(size: size).overlay { Image(systemName: "arrow.down").font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.blue.opacity(0.65)).offset(y: size * 0.10) } }
        else if let kind = item.kind { TahoeAppIcon(kind: kind, size: size) }
        else if item.guestPath != nil { TahoeAppIcon(kind: .guest, size: size) }
        else { TahoeTrashIcon(full: hasTrash, size: size) }
    }
    private func miniature(_ window: TahoeWindow, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color.opacity(0.8)).frame(width: 2.5, height: 2.5) }
                Spacer(minLength: 0)
            }.padding(3).frame(height: 9).background(TahoeDesign.window)
            ZStack {
                if let image = workspace.thumbnails[window.id] { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    TahoeDesign.content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(window.title).font(.system(size: max(4, size * 0.10), weight: .medium)).lineLimit(1)
                        ForEach(0..<2, id: \.self) { _ in Capsule().fill(.primary.opacity(0.09)).frame(height: 1) }
                    }.padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }.frame(height: size * 0.53).clipped()
        }.frame(width: size).clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.25), lineWidth: 0.5) }
            .overlay(alignment: .bottomTrailing) { appIcon(window, size: size * 0.35).offset(x: 3, y: 3) }
            .frame(width: size, height: size).accessibilityHidden(true)
    }
    @ViewBuilder private func appIcon(_ window: TahoeWindow, size: CGFloat) -> some View {
        if let bundle = workspace.guests[window.id]?.relativeBundlePath, let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == bundle || $0.bundleIdentifier == bundle }) {
            TahoeNativeAppIcon(app: app, size: size)
        } else { TahoeAppIcon(kind: window.kind, size: size) }
    }
    private func activate(_ item: TahoeDockItem) {
        if workspace.overlay == .overview {
            workspace.overlay = nil
            if let full = workspace.state.fullscreenID { workspace.state.toggleFullscreen(full) }
        }
        if item.trash { workspace.openFiles(fileStore.trash) }
        else if let window = item.window { if item.preview || !showWindowPicker(item) { workspace.state.focus(window.id) } }
        else if let link = item.link {
            if !showWindowPicker(item) { workspace.openWebApp(link) }
        }
        else if let path = item.guestPath {
            if let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == path }) { Task { await workspace.launch(app) } }
            else { workspace.showManagement = true }
        }
        else if let kind = item.kind {
            if kind == .applications { workspace.present(.launchpad) }
            else if showWindowPicker(item) { }
            else if let existing = workspace.state.windows.last(where: { $0.applicationIdentity == .builtIn(kind) }) { workspace.state.focus(existing.id) }
            else { workspace.open(kind) }
        }
    }
    private func windows(for item: TahoeDockItem) -> [TahoeWindow] {
        if let path = item.guestPath, let app = workspace.runningApps.applications.first(where: { $0.id == path }) {
            return workspace.state.windows.filter { app.windows.contains($0.id) }
        }
        if let link = item.link { return workspace.state.windows.filter { $0.resourceID == link.url.absoluteString } }
        if let kind = item.kind { return workspace.state.windows.filter { $0.applicationIdentity == .builtIn(kind) } }
        return []
    }
    private func showWindowPicker(_ item: TahoeDockItem) -> Bool {
        let matches = windows(for: item)
        guard matches.count > 1 else { return false }
        var entries = matches.map { window in
            TahoeMenuEntry(title: window.title, symbol: window.minimized ? "diamond" : "window",
                checked: workspace.state.activeID == window.id, key: window.id.uuidString,
                action: { workspace.state.focus(window.id) })
        }
        entries.append(.line(0))
        if let front = matches.first(where: { $0.id == workspace.state.activeID }) {
            entries += [TahoeMenuEntry(title: TahoeStrings.ui("Minimise Current Window"), action: { workspace.minimize(front.id) }),
                        TahoeMenuEntry(title: TahoeStrings.ui("Close Current Window"), action: { workspace.close(front.id) })]
        }
        entries.append(TahoeMenuEntry(title: TahoeStrings.ui("Show All Windows"), action: { workspace.present(.overview) }))
        TahoeMenuCoordinator.shared.show(anchor: workspace.dockFrames[item.id] ?? .zero, entries: entries)
        return true
    }
    private func isRunning(_ item: TahoeDockItem) -> Bool {
        if let kind = item.kind { return workspace.state.windows.contains { $0.applicationIdentity == .builtIn(kind) } }
        if let link = item.link { return workspace.state.windows.contains { $0.resourceID == link.url.absoluteString } }
        if item.guestPath != nil { return windows(for: item).contains { workspace.guests[$0.id]?.terminated == false } }
        return item.window != nil && !item.preview
    }

}

private struct TahoeDockDrag: ViewModifier {
    let link: UUID?
    let workspace: TahoeWorkspace
    func body(content: Content) -> some View {
        if let link {
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: "com.aault.tahoe.web-app", visibility: .ownProcess) { completion in
                    completion(Data(link.uuidString.utf8), nil); return nil
                }
                return provider
            }.onDrop(of: ["com.aault.tahoe.web-app"], delegate: TahoeDockDrop(target: link, workspace: workspace))
        } else { content }
    }
}

private struct TahoeDockDrop: DropDelegate {
    let target: UUID?
    let workspace: TahoeWorkspace
    func validateDrop(info: DropInfo) -> Bool { target != nil && info.hasItemsConforming(to: ["com.aault.tahoe.web-app"]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let target, let provider = info.itemProviders(for: ["com.aault.tahoe.web-app"]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: "com.aault.tahoe.web-app") { data, _ in
            guard let data, let text = String(data: data, encoding: .utf8), let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async { workspace.reorderPinned(id, before: target) }
        }
        return true
    }
}

