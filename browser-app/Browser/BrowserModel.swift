import SwiftUI
import WebKit

enum BrowserProfile: String, CaseIterable, Identifiable {
    case personal = "Personal", work = "Work", privateMode = "Private"
    var id: String { rawValue }
}

@MainActor final class BrowserWindows: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selected: UUID?
    private let privateStore = WKWebsiteDataStore.nonPersistent()
    var active: BrowserTab? { tabs.first { $0.id == selected } }
    init() { add() }
    func add(url: URL = URL(string: "https://duckduckgo.com")!, profile: BrowserProfile = .personal, configuration: WKWebViewConfiguration? = nil) {
        let store: WKWebsiteDataStore
        switch profile {
        case .personal: store = .default()
        case .work: store = WKWebsiteDataStore(forIdentifier: IsolationPolicy.workStoreID)
        case .privateMode: store = privateStore
        }
        let tab = BrowserTab(url: url, profile: profile, store: store, configuration: configuration)
        tab.popup = { [weak self, weak tab] configuration, url in
            guard let self, let tab, configuration.websiteDataStore === tab.webView.configuration.websiteDataStore else { return nil }
            self.add(url: url, profile: tab.profile, configuration: configuration)
            return self.active?.webView
        }
        tabs.append(tab); selected = tab.id
    }
    func close(_ id: UUID) {
        tabs.first { $0.id == id }?.webView.stopLoading()
        tabs.removeAll { $0.id == id }
        if selected == id { selected = tabs.last?.id }
        if tabs.isEmpty { add() }
    }
}

@MainActor final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let profile: BrowserProfile
    let webView: WKWebView
    @Published private(set) var title = "New Tab"
    @Published private(set) var address = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    var popup: ((WKWebViewConfiguration, URL) -> WKWebView?)?
    private var observations: [NSKeyValueObservation] = []
    init(url: URL, profile: BrowserProfile, store: WKWebsiteDataStore, configuration: WKWebViewConfiguration?) {
        self.profile = profile
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil { config.websiteDataStore = store }
        config.userContentController = WKUserContentController() // No injected page/native bridges.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.preferredContentMode = .recommended
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.isInspectable = false
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [webView.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.changed() } },
            webView.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.changed() } },
            webView.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.changed() } }]
        if configuration == nil { webView.load(URLRequest(url: url)) }
    }
    private func changed() {
        title = webView.title ?? webView.url?.host ?? "New Tab"
        address = webView.url?.absoluteString ?? ""
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward; loading = webView.isLoading
    }
    func navigate(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let url: URL?
        if value.contains(":") { url = URL(string: value) }
        else if value.contains(".") && !value.contains(where: \.isWhitespace) { url = URL(string: "https://" + value) }
        else {
            var search = URLComponents(string: "https://duckduckgo.com/")!
            search.queryItems = [URLQueryItem(name: "q", value: value)]; url = search.url
        }
        guard let url, IsolationPolicy.webURL(url) else { error = "Only HTTPS websites without embedded usernames or passwords are allowed."; return }
        error = nil; webView.load(URLRequest(url: url))
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let subframe = navigationAction.targetFrame?.isMainFrame == false
        let allowed = url.map(IsolationPolicy.webURL) == true || url?.absoluteString == "about:blank" ||
            (subframe && ["data", "blob"].contains(url?.scheme ?? ""))
        if !allowed { error = "This navigation was blocked. The isolated browser accepts HTTPS websites only." }
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil) // Never bypass TLS trust or certificate failures.
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url,
              IsolationPolicy.webURL(url) || url.absoluteString == "about:blank" else { return nil }
        return popup?(configuration, url)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.protocol == "https" && frame.isMainFrame ? .prompt : .deny)
    }
}
