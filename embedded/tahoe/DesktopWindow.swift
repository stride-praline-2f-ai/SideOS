import SwiftUI

struct TahoeDesktopWindow<Content: View>: View {
    let window: TahoeWindow
    @ObservedObject var workspace: TahoeWorkspace
    @ViewBuilder let content: () -> Content
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var motion = TahoeWindowMotion.shared
    // Hold the controller without subscribing the content tree to pointer updates.
    @State private var interaction = TahoeWindowInteraction()
    @State private var browserAddressFrame: CGRect = .zero
    @ObservedObject private var fullscreenChrome = TahoeFullscreenChrome.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var fullscreen: Bool { workspace.state.fullscreenID == window.id }
    private var visible: Bool { workspace.state.isVisible(window) }
    private var active: Bool { workspace.state.activeID == window.id }
    private var hosted: Bool { window.isWebApp || window.kind == .guest || window.kind == .installer || window.kind == .livecontainer }
    private var integrated: Bool { window.isWebApp || window.kind != .browser && window.kind != .settings && (window.kind != .guest || preferences.value.guestControlsOverlay) }
    private var integratedHeight: CGFloat { TahoeDesign.titleHeight }
    private var chromeHeight: CGFloat { window.kind == .browser ? TahoeDesign.navigationHeight : window.kind == .settings ? 48 : TahoeDesign.titleHeight }
    private var minimizeTarget: CGPoint { workspace.minimizeTargets[window.id] ?? CGPoint(x: workspace.state.canvas.width / 2, y: workspace.state.canvas.height - 40) }

    var body: some View {
        placedWindow
        .accessibilityElement(children: .contain).accessibilityLabel("\(window.title) window")
        .accessibilityAction(named: "Minimize Window") { workspace.minimize(window.id) }
        .accessibilityAction(named: "Close Window") { workspace.close(window.id) }
        .accessibilityAction(named: "Fill or Restore Window") { workspace.state.toggleMaximize(window.id) }
        .accessibilityAction(named: "Move Window Left") { workspace.state.move(window.id, from: workspace.state.displayFrame(window), translation: CGSize(width: -40, height: 0)) }
        .accessibilityAction(named: "Move Window Right") { workspace.state.move(window.id, from: workspace.state.displayFrame(window), translation: CGSize(width: 40, height: 0)) }
        .accessibilityAction(named: "Move Window Up") { workspace.state.move(window.id, from: workspace.state.displayFrame(window), translation: CGSize(width: 0, height: -40)) }
        .accessibilityAction(named: "Move Window Down") { workspace.state.move(window.id, from: workspace.state.displayFrame(window), translation: CGSize(width: 0, height: 40)) }
        .accessibilityAction(named: "Make Window Wider") { workspace.state.resize(window.id, from: workspace.state.displayFrame(window), edge: .right, translation: CGSize(width: 40, height: 0)) }
        .accessibilityAction(named: "Make Window Narrower") { workspace.state.resize(window.id, from: workspace.state.displayFrame(window), edge: .right, translation: CGSize(width: -40, height: 0)) }
        .modifier(TahoeMenuAccessibility(hidden: !visible || workspace.overlay != nil))
    }


    private var placedWindow: some View {
        windowSurface
        .coordinateSpace(name: "tahoe-window-\(window.id)")
        .modifier(TahoeWindowPlacement(interaction: interaction, frame: workspace.state.displayFrame(window),
            minimized: window.minimized, target: minimizeTarget, layout: window.layout, fullscreen: fullscreen))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
        .opacity(visible && (window.onWirelessDisplay == true || workspace.overlay != .overview) && motion.flights[window.id] == nil ? 1 : 0)
        .allowsHitTesting(visible && workspace.overlay != .overview)
        .simultaneousGesture(TapGesture().onEnded {
            // Remote apps focus at native touch-down. A second focus on
            // touch-up could undo a window switch triggered by the app.
            guard window.kind != .guest && window.kind != .installer else { return }
            if workspace.state.activeID != window.id { workspace.state.focusVisible(window.id) }
        })
        .onPreferenceChange(TahoeBrowserAddressFrameKey.self) { if browserAddressFrame != $0 { browserAddressFrame = $0 } }
        .onChange(of: window.minimized) { _, minimized in motion.transition(window.id, minimized: minimized) }
        .onDisappear { motion.cancel(window.id) }
        .onChange(of: workspace.overlay) { _, overlay in if overlay != nil { interaction.reset(); workspace.snapPreview = nil } }
        .onChange(of: fullscreen) { _, _ in interaction.reset() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { interaction.reset(); workspace.snapPreview = nil } }
        .onChange(of: visible) { _, shown in if !shown { interaction.reset(); workspace.snapPreview = nil } }
        .onChange(of: window.frame) { _, _ in motion.cancel(window.id) }
    }

