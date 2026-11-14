import SwiftUI
import WebKit
import ImageIO

func tahoeBrowserInterfaceStyle(_ appearance: String) -> UIUserInterfaceStyle {
    switch appearance {
    case "dark", "oled": return .dark
    case "light": return .light
    default: return .unspecified
    }
}

/// Browsing profile identity is attached to each WKWebView before it exists.
/// 'Private' uses a session-owned in-memory store, never the default cookies.
enum TahoeBrowserProfile: String, Codable, CaseIterable, Identifiable {
    case personal, work, privateBrowsing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .personal: return "Personal"
        case .work: return "Work"
        case .privateBrowsing: return "Private"
        }
    }
    var symbol: String {
        switch self {
        case .personal: return "person.crop.circle.fill"
        case .work: return "briefcase.fill"
        case .privateBrowsing: return "hand.raised.fill"
        }
    }
}

struct TahoeBrowserDialog: Identifiable {
    enum Kind { case alert, confirm, prompt }
    let id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var value = ""
    var completion: (String?) -> Void
}

@MainActor
final class TahoeBrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    weak var workspace: TahoeWorkspace?
    let id: UUID
    let profile: TahoeBrowserProfile
    private let websiteDataStore: WKWebsiteDataStore
    @Published var address = "https://www.apple.com"
    // Google suggestions are owned by the tab, never the global workspace.
    let suggestions = TahoeGoogleSuggestions()
    @Published var suggestionsFocused = false
    @Published var title = "New Tab"
    @Published var favicon: UIImage?
    @Published var loading = false
    @Published var pinned = false
    @Published var group: String?
    var restoredZoom: Double = 1
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    // Chrome has a solid, neutral top pocket until the document moves
    // underneath it. This is per-tab, so switching tabs restores each state.
    @Published private(set) var hasScrolledBelowChrome = false
    private var resetsScrollOnCommit = true
    private var needsInitialScrollPosition = true
    @Published var message: String?
    @Published var identity: TahoeWebsiteIdentity
    @Published var dialog: TahoeBrowserDialog?
    @Published var authentication: TahoeHTTPAuthentication?
    @Published private(set) var webView: WKWebView?
    @Published var chatWorkspace: TahoeChatWorkspace?
    weak var chatOwner: TahoeChatWorkspace?
    var restoredChatWorkspace: TahoeSavedChatWorkspace?
    private var chatBridge: TahoeChatBridge?
    private(set) var needsAutomaticRestore = false
    var isPresented = false { didSet { if isPresented { lastUse = ProcessInfo.processInfo.systemUptime } } }
    var lastUse = ProcessInfo.processInfo.systemUptime
    var activityKnown = false
    var hasDirtyForm = false
    var privateMediaChoices: [String: String] = [:]
    var transferredChatState: TahoeChatItem?
    @Published var playingMedia = false
    @Published var mediaSuspended = false
    @Published private(set) var isSleeping = false
    private var activityBridge: TahoePageActivityBridge?
    private var automaticNavigation: WKNavigation?
    private var recoveryBudget = TahoePageRecoveryBudget()
    var activePage: TahoeBrowserTab { chatWorkspace?.focusedPage ?? self }
    var chatHost: TahoeBrowserTab { chatOwner?.host ?? self }
    var hasWebContent: Bool { activePage.webView != nil && !activePage.needsAutomaticRestore }
    var dataStoreForTransfer: WKWebsiteDataStore { websiteDataStore }
    var protectedChatCount: Int {
        if let chatWorkspace { return chatWorkspace.protectedCount }
        if let item = chatOwner?.state.items.first(where: { $0.id == id }) { return item.hasProtectedWork ? 1 : 0 }
        return hasDirtyForm || transferredChatState?.hasProtectedWork == true ? 1 : 0
    }
    var savedDescriptor: TahoeSavedTab? {
        guard profile != .privateBrowsing, let url = currentURL else { return nil }
        return TahoeSavedTab(id: id, url: url, profile: profile.rawValue, zoom: webView.map { Double($0.pageZoom) } ?? restoredZoom,
            identity: identity.rawValue, pinned: pinned, chatWorkspace: chatWorkspace?.saved ?? restoredChatWorkspace, group: group)
    }
    func findOnPage() { webView?.isFindInteractionEnabled = true; webView?.findInteraction?.presentFindNavigator(showingReplace: false) }
    func toggleMedia() { mediaSuspended.toggle(); webView?.setAllMediaPlaybackSuspended(mediaSuspended, completionHandler: nil) }
    func updateAdapterScript(_ source: String) {
        guard let view = webView else { return }
        let controller = view.configuration.userContentController
        controller.removeAllUserScripts()
        if let script = identity.enhancedScript { controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)) }
        controller.addUserScript(WKUserScript(source: TahoePageActivityBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        installChatBridge(on: controller, addScript: true)
        view.evaluateJavaScript("window.__sideosChat?.dispose();\n" + source, in: nil, in: .defaultClient) { result in
            if case .failure = result { Task { @MainActor in TahoeWorkspace.shared.error = "ChatGPT controls could not initialize. Use Bundled Adapter in Browser Settings to recover." } }
        }
    }

    var openTab: ((URL, WKWebViewConfiguration?, TahoeWebsiteIdentity) -> WKWebView?)?
    var requestClose: (() -> Void)?
    var changed: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var faviconTask: Task<Void, Never>?

    init(url: URL, configuration: WKWebViewConfiguration? = nil, load: Bool = true,
         identity: TahoeWebsiteIdentity? = nil, profile: TahoeBrowserProfile = .personal,
         websiteDataStore: WKWebsiteDataStore? = nil, id: UUID = UUID()) {
        self.id = id
        self.profile = profile
        self.websiteDataStore = websiteDataStore ?? .default()
        self.identity = identity ?? TahoePreferences.shared.value.browserIdentity
        super.init()
        address = url.absoluteString
        if load { makeWebView(configuration: configuration) }
        // WebKit loads the original request itself when it supplies a popup configuration.
        if configuration == nil, load { webView?.load(URLRequest(url: url)) }
        if !load { needsAutomaticRestore = true; message = "Waiting to restore page…" }
    }

    private func makeWebView(configuration: WKWebViewConfiguration? = nil) {
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil { config.websiteDataStore = websiteDataStore }
        // Identity determines content mode. Avoid appending synthetic Safari
        // tokens to a native UA: that previously produced inconsistent headers.
        config.defaultWebpagePreferences.preferredContentMode = identity.isMacOS ? .desktop : .recommended
        config.applicationNameForUserAgent = nil
        // A fresh controller prevents an enhanced tab's injected script from
        // leaking into its parent, siblings or WebKit-created popup tabs.
        config.userContentController = WKUserContentController()
        if let source = identity.enhancedScript {
            config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        installChatBridge(on: config.userContentController, addScript: true)
        config.userContentController.addUserScript(WKUserScript(source: TahoePageActivityBridge.script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.pageZoom = restoredZoom
        // WebKit may repaint after its UIKit surface expands. Let the themed
        // browser canvas show through those unpainted areas instead of flashing
        // the default opaque white backing during maximise/live resize.
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        // Obscured insets describe the layout viewport, while the scroll
        // inset provides actual space for the document at its top boundary.
        // Keep the two equal; obscuredContentInsets alone can leave the first
        // document pixels at y=0, hidden beneath the toolbar's neutral pocket.
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.contentInset.top = 94
        view.scrollView.verticalScrollIndicatorInsets.top = 94
        if #available(iOS 26.0, *) {
            view.obscuredContentInsets = UIEdgeInsets(top: 94, left: 0, bottom: 0, right: 0)
        }
        view.scrollView.setContentOffset(CGPoint(x: 0, y: -94), animated: false)
        if identity.isMacOS {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            view.customUserAgent = TahoeWebsiteIdentity.macSafariUserAgent(systemMajor: os.majorVersion, systemMinor: os.minorVersion)
        }
        view.overrideUserInterfaceStyle = tahoeBrowserInterfaceStyle(TahoePreferences.shared.value.appearance)
        bindWebView(view)
    }

    private func bindWebView(_ view: WKWebView) {
        needsAutomaticRestore = false
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        webView = view
        activityBridge = TahoePageActivityBridge(self)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "sideosActivity", contentWorld: .defaultClient)
        if let activityBridge { view.configuration.userContentController.add(activityBridge, contentWorld: .defaultClient, name: "sideosActivity") }
        progress = view.estimatedProgress
        canGoBack = view.canGoBack; canGoForward = view.canGoForward
        loading = view.isLoading
        observations = [
            view.observe(\.title, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let self, self.webView === view else { return }
                    let title = view.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.title = title.isEmpty ? view.url?.host ?? "Browser" : title
                    self.changed?()
                }
            },
            view.observe(\.url, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let self, self.webView === view, let url = view.url, TahoeStorage.isWebURL(url) else { return }
                    self.address = url.absoluteString
                    self.chatOwner?.navigationChanged(self, url: url)
                    self.changed?()
                }
            },
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.progress = view.estimatedProgress }
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
            },
            view.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
            },
            view.scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak view] _, _ in
                DispatchQueue.main.async {
                    guard let self, let view, self.webView === view else { return }
                    self.updateScrollUnderlay(for: view)
                }
            }
        ]
    }

    /// Use one native scroll origin for both the document and glass backdrop.
    /// This also handles trackpad, keyboard and scripted scrolling to the top.
    private func updateScrollUnderlay(for view: WKWebView) {
        let distance = view.scrollView.contentOffset.y + view.scrollView.adjustedContentInset.top
        let scrolled = !needsInitialScrollPosition && distance > 2
        if hasScrolledBelowChrome != scrolled { hasScrolledBelowChrome = scrolled }
    }

    func updateChromeInset(_ height: CGFloat, for view: WKWebView) {
        guard webView === view else { return }
        let scroll = view.scrollView
        let distance = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let height = max(0, height)
        let changed = abs(scroll.contentInset.top - height) > 0.5
        if #available(iOS 26.0, *) {
            if abs(view.obscuredContentInsets.top - height) > 0.5 {
                view.obscuredContentInsets = UIEdgeInsets(top: height, left: 0, bottom: 0, right: 0)
            }
        }
        if changed {
            var inset = scroll.contentInset
            inset.top = height
            scroll.contentInset = inset
            var indicators = scroll.verticalScrollIndicatorInsets
            indicators.top = height
            scroll.verticalScrollIndicatorInsets = indicators
            // Revealing fullscreen chrome or changing window geometry must
            // preserve document position, including an untouched page's top.
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                y: distance - scroll.adjustedContentInset.top), animated: false)
        }
    }

    private func positionNewDocument(in view: WKWebView) {
        guard needsInitialScrollPosition else { return }
        view.layoutIfNeeded()
        needsInitialScrollPosition = false
        let inset = view.scrollView.adjustedContentInset
        view.scrollView.setContentOffset(CGPoint(x: -inset.left, y: -inset.top), animated: false)
        updateScrollUnderlay(for: view)
    }

    /// A WKWebView's document-start scripts and UA are configured before
    /// navigation. Changing identity therefore replaces only this tab's
    /// web view, preserving the normal website data store and safeguards.
    func setWebsiteIdentity(_ newIdentity: TahoeWebsiteIdentity, confirmed: Bool = false) {
        if let page = chatWorkspace?.focusedPage { page.setWebsiteIdentity(newIdentity); return }
        guard newIdentity != identity else { return }
        if !confirmed, protectedChatCount > 0 {
            TahoeClosePolicy.perform(owner: chatHost.id, protectedCount: protectedChatCount, title: "Reload this tab to change identity?") { [weak self] in
                self?.setWebsiteIdentity(newIdentity, confirmed: true)
            }
            return
        }
        guard !TahoeDownloads.shared.isActive(id) else {
            message = "Finish this tab's active download before changing its website identity."
            return
        }
        let url = currentURL
        let zoom = webView?.pageZoom ?? 1
        let wasLoaded = webView != nil
        if wasLoaded { release() }
        identity = newIdentity
        if wasLoaded {
            makeWebView()
            webView?.pageZoom = zoom
            message = nil
            if let url { address = url.absoluteString; webView?.load(URLRequest(url: url)) }
        }
        changed?()
    }

    func navigate() {
        isSleeping = false
        if let chatWorkspace { chatWorkspace.navigate(address); return }
        TahoePageRestoration.shared.finish(id)
        automaticNavigation = nil
        needsAutomaticRestore = false
        _ = loadAddress()
    }
    private func loadAddress(automatically: Bool = false) -> Bool {
        guard let url = TahoeAddress.url(for: address, provider: TahoePreferences.shared.value.searchProvider ?? .google) else { message = "Enter an HTTP or HTTPS address, or a search."; return false }
        if webView == nil { makeWebView() }
        completeAuthentication(nil)
        message = nil
        loading = true
        let navigation = webView?.load(URLRequest(url: url))
        if automatically { automaticNavigation = navigation }
        if navigation == nil { loading = false; message = "Unable to load this page. Retry to load it again." }
        return navigation != nil
    }
    func resumeIfNeeded(priority: Bool = false) {
        if isSleeping && !priority { return }
        if priority {
            if isSleeping { message = "Waiting to restore page…" }
            isSleeping = false; lastUse = ProcessInfo.processInfo.systemUptime
        }
        if let chatWorkspace { chatWorkspace.resumePages(); return }
        TahoePageRestoration.shared.request(self, priority: priority)
    }
    func beginAutomaticRestore() -> Bool {
        guard needsAutomaticRestore else { return false }
        needsAutomaticRestore = false
        return loadAddress(automatically: true)
    }
    func automaticRestoreTimedOut() {
        guard automaticNavigation != nil else { return }
        automaticNavigation = nil
        webView?.stopLoading()
        loading = false
        message = "This page took too long to restore. Check your connection and retry."
    }
    private func finishAutomaticRestore(_ navigation: WKNavigation?) {
        guard let automaticNavigation, navigation === automaticNavigation else { return }
        self.automaticNavigation = nil
        TahoePageRestoration.shared.finish(id)
    }

    func hibernate() {
        guard !pinned, !chatHost.pinned else { return }
        if let chatWorkspace { chatWorkspace.hibernate(); return }
        // Blank opener windows may be waiting for a sign-in script to navigate.
        // Without a restorable address, unloading cannot preserve that flow.
        if webView != nil && currentURL == nil { return }
        if let item = chatOwner?.state.items.first(where: { $0.id == id }), item.hasProtectedWork { return }
        guard !hasDirtyForm, !playingMedia, !pinned, !TahoeDownloads.shared.isActive(id) else { return }
        release()
        needsAutomaticRestore = true
    }
    func sleep() {
        guard webView != nil, !hasDirtyForm, !playingMedia else { return }
        hibernate()
        if webView == nil { isSleeping = true; message = "Sleeping to save memory. Select this tab to wake it." }
    }

    func release() {
        TahoePageRestoration.shared.finish(id)
        automaticNavigation = nil
        needsAutomaticRestore = false
        chatWorkspace?.release()
        chatWorkspace = nil
        suggestions.dismiss()
        suggestionsFocused = false
        hasScrolledBelowChrome = false
        resetsScrollOnCommit = true
        needsInitialScrollPosition = true
        faviconTask?.cancel()
        favicon = nil
        completeAuthentication(nil)
        completeDialog(nil)
        if let url = webView?.url { address = url.absoluteString }
        observations.removeAll()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        if let controller = webView?.configuration.userContentController {
            controller.removeScriptMessageHandler(forName: "sideosChat", contentWorld: .defaultClient)
            controller.removeScriptMessageHandler(forName: "sideosActivity", contentWorld: .defaultClient)
        }
        activityBridge = nil; activityKnown = false; hasDirtyForm = false; playingMedia = false
        chatBridge = nil
        webView = nil
        loading = false
        canGoBack = false
        canGoForward = false
        message = "Page unloaded to save memory. Resume reloads its address; unsaved page state and back history are not retained."
    }

    var currentURL: URL? {
        if let page = chatWorkspace?.focusedPage { return page.currentURL }
        if let url = webView?.url, TahoeStorage.isWebURL(url) { return url }
        if let url = URL(string: address), TahoeStorage.isWebURL(url) { return url }
        return nil
    }

    private func installChatBridge(on controller: WKUserContentController, addScript: Bool) {
        controller.removeScriptMessageHandler(forName: "sideosChat", contentWorld: .defaultClient)
        let bridge = TahoeChatBridge(page: self)
        chatBridge = bridge
        controller.add(bridge, contentWorld: .defaultClient, name: "sideosChat")
        if addScript {
            controller.addUserScript(WKUserScript(source: TahoeAdapterResources.shared.script,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
    }
    func configureChat(_ state: [String: Any]) {
        guard let view = webView, let url = view.url, TahoeChatWorkspaceState.allows(url),
              let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("window.__sideosChat?.configure(\(json));", in: nil, in: .defaultClient) { _ in }
    }
    func makeChatPage(id: UUID, url: URL) -> TahoeBrowserTab {
        TahoeBrowserTab(url: url, load: false, identity: identity, profile: profile,
                        websiteDataStore: websiteDataStore, id: id)
    }
    private func moveWebView(to page: TahoeBrowserTab) {
        guard let view = webView else { return }
        TahoePageRestoration.shared.finish(id)
        automaticNavigation = nil
        observations.removeAll(); faviconTask?.cancel()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "sideosChat", contentWorld: .defaultClient)
        chatBridge = nil; webView = nil
        page.address = view.url?.absoluteString ?? address
        page.activityKnown = activityKnown; page.hasDirtyForm = hasDirtyForm; page.playingMedia = playingMedia
        activityBridge = nil
        page.title = view.title ?? title; page.favicon = favicon; page.loading = loading
        page.message = nil
        page.needsInitialScrollPosition = needsInitialScrollPosition
        page.resetsScrollOnCommit = resetsScrollOnCommit
        page.hasScrolledBelowChrome = hasScrolledBelowChrome
        page.installChatBridge(on: view.configuration.userContentController, addScript: false)
        page.bindWebView(view)
    }
    func activateChatWorkspace(report: [String: Any]) {
        guard chatWorkspace == nil, chatOwner == nil, webView != nil,
              let url = webView?.url, TahoeChatWorkspaceState.allows(url) else { return }
        let page = makeChatPage(id: UUID(), url: url)
        moveWebView(to: page)
        let controller = TahoeChatWorkspace(host: self, initial: page, saved: restoredChatWorkspace)
        restoredChatWorkspace = nil
        chatWorkspace = controller
        controller.receive(report, from: page)
        controller.activate()
    }
    func restoreChatPage(_ page: TahoeBrowserTab) {
        page.moveWebView(to: self)
    }
    func setChatTabsEnabled(_ enabled: Bool) {
        (workspace ?? .shared).setChatTabsEnabled(enabled)
    }

    func completeDialog(_ value: String?) {
        guard let dialog else { return }
        self.dialog = nil
        dialog.completion(value)
    }

    func completeAuthentication(_ credential: URLCredential?) {
        guard let authentication else { return }
        self.authentication = nil
        authentication.completion(credential)
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard challenge.previousFailureCount < 3 else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completeAuthentication(nil); completeDialog(nil)
        let space = challenge.protectionSpace
        authentication = TahoeHTTPAuthentication(origin: "\(space.protocol ?? "https")://\(space.host):\(space.port)", user: challenge.proposedCredential?.user ?? "", retry: challenge.previousFailureCount > 0) { credential in
            completionHandler(credential == nil ? .cancelAuthenticationChallenge : .useCredential, credential)
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        if automaticNavigation == nil || navigation !== automaticNavigation {
            // Back, Reload and page links can navigate directly through WebKit.
            // An old restoration deadline must never stop the new navigation.
            TahoePageRestoration.shared.finish(id)
            automaticNavigation = nil
            needsAutomaticRestore = false
        }
        hasScrolledBelowChrome = false
        needsInitialScrollPosition = resetsScrollOnCommit
        faviconTask?.cancel()
        favicon = nil
        loading = true
        message = nil
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        activityKnown = false; hasDirtyForm = false; playingMedia = false
        positionNewDocument(in: webView)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        if let automaticNavigation, navigation !== automaticNavigation { return }
        finishAutomaticRestore(navigation)
        loading = false
        address = webView.url?.absoluteString ?? address
        let pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = pageTitle.isEmpty ? webView.url?.host ?? "Browser" : pageTitle
        refreshFavicon(in: webView)
        // Commit normally establishes the origin. This fallback only handles
        // a navigation that finished without committing a new document; it
        // never snaps an already committed page back after the user scrolls.
        positionNewDocument(in: webView)
        updateScrollUnderlay(for: webView)
        if let url = currentURL { TahoeBrowserLibrary.shared.record(url: url, title: title, profile: profile) }
        changed?()
    }
    /// Read a site's declared icon directly from its own page. No proxy,
    /// tracking service or fabricated 'favicon' is introduced.
    private func refreshFavicon(in webView: WKWebView) {
        guard let pageURL = webView.url else { return }
        let script = "[...document.querySelectorAll('link[rel~=icon],link[rel=apple-touch-icon]')].sort((a,b)=>(a.type===\"image/svg+xml\")-(b.type===\"image/svg+xml\")).map(e=>e.href).slice(0,6)"
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
            guard let self, let webView, self.webView === webView, webView.url == pageURL else { return }
            var candidates = (result as? [String] ?? []).compactMap(URL.init(string:))
            if var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                parts.query = nil; parts.fragment = nil
                for path in ["/apple-touch-icon.png", "/favicon.ico"] { parts.path = path; if let url = parts.url { candidates.append(url) } }
            }
            self.faviconTask?.cancel()
            self.faviconTask = Task { [weak self, weak webView] in
                guard let data = await TahoeFaviconLoader.shared.load(candidates), !Task.isCancelled,
                      let self, let webView, self.webView === webView, webView.url == pageURL else { return }
                self.favicon = UIImage(data: data)
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if self.webView === webView { failed(error, navigation: navigation) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if self.webView === webView { failed(error, navigation: navigation) } }
    private func failed(_ error: Error, navigation: WKNavigation?) {
        if let automaticNavigation, navigation !== automaticNavigation { return }
        finishAutomaticRestore(navigation)
        loading = false
        if (error as NSError).code != NSURLErrorCancelled { message = error.localizedDescription }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        TahoePageRestoration.shared.finish(id)
        automaticNavigation = nil
        completeAuthentication(nil); completeDialog(nil)
        loading = false
        if recoveryBudget.allow(at: ProcessInfo.processInfo.systemUptime) {
            needsAutomaticRestore = true
            message = "Restoring page…"
            let visibleChat = chatOwner.map { $0.host?.isPresented == true && ($0.state.left == id || $0.state.right == id) } ?? false
            resumeIfNeeded(priority: isPresented || visibleChat)
        } else { message = "This page keeps stopping. Retry to load it again." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = identity.isMacOS ? .desktop : .recommended
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        if ["mailto", "tel", "sms", "facetime", "maps", "itms-apps"].contains(scheme),
           navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            decisionHandler(.cancel, preferences)
            TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Open in Another App?",
                message: "\(webView.url?.host ?? "This website") wants to open:\n\(url.absoluteString.prefix(500))", primary: "Open", accept: { _ in
                    UIApplication.shared.open(url, options: [:]) { opened in
                        if !opened { Task { @MainActor in TahoeWorkspace.shared.error = "No installed app can open this link." } }
                    }
                })
            return
        }
        if navigationAction.shouldPerformDownload, ["http", "https", "blob", "data"].contains(scheme) {
            decisionHandler(.download, preferences); return
        }
        // Subframe blobs/data are common in web applications. Top-level executable/file URLs are refused.
        let allowed = ["http", "https", "about"].contains(scheme) ||
            (navigationAction.targetFrame?.isMainFrame == false && ["blob", "data"].contains(scheme))
        if allowed && navigationAction.targetFrame?.isMainFrame == true {
            // WebKit owns history/reload restoration. Fresh links, locations,
            // searches and new tabs start at the protected document origin.
            resetsScrollOnCommit = navigationAction.navigationType != .backForward && navigationAction.navigationType != .reload
            if let owner = chatOwner, let url = navigationAction.request.url,
               !TahoeChatWorkspaceState.allows(url), owner.protectedCount > 0 {
                TahoeClosePolicy.perform(owner: owner.host?.id ?? id, protectedCount: owner.protectedCount,
                    title: "Leave chat workspace?", cancel: { decisionHandler(.cancel, preferences) }) { [weak self, weak owner] in
                    guard let self, let owner else { decisionHandler(.cancel, preferences); return }
                    owner.leave(using: self, confirmed: true)
                    decisionHandler(.allow, preferences)
                }
                return
            }
            // Full-document navigation can also discard a draft while staying
            // on ChatGPT. Form submission and same-document anchors retain the
            // website's normal behavior; document reload/history/location do not.
            let submitting = navigationAction.navigationType == .formSubmitted || navigationAction.navigationType == .formResubmitted
            let from = webView.url, to = navigationAction.request.url
            func withoutFragment(_ url: URL?) -> String? {
                guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
                parts.fragment = nil; return parts.string
            }
            let anchorOnly = from != to && withoutFragment(from) == withoutFragment(to)
            if !submitting, !anchorOnly, protectedChatCount > 0 {
                TahoeClosePolicy.perform(owner: chatHost.id, protectedCount: protectedChatCount,
                    title: "Leave or reload this page?", cancel: { decisionHandler(.cancel, preferences) }) {
                    decisionHandler(.allow, preferences)
                }
                return
            }
        }
        if !allowed { message = "This link uses an unsupported scheme: \(scheme)." }
        if allowed, navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url {
            Task {
                await TahoeContentBlocking.shared.install(on: webView, url: url)
                decisionHandler(self.webView === webView ? .allow : .cancel, preferences)
            }
        } else { decisionHandler(allowed ? .allow : .cancel, preferences) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        loading = false; TahoeDownloads.shared.track(download, tabID: id, source: webView, profile: profile)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        loading = false; TahoeDownloads.shared.track(download, tabID: id, source: webView, profile: profile)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completeDialog(nil)
        dialog = TahoeBrowserDialog(kind: .alert, title: frame.securityOrigin.host, message: message, completion: { _ in completionHandler() })
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completeDialog(nil)
        dialog = TahoeBrowserDialog(kind: .confirm, title: frame.securityOrigin.host, message: message, completion: { completionHandler($0 == "yes") })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completeDialog(nil)
        dialog = TahoeBrowserDialog(kind: .prompt, title: frame.securityOrigin.host, message: prompt, value: defaultText ?? "", completion: completionHandler)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard origin.protocol == "https", (workspace ?? .shared).activeBrowserPage === self else { decisionHandler(.deny); return }
        var parts = URLComponents(); parts.scheme = origin.protocol; parts.host = origin.host
        if origin.port != 0 && origin.port != 443 { parts.port = origin.port }
        let requestOrigin = parts.string ?? ""
        let kinds = type == .camera ? ["camera"] : type == .microphone ? ["microphone"] : ["camera", "microphone"]
        let choices = kinds.map { mediaChoice($0, origin: requestOrigin) }
        if choices.contains("deny") { decisionHandler(.deny); return }
        if choices.allSatisfy({ $0 == "allow" }) { decisionHandler(.grant); return }
        completeDialog(nil)
        dialog = TahoeBrowserDialog(kind: .confirm, title: "Website Permission", message: "Allow \(origin.host) to use your \(type == .camera ? "camera" : type == .microphone ? "microphone" : "camera and microphone")?", completion: { decisionHandler($0 == "yes" ? .grant : .deny) })
    }
    func webViewDidClose(_ webView: WKWebView) { requestClose?() }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url,
              TahoeAddress.allowsPopup(url) else { return nil }
        return openTab?(url, configuration, identity)
    }
}

