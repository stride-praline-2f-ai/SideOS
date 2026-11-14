import SwiftUI
import QuickLook

struct TahoeDesktopView: View {
    @ObservedObject var workspace: TahoeWorkspace
    @MainActor init(workspace: TahoeWorkspace? = nil) { self.workspace = workspace ?? .shared }
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var display = TahoeDisplayMetrics.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var performanceTarget: UUID?
    @ObservedObject private var fullscreenChrome = TahoeFullscreenChrome.shared
    private let menus = TahoeMenuCoordinator.shared
    @ObservedObject private var dialogs = TahoeDialogCoordinator.shared
    @AppStorage("SideOSHostSafetyAcknowledged.v2") private var browserSafetyAcknowledged = false
    @AppStorage("SideOSWelcomeDismissed.v1") private var welcomeDismissed = false

    var body: some View {
        presentedDesktop
        .onChange(of: workspace.state.activeID) { _, _ in menus.dismiss() }
        .onChange(of: workspace.state.fullscreenID) { _, _ in fullscreenChrome.reset() }
        .onChange(of: preferences.value.compactDesktop) { _, compact in
            workspace.state.setViewportChrome(menuHeight: display.current.menuHeight,
                prefersFilled: display.current.prefersFilledWindows, compact: compact)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background { TahoeWirelessDisplay.shared.stop() }
            TahoePageRestoration.shared.setActive(phase == .active)
            workspace.guests.values.forEach { $0.setActive(phase == .active) }
            if phase != .active { workspace.saveWorkspace(); preferences.save() }
        }
        .environmentObject(workspace)
        .environment(\.tahoeOLED, preferences.value.appearance == "oled")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if TahoeWirelessDisplay.shared.hosting { TahoeWirelessDisplay.shared.stop(keeping: "Display sharing stopped because of memory pressure. All windows are local.") }
        }
        .onChange(of: performanceTarget) { _, target in
            guard let target else { return }
            dialogs.dialog = TahoeDialog(title: "Enter Performance Fullscreen?", message: "Other eligible browser pages will be unloaded. Unsaved page state and navigation history will be lost. Active downloads are retained.", symbol: "arrow.up.left.and.arrow.down.right", primary: "Enter Fullscreen", destructive: true, accept: { _ in
                workspace.performanceFullscreen(target); performanceTarget = nil
            }, reject: { performanceTarget = nil })
        }
    }


    private var managedCanvas: some View {
        desktopCanvas
        .onChange(of: workspace.state.fullscreenID) { _, _ in TahoeWindowMotion.shared.cancelAll() }
        .onChange(of: workspace.state.currentSpace) { _, _ in TahoeWindowMotion.shared.cancelAll() }
        .onChange(of: workspace.state.desktopExposed) { _, _ in TahoeWindowMotion.shared.cancelAll() }
        .onChange(of: reduceMotion) { _, reduced in if reduced { TahoeWindowMotion.shared.cancelAll() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { TahoeWindowMotion.shared.cancelAll() } }
        .background { TahoeSceneWindow(workspace: workspace) }
        .background { TahoeDisplayAnchor().allowsHitTesting(false) }
        .sheet(item: $workspace.editingWebIcon) { link in
            TahoeWebIconEditor(link: link) { draft in workspace.setWebIcon(link.id, draft: draft) }
        }
        .background { TahoeOverviewGestureObserver() .allowsHitTesting(false) }
    }

    private var presentedDesktop: some View {
        managedCanvas
        .ignoresSafeArea(.container)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .tahoeDialog($dialogs.dialog)
        .ignoresSafeArea(.container)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(preferences.colorScheme)
        .buttonStyle(TahoePressStyle())
        .tint(preferences.value.accentColor).accentColor(preferences.value.accentColor)
        .background { TahoeDesktopCommandSurface(workspace: workspace) }
        .overlay(alignment: .bottomLeading) {
            if !browserSafetyAcknowledged && workspace.state.fullscreenID == nil && workspace.overlay == nil {
                TahoeBrowserSafetyCard { browserSafetyAcknowledged = true }
                    .frame(width: min(420, max(1, workspace.state.canvas.width - 24)))
                    .padding(.leading, 12).padding(.bottom, workspace.state.dockInset + 12)
            } else if !welcomeDismissed && workspace.state.fullscreenID == nil && workspace.overlay == nil && !workspace.showManagement {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(TahoeStrings.ui("Welcome to SideOS")).font(.headline); Spacer(); Button { welcomeDismissed = true } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss welcome") }
                    Text(TahoeStrings.ui("Explore window layouts, ChatGPT tabs, drag-and-drop and keyboard shortcuts.")).font(.callout)
                    Button(TahoeStrings.ui("Getting Started")) { welcomeDismissed = true; workspace.openTools("Help") }.buttonStyle(TahoeControlStyle())
                }.padding(16).frame(width: 300).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).shadow(radius: 12).padding(.leading, 16).padding(.bottom, workspace.state.dockInset + 12)
            }
        }
    }

    private var desktopCanvas: some View {
        GeometryReader { geometry in
            let layout = display.layout(for: geometry.size)
            ZStack(alignment: .topLeading) {
                if workspace.state.fullscreenID == nil || workspace.overlay == .overview {
                    TahoeWallpaper().allowsHitTesting(false)
                } else { Color.black }
                desktopLayers
            .frame(width: layout.viewport.width, height: layout.viewport.height)
            .clipped().coordinateSpace(name: "tahoe-desktop")
            .onDrop(of: ["com.aault.tahoe.browser-tab"], delegate: TahoeBrowserTabDesktopDrop(workspace: workspace))
            .onContinuousHover { phase in
                guard workspace.state.fullscreenID != nil else { return }
                switch phase {
                case .active(let location): fullscreenChrome.pointer(location: location)
                case .ended: fullscreenChrome.pointer(location: nil)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 20, coordinateSpace: .named("tahoe-desktop")).onEnded { value in
                if workspace.state.fullscreenID != nil, value.startLocation.y < 48, value.translation.height > 24 { fullscreenChrome.reveal() }
            })
            .background { TahoeFullscreenPointerObserver(enabled: workspace.state.fullscreenID != nil).allowsHitTesting(false) }
            .onAppear { applyViewport(layout); workspace.start() }
            .onChange(of: layout) { _, value in applyViewport(value) }
            .position(x: layout.insets.left + layout.viewport.width / 2,
                      y: layout.insets.top + layout.viewport.height / 2)
            }
        }
    }

    private func applyViewport(_ layout: TahoeViewportPolicy.Layout) {
        TahoeWindowMotion.shared.cancelAll()
        workspace.state.setViewportChrome(menuHeight: layout.menuHeight, prefersFilled: layout.prefersFilledWindows,
                                          compact: preferences.value.compactDesktop)
        workspace.state.setCanvas(layout.viewport)
    }

    private var desktopLayers: some View {
            ZStack(alignment: .topLeading) {
                if workspace.state.fullscreenID == nil || workspace.overlay == .overview {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { workspace.menu = nil; workspace.overlay = nil; if workspace.state.activeID != nil { workspace.state.activateDesktop() } }
                        .contextMenu {
                            Button(TahoeStrings.ui("New Folder")) { newFolder() }
                            Button(TahoeStrings.ui("Show Desktop")) { workspace.state.showDesktop() }
                            Button(TahoeStrings.ui("Change Wallpaper…")) { workspace.open(.settings) }
                        }
                    if preferences.value.desktopIcons { TahoeDesktopIcons().padding(.top, 36).padding(.bottom, workspace.state.dockInset) }
                } else { Color.black }

                if let layout = workspace.snapPreview {
                    let frame = snapFrame(layout)
                    RoundedRectangle(cornerRadius: 16).fill(TahoeDesign.accent.opacity(0.18))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.65), lineWidth: 2) }
                        .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY).allowsHitTesting(false)
                }

                // The window tree is never reparented by fullscreen, minimise or Spaces.
                ForEach(Array(workspace.state.windows.filter { $0.onWirelessDisplay != true }.enumerated()), id: \.element.id) { index, window in
                    TahoeDesktopWindow(window: window, workspace: workspace) { TahoeWindowContent(window: window, workspace: workspace) }
                        .zIndex(Double(index) + (window.alwaysOnTop == true ? 500 : 0))
                }

                TahoeTileDivider(workspace: workspace).zIndex(800)
                TahoeWindowMotionOverlay().zIndex(900)
                TahoeDesktopChrome(workspace: workspace, performanceTarget: $performanceTarget).zIndex(2000)
            }
    }

    private func snapFrame(_ layout: TahoeWindowLayout) -> CGRect {
        workspace.state.layoutFrame(layout)
    }
    private func newFolder() {
        do { try TahoeFileStore.shared.prepare(); try TahoeFileStore.shared.createFolder(in: TahoeFileStore.shared.root) }
        catch { workspace.error = error.localizedDescription }
    }
}


