import SwiftUI
import WebKit
import Translation

struct TahoeBrowserNavigation: View {
    @ObservedObject var tab: TahoeBrowserTab
    @ObservedObject var session: TahoeBrowserSession
    let windowID: UUID
    @EnvironmentObject private var workspace: TahoeWorkspace
    @FocusState private var addressFocused: Bool
    @ObservedObject var suggestions: TahoeGoogleSuggestions
    @State private var draft = ""
    @State private var bookmarksShown = false
    @State private var tabsShown = false
    @State private var profileShown = false
    @ObservedObject private var fullscreenChrome = TahoeFullscreenChrome.shared
    @State private var translationShown = false
    @State private var translationText = ""
    @State private var chromeOwner = UUID()
    @State private var shareFrame = CGRect.zero
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var foreground: Bool { workspace.state.activeID == windowID && workspace.state.windows.contains { $0.id == windowID && workspace.state.isVisible($0) } }
    private var displayedAddress: String { tab.currentURL?.host ?? tab.address }
    // The traffic lights are owned by DesktopWindow, outside this toolbar's
    // layout. Their 92pt footprint would otherwise push the URL pill 46pt right.
    private var visibleTrafficWidth: CGFloat {
        let fullscreen = workspace.state.fullscreenID == windowID
        return fullscreen && !fullscreenChrome.revealed ? 0 : TahoeDesign.trafficInset
    }
    private var narrowToolbar: Bool {
        let width = workspace.state.windows.first(where: { $0.id == windowID }).map { workspace.state.displayFrame($0).width } ?? workspace.state.canvas.width
        return width - visibleTrafficWidth < 560
    }
    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 1120 {
                    // Center the address field on the *window*, not between
                    // asymmetrical left and right groups.
                    ZStack {
                        HStack(spacing: 0) {
                            leftControls(showProfile: true)
                            Spacer(minLength: 8)
                            rightControls
                        }
                        address.frame(width: 565)
                            .offset(x: -visibleTrafficWidth / 2)
                    }
                } else if geometry.size.width < 560 {
                    HStack(spacing: 6) {
                        Button { tab.webView?.goBack() } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }.disabled(!tab.canGoBack).accessibilityLabel("Back").buttonStyle(TahoePressStyle())
                        address.frame(maxWidth: .infinity)
                        Button { session.add() } label: {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                        }.accessibilityLabel("New tab").buttonStyle(TahoePressStyle())
                        Menu {
                            Button("Forward", systemImage: "chevron.right") { tab.webView?.goForward() }.disabled(!tab.canGoForward)
                            Button("Show All Tabs", systemImage: "square.on.square") { tabsShown = true }
                            Button("Bookmarks", systemImage: "book") { bookmarksShown = true }
                            Button("Browsing Profile", systemImage: "person.crop.circle") { profileShown = true }
                            Button("Reload", systemImage: "arrow.clockwise") { tab.webView?.reload() }
                            Button("Share Website", systemImage: "square.and.arrow.up") {
                                if let url = tab.currentURL { TahoeShare.present([url], window: workspace.hostWindow, sourceRect: shareFrame) }
                            }.disabled(tab.currentURL == nil)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Capsule())
                        }.buttonStyle(TahoePressStyle(surface: true, radius: 100)).accessibilityLabel("More browser controls")
                    }
                } else {
                    HStack(spacing: 8) {
                        leftControls(showProfile: geometry.size.width >= 850)
                        address.frame(maxWidth: .infinity)
                        rightControls
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: TahoeDesign.navigationHeight)
            .frame(maxWidth: .infinity)
        }
        .frame(height: TahoeDesign.navigationHeight)
        .tahoeGlassGroup()
        .popover(isPresented: Binding(get: { narrowToolbar && bookmarksShown }, set: { if narrowToolbar { bookmarksShown = $0 } })) {
            bookmarksPanel.presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: Binding(get: { narrowToolbar && tabsShown }, set: { if narrowToolbar { tabsShown = $0 } })) {
            tabsPanel.presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: Binding(get: { narrowToolbar && profileShown }, set: { if narrowToolbar { profileShown = $0 } })) {
            profilePanel
        }
        .onAppear { draft = tab.address }
        .onChange(of: addressFocused) { _, focused in
            TahoeFullscreenChrome.shared.setEditing(chromeOwner, active: focused)
            tab.suggestionsFocused = focused
            if focused {
                draft = tab.address
                suggestions.update(draft, privateBrowsing: session.profile == .privateBrowsing)
                DispatchQueue.main.async {
                    let responder = TahoeResponderBox()
                    UIApplication.shared.sendAction(#selector(UIResponder.tahoeCaptureResponder(_:)), to: nil, from: responder, for: nil)
                    (responder.value as? UITextField)?.selectAll(nil)
                }
            } else {
                suggestions.dismiss()
            }
        }
        .onChange(of: draft) { _, newValue in
            if addressFocused { suggestions.update(newValue, privateBrowsing: session.profile == .privateBrowsing) }
        }
        .onChange(of: session.profile) { _, _ in
            tab.suggestionsFocused = false
            suggestions.dismiss()
        }
        .onChange(of: tab.suggestionsFocused) { _, focused in
            if !focused && addressFocused { addressFocused = false }
        }
        .onChange(of: bookmarksShown || tabsShown || profileShown || translationShown) { _, open in
            TahoeFullscreenChrome.shared.setPopover(chromeOwner, open: open)
            if open { addressFocused = false; suggestions.dismiss() }
        }
        .onDisappear {
            TahoeFullscreenChrome.shared.setEditing(chromeOwner, active: false)
            TahoeFullscreenChrome.shared.setPopover(chromeOwner, open: false)
            suggestions.dismiss()
            tab.suggestionsFocused = false
        }
        .onChange(of: foreground) { _, active in
            if !active { addressFocused = false; tab.suggestionsFocused = false; suggestions.dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tahoeFocusAddress)) { notification in
            if notification.object as? UUID == windowID { addressFocused = true }
        }
    }

    private var profilePanel: some View {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(TahoeStrings.ui("Browsing Profiles")).font(.system(size: 14, weight: .semibold))
                        ForEach(TahoeBrowserProfile.allCases) { candidate in
                            Button {
                                profileShown = false
                                addressFocused = false
                                session.selectProfile(candidate)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: candidate.symbol).frame(width: 19)
                                    Text(candidate.title).frame(maxWidth: .infinity, alignment: .leading)
                                    if session.profile == candidate {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .font(.system(size: 13))
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TahoePressStyle())
                            .accessibilityAddTraits(session.profile == candidate ? [.isSelected] : [])
                        }
                        Divider()
                        Text(TahoeStrings.ui("Personal and Work keep separate site data. Private browsing uses an in-memory data store; private tabs are never restored."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(16).frame(width: 280).presentationCompactAdaptation(.popover)
    }

    private func leftControls(showProfile: Bool) -> some View {
        HStack(spacing: 8) {
            Button { bookmarksShown.toggle() } label: {
                Image(systemName: "sidebar.left").font(.system(size: 17, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Capsule())
            }
            .buttonStyle(TahoeBrowserButtonStyle())
            .accessibilityLabel("Bookmarks sidebar")
            .accessibilityIdentifier("browser-sidebar")
            .popover(isPresented: $bookmarksShown) { bookmarksPanel.presentationCompactAdaptation(.popover) }

            if showProfile {
                Button { profileShown.toggle() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: session.profile.symbol).font(.system(size: 14, weight: .medium))
                        Text(session.profile.title).font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .frame(width: 112, height: 44).contentShape(Capsule())
                }
                .buttonStyle(TahoeBrowserButtonStyle())
                .accessibilityIdentifier("browser-profile")
                .accessibilityLabel("Browsing profile: \(session.profile.title)")
                .popover(isPresented: $profileShown) { profilePanel }
            }
            HStack(spacing: 0) {
                Button { tab.webView?.goBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .regular))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(!tab.canGoBack)
                .accessibilityLabel("Back")
                Rectangle().fill(.white.opacity(0.20)).frame(width: 0.5, height: 19)
                    .accessibilityHidden(true)
                Button { tab.webView?.goForward() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .regular))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(!tab.canGoForward)
                .accessibilityLabel("Forward")
            }
            .buttonStyle(TahoePressStyle())
            .tahoeBrowserPill(interactive: true)
            .accessibilityIdentifier("browser-history-controls")
        }
        .foregroundStyle(.primary.opacity(0.87))
    }

    private var rightControls: some View {
        HStack(spacing: 1) {
            Button {
                if let url = tab.currentURL { TahoeShare.present([url], window: workspace.hostWindow, sourceRect: shareFrame) }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(tab.currentURL == nil)
            .background { GeometryReader { geometry in Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in shareFrame = frame } } }
            .accessibilityLabel("Share website")
            Button { session.add() } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("New tab")
            Button { tabsShown.toggle() } label: {
                Image(systemName: "square.on.square").font(.system(size: 18, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Show all tabs")
            .popover(isPresented: $tabsShown) { tabsPanel.presentationCompactAdaptation(.popover) }
        }
        .buttonStyle(TahoePressStyle())
        .foregroundStyle(.primary.opacity(0.9))
        .tahoeBrowserPill(interactive: true)
        .accessibilityIdentifier("browser-actions")
    }

    private func navigateFromAddress(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        suggestions.dismiss()
        tab.suggestionsFocused = false
        draft = value
        tab.address = value
        tab.navigate()
        addressFocused = false
    }

    @ViewBuilder
    private var address: some View {
        if #available(iOS 18.0, *) {
            addressContents.translationPresentation(isPresented: $translationShown, text: translationText)
        } else {
            addressContents
        }
    }

    private var addressContents: some View {
        ZStack {
            TextField(TahoeStrings.ui("Search or enter website"), text: Binding(
                get: { addressFocused ? draft : displayedAddress },
                set: { draft = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .multilineTextAlignment(addressFocused ? .leading : .center)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.webSearch)
            .focused($addressFocused)
            .onSubmit {
                navigateFromAddress(suggestions.selectedRow == nil ? draft : suggestions.selectedSuggestion)
            }
            .onKeyPress(.downArrow) {
                guard suggestions.shouldPresent else { return .ignored }
                suggestions.selectNext(1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard suggestions.shouldPresent else { return .ignored }
                suggestions.selectNext(-1)
                return .handled
            }
            .onKeyPress(.escape) {
                guard suggestions.shouldPresent else { return .ignored }
                addressFocused = false
                suggestions.dismiss()
                return .handled
            }
            .padding(.horizontal, narrowToolbar ? 50 : 94)
            .accessibilityIdentifier("browser-address")

            HStack(spacing: 1) {
                if !addressFocused {
                    TahoePopupButton(entries: browserCommands) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 13, weight: .regular))
                            .frame(width: 40, height: 44).contentShape(Rectangle())
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Browser options")
                } else {
                    Color.clear.frame(width: 40, height: 44)
                }
                Spacer(minLength: 0)
                if !narrowToolbar {
                Button(action: translatePageExcerpt) {
                    Image(systemName: "translate")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 40, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(TahoePressStyle())
                .disabled(tab.webView == nil)
                .accessibilityLabel("Translate page text")
                }
                Button {
                    if tab.loading {
                        tab.webView?.stopLoading()
                        tab.loading = false
                    } else if tab.webView == nil {
                        tab.navigate()
                    } else {
                        tab.webView?.reload()
                    }
                } label: {
                    Image(systemName: tab.loading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 40, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(TahoePressStyle())
                .accessibilityLabel(tab.loading ? "Stop loading" : "Reload")
            }
            .padding(.horizontal, 7)
            .foregroundStyle(.primary.opacity(0.77))
        }
        .frame(maxWidth: 565)
        .frame(height: 44)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: TahoeBrowserAddressFrameKey.self,
                    value: geometry.frame(in: .named("tahoe-window-\(windowID)")))
            }
        }
        .tahoeBrowserPill(selected: addressFocused)
        .overlay {
            Capsule().strokeBorder(addressFocused ? TahoeDesign.accent.opacity(0.75) : .clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: addressFocused)
    }

    private func translatePageExcerpt() {
        guard #available(iOS 18.0, *), let webView = tab.webView else { return }
        // Apple's Translation presentation is text-based, unlike Safari's
        // privileged full-page translator. Never pretend to rewrite the page.
        webView.evaluateJavaScript("document.body ? document.body.innerText.slice(0, 4000) : ''") { value, _ in
            DispatchQueue.main.async {
                let extracted = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !extracted.isEmpty else { return }
                translationText = extracted
                translationShown = true
            }
        }
    }

    private var bookmarksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TahoeStrings.ui("Bookmarks")).font(.headline)
            if workspace.bookmarks.isEmpty { Text(TahoeStrings.ui("Bookmark a website to find it here.")).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(workspace.bookmarks) { link in
                        Button { tab.address = link.url.absoluteString; tab.navigate(); bookmarksShown = false } label: {
                            Label(link.title, systemImage: "bookmark").lineLimit(1)
                        }.buttonStyle(TahoePressStyle())
                    }
                }
            }.frame(maxHeight: 300)
            Button(TahoeStrings.ui("Add Current Website")) { if let url = tab.currentURL { workspace.addBookmark(title: tab.title, url: url) } }
                .disabled(tab.currentURL == nil)
        }.padding(20).frame(width: 300)
    }
    private var tabsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TahoeStrings.ui("Open Tabs")).font(.headline)
            if !session.groupNames.isEmpty {
                Picker("Tab Group", selection: Binding(get: { session.selectedGroup ?? "" }, set: { session.selectGroup($0.isEmpty ? nil : $0) })) {
                    Text("All Tabs").tag("")
                    ForEach(session.groupNames, id: \.self) { Text($0).tag($0) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.visibleTabs) { candidate in
                        HStack {
                            Button { session.selectedID = candidate.id; tabsShown = false } label: {
                                TahoeTabLabel(tab: candidate).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(TahoePressStyle())
                            Button { session.close(candidate.id) } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close tab")
                        }
                    }
                }
            }.frame(maxHeight: 300)
        }.padding(20).frame(width: 340)
    }
    private var browserCommands: [TahoeMenuEntry] {
        var commands: [TahoeMenuEntry] = [
            TahoeMenuEntry(title: "New Tab", shortcut: "⌘T", symbol: "plus", action: { session.add() }),
            TahoeMenuEntry(title: "Forward", symbol: "chevron.right", enabled: tab.canGoForward, action: { tab.webView?.goForward() }),
            TahoeMenuEntry(title: "Show All Tabs", symbol: "square.on.square", action: { tabsShown = true }),
            TahoeMenuEntry(title: "Bookmarks Sidebar", symbol: "sidebar.left", action: { bookmarksShown = true }),
            TahoeMenuEntry(title: "Browsing Profile", symbol: session.profile.symbol,
                children: TahoeBrowserProfile.allCases.map { profile in
                    TahoeMenuEntry(title: profile.title, checked: session.profile == profile, action: { session.selectProfile(profile) })
                }),
            TahoeMenuEntry(title: "Translate Page Text", symbol: "translate", enabled: tab.webView != nil, action: translatePageExcerpt),
            .line(31),
            TahoeMenuEntry(title: TahoeStrings.ui("Find on Page"), shortcut: "⌘F", symbol: "magnifyingglass", action: { tab.findOnPage() }),
            TahoeMenuEntry(title: TahoeStrings.ui("Open Tabs…"), symbol: "rectangle.on.rectangle", action: { workspace.showLibrary() }),
            TahoeMenuEntry(title: TahoeStrings.ui("History and Recently Closed…"), symbol: "clock", action: { workspace.showLibrary("history") }),
            TahoeMenuEntry(title: TahoeStrings.ui("Manage Bookmarks…"), symbol: "book", action: { workspace.showLibrary("bookmarks") }), .line(30)]
        commands.append(TahoeMenuEntry(title: TahoeStrings.ui("Website Information and Permissions…"), symbol: "lock.shield", action: { workspace.present(.siteInfo) }))
        commands += [TahoeMenuEntry(title: TahoeStrings.ui("Reader View"), symbol: "doc.text", action: { TahoeBrowserDocuments.reader(tab) }),
                     TahoeMenuEntry(title: TahoeStrings.ui("Save as PDF"), symbol: "doc.richtext", action: { TahoeBrowserDocuments.savePDF(tab) }),
                     TahoeMenuEntry(title: TahoeStrings.ui("Print…"), symbol: "printer", action: { TahoeBrowserDocuments.printPage(tab) }),
                     TahoeMenuEntry(title: tab.mediaSuspended ? "Resume Media" : "Pause Media", symbol: "playpause", enabled: tab.playingMedia || tab.mediaSuspended, action: { tab.toggleMedia() })]
        if let url = tab.currentURL {
            commands += [TahoeMenuEntry(title: TahoeStrings.ui("Add Bookmark"), symbol: "bookmark", action: { workspace.addBookmark(title: tab.title, url: url) }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Keep Web App in Dock"), symbol: "dock.rectangle", action: { workspace.pinWebApp(title: tab.title, url: url) }),
                         TahoeMenuEntry(title: TahoeStrings.ui("Share…"), symbol: "square.and.arrow.up", action: { TahoeShare.present([url], window: workspace.hostWindow, sourceRect: TahoeMenuCoordinator.shared.lastAnchor) }), .line(0)]
        }
        if tab.currentURL?.host == "chatgpt.com" {
            commands += [TahoeMenuEntry(title: TahoeStrings.ui("ChatGPT Chat Tabs"), checked: TahoePreferences.shared.value.chatTabsEnabled,
                action: { tab.setChatTabsEnabled(!TahoePreferences.shared.value.chatTabsEnabled) }),
                TahoeMenuEntry(title: TahoeStrings.ui("New Chat Tab"), symbol: "plus.bubble", enabled: tab.chatHost.chatWorkspace != nil, action: { tab.chatHost.chatWorkspace?.open(TahoeChatWorkspaceState.home) }), .line(7)]
            commands.append(TahoeMenuEntry(title: "Save Chat Workspace…", enabled: tab.profile != .privateBrowsing, action: { workspace.saveChatWorkspace(tab) }))
        }
        commands += [TahoeMenuEntry(title: TahoeStrings.ui("Zoom In"), action: { if let view = tab.webView { view.pageZoom = min(3, view.pageZoom + 0.1) } }),
                     TahoeMenuEntry(title: TahoeStrings.ui("Zoom Out"), action: { if let view = tab.webView { view.pageZoom = max(0.5, view.pageZoom - 0.1) } }),
                     TahoeMenuEntry(title: TahoeStrings.ui("Actual Size"), action: { tab.webView?.pageZoom = 1 }), .line(1),
                     TahoeMenuEntry(title: TahoeStrings.ui("Website Device Identity"), symbol: "desktopcomputer", children: TahoeWebsiteIdentity.allCases.map { mode in
                          TahoeMenuEntry(title: mode.title, checked: tab.identity == mode, action: { tab.setWebsiteIdentity(mode) })
                      }),
                     TahoeMenuEntry(title: TahoeStrings.ui("Downloads"), symbol: "arrow.down.circle", action: { workspace.open(.downloads) }),
                     TahoeMenuEntry(title: TahoeStrings.ui("Bookmarks"), enabled: !workspace.bookmarks.isEmpty, children: workspace.bookmarks.map { link in
                         TahoeMenuEntry(title: link.title, key: link.id.uuidString, action: { tab.address = link.url.absoluteString; tab.navigate() })
                     })]
        return commands
    }

}