    private var windowSurface: some View {
        Group {
            if window.kind == .browser {
                // Safari-style under-scroll: the live WKWebView fills the window
                // beneath both chrome rows. Its scroll inset protects the
                // initially visible page while allowing scrolled content to
                // blur through the navigation and tab materials.
                ZStack(alignment: .top) {
                    windowContents
                    if !window.isWebApp { titleBar.frame(height: chromeHeight)
                        .background { if visible { TahoeWindowChrome(active: active, browser: true) } }
                        .offset(y: fullscreen && fullscreenChrome.revealed ? TahoeDesign.menuBarHeight : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: fullscreenChrome.revealed)
                        .zIndex(2) }
                }
            } else {
                VStack(spacing: 0) {
                    if !integrated && !fullscreen {
                        titleBar.frame(height: chromeHeight)
                            .background { if visible { TahoeWindowChrome(active: active) } }
                            .zIndex(2)
                    }
                    windowContents
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if integrated && !fullscreen {
                titleBar.frame(maxWidth: hosted ? .infinity : TahoeDesign.trafficInset, alignment: .leading).frame(height: integratedHeight)
                    .background { if hosted { TahoeWindowChrome(active: active) } }
            }
            if fullscreen && fullscreenChrome.revealed && TahoeChromePolicy.showsFullscreenTrafficLights(kind: window.kind, webApp: window.isWebApp) {
                titleBar.frame(height: integratedHeight).background { TahoeWindowChrome(active: true) }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            fullscreenChrome.pointer(location: CGPoint(x: location.x, y: location.y + TahoeDesign.menuBarHeight), owner: "traffic")
                        case .ended: fullscreenChrome.pointer(location: nil, owner: "traffic")
                        }
                    }
                    .offset(y: TahoeDesign.menuBarHeight)
                    .onDisappear { fullscreenChrome.pointer(location: nil, owner: "traffic") }
            }
        }
        // Clip the integrated hosted title bar too: an overlay added after
        // clipping would paint square corners over the rounded window.
        .clipShape(RoundedRectangle(cornerRadius: fullscreen ? 0 : TahoeDesign.windowRadius))
        // The toolbar is only 53 pt high. Present suggestions in the full
        // browser window so rows below it receive native hit testing.
        .overlay(alignment: .topLeading) {
            if window.kind == .browser, !window.isWebApp, active, visible,
               browserAddressFrame.width > 0,
               let session = workspace.browsers[window.id],
               let tab = session.tabs.first(where: { $0.id == session.selectedID }) {
                GeometryReader { geometry in
                    let panelWidth = min(browserAddressFrame.width, max(0, geometry.size.width - 24))
                    let panelX = max(12, min(browserAddressFrame.minX, geometry.size.width - panelWidth - 12))
                    TahoeBrowserSuggestionsOverlay(tab: tab)
                        .frame(width: panelWidth)
                        .offset(x: panelX, y: browserAddressFrame.maxY + 6)
                        .zIndex(20)
                }
            }
        }
        .overlay {
            // Fullscreen has no window frame. Hosted scenes also need only
            // one subtle edge, not a second bright border over their content.
            if !fullscreen {
                RoundedRectangle(cornerRadius: TahoeDesign.windowRadius)
                    .strokeBorder(Color.primary.opacity(active ? 0.20 : 0.10), lineWidth: 0.5)
                    .overlay {
                        if !hosted {
                            RoundedRectangle(cornerRadius: TahoeDesign.windowRadius).inset(by: 0.5)
                                .strokeBorder(.white.opacity(active ? 0.15 : 0.06), lineWidth: 0.5)
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
        // Resize grips stay above the header and remote UIKit content.
        .overlay { if !fullscreen { resizeHandles } }
        .shadow(color: .black.opacity(visible && !fullscreen ? active ? 0.30 : 0.14 : 0), radius: active ? 24 : 12, y: active ? 12 : 5)
    }

    private var windowContents: some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .padding(.top, (window.kind == .guest || window.kind == .installer || window.kind == .livecontainer) && integrated && !fullscreen ? integratedHeight : 0)
            .environment(\.tahoeTrafficInset, integrated && !fullscreen ? TahoeDesign.trafficInset : 0)
            .environment(\.tahoeTitlebarActions, fullscreen ? nil : TahoeTitlebarActions(drag: windowDrag, zoom: { workspace.state.toggleMaximize(window.id) }))
            .environment(\.tahoeWindowActive, active).environment(\.tahoeWindowVisible, visible)
            .background { if window.kind != .browser { TahoeDesign.window } }
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            if !fullscreen || fullscreenChrome.revealed { HStack(spacing: 0) {
                trafficLight(Color(red: 1, green: 95 / 255, blue: 87 / 255), symbol: "xmark", label: "Close \(window.title)") { workspace.close(window.id) }
                trafficLight(Color(red: 254 / 255, green: 188 / 255, blue: 46 / 255), symbol: "minus", label: "Minimise \(window.title)") { workspace.minimize(window.id) }
                trafficLight(Color(red: 40 / 255, green: 200 / 255, blue: 64 / 255), symbol: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: fullscreen ? "Exit Fullscreen" : "Fullscreen \(window.title)") { workspace.state.toggleFullscreen(window.id) }
            }.padding(.leading, 14).padding(.trailing, 14) }
            if window.kind == .browser, !window.isWebApp, let session = workspace.browsers[window.id] {
                TahoeBrowserToolbar(session: session, windowID: window.id)
            } else if window.kind == .settings {
                TahoeSettingsToolbar(workspace: workspace)
            } else if integrated && hosted {
                ZStack {
                    Color.clear
                    if window.kind == .installer {
                        Text("SideInstaller by FrizzleM").font(.system(size: 13, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.8).allowsHitTesting(false)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if !fullscreen { workspace.state.toggleMaximize(window.id) } }
                    .gesture(windowDrag)
                    .simultaneousGesture(TapGesture().onEnded {
                        if workspace.state.activeID != window.id { workspace.state.focusVisible(window.id) }
                    })
                    .accessibilityLabel("Move \(window.title) window")
                    .accessibilityIdentifier("window-header-\(window.id)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Fill or Restore Window") { if !fullscreen { workspace.state.toggleMaximize(window.id) } }
            } else if !integrated {
                Text(window.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(active ? .primary : .secondary)
                    .accessibilityIdentifier("title-\(window.kind.rawValue)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    .onTapGesture(count: 2) { if !fullscreen { workspace.state.toggleMaximize(window.id) } }.gesture(windowDrag)
            }

        }.frame(maxHeight: .infinity).background {
            Color.clear.contentShape(Rectangle()).gesture(windowDrag)
                .onTapGesture(count: 2) { if !fullscreen { workspace.state.toggleMaximize(window.id) } }
        }
    }

    private var windowDrag: AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(coordinateSpace: .named("tahoe-desktop"))
                    .onChanged { value in
                        guard !fullscreen, workspace.overlay == nil, visible else { return }
                        if !interaction.active {
                            motion.cancel(window.id)
                            let displayed = workspace.state.displayFrame(window)
                            let start = window.layout == .floating ? displayed : TahoeWindowGeometry.restored(window.frame,
                                displayed: displayed, pointer: value.startLocation, titleHeight: chromeHeight)
                            interaction.begin(start, restored: window.layout != .floating)
                            if workspace.state.activeID != window.id { workspace.state.focus(window.id) }
                        }
                        interaction.move(value.translation, area: workspace.state.desktopArea)
                        let area = workspace.state.workArea
                        let preview: TahoeWindowLayout? = value.location.x < area.minX + 16 ? .left : value.location.x > area.maxX - 16 ? .right : value.location.y < area.minY + 12 ? .maximized : nil
                        if workspace.snapPreview != preview { workspace.snapPreview = preview }
                    }
                    .onEnded { value in
                        guard !fullscreen, workspace.overlay == nil, let start = interaction.start else {
                            interaction.reset(); workspace.snapPreview = nil; return
                        }
                        withTransaction(Transaction(animation: nil)) {
                            workspace.state.move(window.id, from: start, translation: value.translation)
                            interaction.reset()
                            workspace.snapPreview = nil
                        }
                        let area = workspace.state.workArea
                        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.9)) {
                            if value.location.x < area.minX + 16 { workspace.state.setLayout(.left, for: window.id) }
                            else if value.location.x > area.maxX - 16 { workspace.state.setLayout(.right, for: window.id) }
                            else if value.location.y < area.minY + 12 { workspace.state.setLayout(.maximized, for: window.id) }
                        }
                    })
    }

    private func trafficLight(_ color: Color, symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(active && enabled ? color : Color.primary.opacity(0.16)).frame(width: 12, height: 12)
                .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                .overlay { Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(.black.opacity(0.6)) }
                .frame(width: 40, height: 44).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle()).disabled(!enabled).accessibilityLabel(label).help(label)
            .contextMenu {
                if symbol == "arrow.up.left.and.arrow.down.right" {
                    Button(TahoeStrings.ui("Enter Fullscreen")) { workspace.state.toggleFullscreen(window.id) }
                    Button(TahoeStrings.ui("Fill Desktop")) { workspace.state.setLayout(.maximized, for: window.id) }
                    Button(TahoeStrings.ui("Tile Left")) { workspace.state.setLayout(.left, for: window.id) }
                    Button(TahoeStrings.ui("Tile Right")) { workspace.state.setLayout(.right, for: window.id) }
                    Button(TahoeStrings.ui("Restore Size")) { workspace.state.setLayout(.floating, for: window.id) }
                }
            }
    }

    private var resizeHandles: some View {
        GeometryReader { geometry in
            ForEach(Array(TahoeResizeEdge.allCases.enumerated()), id: \.offset) { _, edge in
                let box = handleFrame(edge, size: geometry.size)
                Color.clear.frame(width: box.width, height: box.height).contentShape(Rectangle())
                    .overlay(alignment: edge == .bottomLeft ? .bottomLeading : .bottomTrailing) {
                        if edge == .bottomRight || edge == .bottomLeft {
                            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(edge == .bottomRight ? -45 : 45)).foregroundStyle(.secondary.opacity(0.5))
                                .padding(6).allowsHitTesting(false)
                        }
                    }
                    .position(x: box.midX, y: box.midY)
                    .highPriorityGesture(DragGesture(coordinateSpace: .named("tahoe-desktop"))
                        .onChanged { value in
                            guard !fullscreen, workspace.overlay == nil, visible else { return }
                            if !interaction.active {
                                motion.cancel(window.id)
                                interaction.begin(workspace.state.displayFrame(window))
                                if workspace.state.activeID != window.id { workspace.state.focus(window.id) }
                            }
                            interaction.resize(value.translation, edge: edge, area: workspace.state.desktopArea)
                        }.onEnded { value in
                            withTransaction(Transaction(animation: nil)) {
                                if let start = interaction.start, !fullscreen, workspace.overlay == nil {
                                    workspace.state.resize(window.id, from: start, edge: edge, translation: value.translation)
                                }
                                interaction.reset()
                            }
                        })
                    .accessibilityLabel("Resize \(window.title)")
                    .accessibilityIdentifier("window-resize-\(String(describing: edge))-\(window.id)")
            }
        }
    }

    private func handleFrame(_ edge: TahoeResizeEdge, size: CGSize) -> CGRect {
        let grip: CGFloat = 16
        switch edge {
        case .top: return CGRect(x: grip, y: 0, width: max(0, size.width - 2 * grip), height: 8)
        case .bottom: return CGRect(x: grip, y: size.height - 8, width: max(0, size.width - 2 * grip), height: 8)
        case .left: return CGRect(x: 0, y: grip, width: 8, height: max(0, size.height - 2 * grip))
        case .right: return CGRect(x: size.width - 8, y: grip, width: 8, height: max(0, size.height - 2 * grip))
        case .topLeft: return CGRect(x: 0, y: 0, width: grip, height: grip)
        case .topRight: return CGRect(x: size.width - grip, y: 0, width: grip, height: grip)
        case .bottomLeft: return CGRect(x: 0, y: size.height - 44, width: 44, height: 44)
        case .bottomRight: return CGRect(x: size.width - 44, y: size.height - 44, width: 44, height: 44)
        }
    }
}