/// Menu ownership only invalidates the shortcut surface. This also restores
/// commands immediately after a menu closes without invalidating live pages.
private struct TahoeDesktopCommandSurface: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var menus = TahoeMenuCoordinator.shared
    @ObservedObject private var dialogs = TahoeDialogCoordinator.shared
    @ObservedObject private var modalRegistry = TahoeModalRegistry.shared
    private var commandsAvailable: Bool {
        let page = workspace.state.activeID.flatMap { workspace.browsers[$0] }.flatMap { session in session.tabs.first { $0.id == session.selectedID } }?.activePage
        return !workspace.showManagement && workspace.overlay == nil && menus.request == nil && menus.bar == nil && dialogs.dialog == nil && modalRegistry.owners.isEmpty && page?.dialog == nil && page?.authentication == nil
    }

    @ViewBuilder var body: some View {
        if commandsAvailable { shortcuts.hidden() }
        else if !workspace.showManagement && dialogs.dialog == nil && modalRegistry.owners.isEmpty && workspace.overlay != nil {
            Button(TahoeStrings.ui("Dismiss Overlay")) { workspace.overlay = nil }.keyboardShortcut(.escape, modifiers: []).hidden()
        }
    }
    private var shortcuts: some View {
        Group {
            Button(TahoeStrings.ui("New Browser Window")) { workspace.openBrowser() }.keyboardShortcut("n", modifiers: .command)
            Button(TahoeStrings.ui("Next Tab")) { workspace.nextTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button(TahoeStrings.ui("Previous Tab")) { workspace.nextTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button(TahoeStrings.ui("New Tab")) { workspace.newTab() }.keyboardShortcut("t", modifiers: .command)
            Button(TahoeStrings.ui("Close")) { workspace.closeActive() }.keyboardShortcut("w", modifiers: .command)
            Button(TahoeStrings.ui("Close Window")) { if let id = workspace.state.activeID { workspace.close(id) } }.keyboardShortcut("w", modifiers: [.command, .shift])
            Button(TahoeStrings.ui("Open Location")) { workspace.focusAddress() }.keyboardShortcut("l", modifiers: .command)
            Button(TahoeStrings.ui("Find on Page")) { workspace.activeBrowserPage?.findOnPage() }.keyboardShortcut("f", modifiers: .command).disabled(workspace.activeBrowserPage?.webView == nil)
            Button(TahoeStrings.ui("Close Chat")) { if let chats = workspace.activeBrowserPage?.chatOwner { chats.close(chats.state.focused) } }.keyboardShortcut("w", modifiers: [.command, .option]).disabled(workspace.activeBrowserPage?.chatOwner == nil)
            TahoeReopenShortcut()
            Button(TahoeStrings.ui("Spotlight")) { workspace.present(.spotlight) }.keyboardShortcut(" ", modifiers: .command)
            Button(TahoeStrings.ui("Commands")) { workspace.openTools("Actions") }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button(TahoeStrings.ui("Minimise Window")) { if let id = workspace.state.activeID { workspace.minimize(id) } }.keyboardShortcut("m", modifiers: .command)
            Button(TahoeStrings.ui("Mission Control")) { workspace.present(.overview) }.keyboardShortcut(.upArrow, modifiers: [.control])
            Button(TahoeStrings.ui("Window Overview Shortcut")) { workspace.present(.overview) }.keyboardShortcut("m", modifiers: [.command, .shift])
            Button(TahoeStrings.ui("Cycle Windows")) { workspace.state.cycleFocus() }.keyboardShortcut("`", modifiers: .command)
            Button(TahoeStrings.ui("Dismiss")) { if let dialog = dialogs.dialog { dialogs.dialog = nil; dialog.reject() } else if menus.request != nil { menus.dismiss() } else { workspace.escape() } }.keyboardShortcut(.escape, modifiers: [])
            Button(TahoeStrings.ui("Fullscreen")) { if let id = workspace.state.activeID { workspace.state.toggleFullscreen(id) } }.keyboardShortcut("f", modifiers: [.control, .command])
            Button(TahoeStrings.ui("Save Workspace")) { workspace.saveWorkspace() }.keyboardShortcut("s", modifiers: .command)
        }
    }
}

/// Menu hover changes stay in the chrome, away from every live app surface.
private struct TahoeDesktopChrome: View {
    @ObservedObject var workspace: TahoeWorkspace
    @Binding var performanceTarget: UUID?
    @ObservedObject private var menus = TahoeMenuCoordinator.shared
    @ObservedObject private var fullscreenChrome = TahoeFullscreenChrome.shared
    @ObservedObject private var display = TahoeDisplayMetrics.shared
    var body: some View {
        ZStack(alignment: .topLeading) {
            if workspace.state.fullscreenID == nil || workspace.overlay == .overview {
                VStack(spacing: 0) {
                    if workspace.overlay != .overview {
                        TahoeMenuBar(workspace: workspace).accessibilityHidden(workspace.overlay != nil && workspace.overlay != .launchpad)
                    } else { Color.clear.frame(height: TahoeDesign.menuBarHeight).allowsHitTesting(false) }
                    Spacer()
                    TahoeDock(workspace: workspace).padding(.bottom, display.current.innerDisplay ? 0 : 4)
                        .accessibilityHidden((workspace.overlay != nil && workspace.overlay != .launchpad && workspace.overlay != .overview) || menus.session.isOpen)
                }.zIndex(menus.bar != nil ? 3200 : workspace.overlay == .launchpad || workspace.overlay == .overview ? 2200 : 1000)
            } else { TahoeFullscreenReveal(workspace: workspace).zIndex(menus.bar != nil ? 3200 : 1000) }
            if workspace.overlay != nil { TahoeDesktopOverlay(workspace: workspace).zIndex(2000) }
            if menus.session.isOpen {
                TahoeMenuPopup(workspace: workspace, performanceTarget: $performanceTarget)
                    .transition(.identity).zIndex(3000)
            }
        }
        .onChange(of: menus.session.isOpen || workspace.overlay != nil, initial: true) { _, open in fullscreenChrome.menuOpen = open }
    }
}

/// Only this accessibility wrapper observes menu ownership, not window content.
struct TahoeMenuAccessibility: ViewModifier {
    @ObservedObject private var menus = TahoeMenuCoordinator.shared
    var hidden: Bool
    func body(content: Content) -> some View { content.accessibilityHidden(hidden || menus.session.isOpen) }
}
