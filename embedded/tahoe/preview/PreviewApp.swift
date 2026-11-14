#if TAHOE_PREVIEW
import SwiftUI
import WebKit

// Simulator-only runtime adapters. This target intentionally has no native guest
// catalogue or guest engine. The production host compiles Guest.swift instead.
@MainActor final class SharedModel: ObservableObject { @Published var apps: [LCAppModel] = [] }
@MainActor final class LCPreviewInfo {
    let defaultClassicMode = 0
    func iconIsDarkIcon(_ dark: Bool) -> UIImage? { nil }
}
@MainActor final class LCAppModel: NSObject, ObservableObject {
    let appInfo = LCPreviewInfo()
    let uiIsLocked = false, uiIsHidden = false, uiIs32bit = false, uiIsJITNeeded = false
    // Match the production launcher contract without enabling guest/JIT hosting in preview.
    let delegate: AnyObject? = nil
    let displayName = "", bundleIdentifier = ""
    @Published var isSigningInProgress = false
    @Published var signProgress = 0.0
    func runApp(multitask: Bool) async throws { throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Native guests require the device host."]) }
}
@MainActor enum LCUtils { static func authenticateUser() async throws -> Bool { false } }
@MainActor final class TahoePreviewController: UIViewController { func openURLScheme(_ url: String) { } }
@MainActor final class TahoeGuestSession: ObservableObject {
    let bundleID: String
    let terminated = true
    var controller: TahoePreviewController? { nil }
    init(bundleID: String, dataUUID: String, completion: ((NSNumber?, Error?) -> Void)?) {
        self.bundleID = bundleID
        completion?(nil, NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Native hosting is unavailable in the simulator preview."]))
    }
    func close() { }
    func addCompletion(_ completion: ((NSNumber?, Error?) -> Void)?) { completion?(nil, NSError(domain: "Preview", code: 1)) }
}
struct TahoeGuestView: View {
    @ObservedObject var session: TahoeGuestSession
    var body: some View { Text("Native apps require the device host.") }
}

@main struct TahoePreviewApp: App {
    @StateObject private var model = SharedModel()
    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            // Only this disposable preview bundle's data is reset by UI tests.
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            try? FileManager.default.removeItem(at: TahoeStorage.root)
        }
    }
    var body: some Scene {
        WindowGroup {
            TahoePreviewRoot().environmentObject(model)
        }
    }
}

private struct TahoePreviewRoot: View {
    @ObservedObject private var workspace = TahoeWorkspace.shared
    @State private var configured = false
    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--controls") { TahoeControlReview() }
            else { TahoeDesktopView() }
        }
            .overlay {
                if workspace.showManagement {
                    VStack(spacing: 16) {
                        Text("Simulator Desktop Preview").font(.title2)
                        Text("LiveContainer and SideInstaller are available in the separate device host build.").multilineTextAlignment(.center)
                        Button("Return to Desktop") { workspace.showManagement = false }.buttonStyle(TahoeControlStyle(variant: .accent))
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(TahoeDesign.window)
                }
            }
            .alert("Desktop", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
                Button("OK") { workspace.error = nil }
            } message: { Text(workspace.error ?? "") }
            .task {
                guard !configured else { return }
                configured = true
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--dark") { TahoePreferences.shared.value.appearance = "dark" }
                if args.contains("--light") { TahoePreferences.shared.value.appearance = "light" }
                if args.contains("--showcase") {
                    try? await Task.sleep(for: .milliseconds(700))
                    showcase()
                    if args.contains("--standalone-test"), let id = workspace.state.activeID,
                       let session = workspace.browsers[id], let view = session.tabs.first?.webView {
                        let link = TahoeWebLink(title: "Standalone Test", url: URL(string: "https://example.com/app")!)
                        workspace.openWebApp(link)
                        if let appID = workspace.state.activeID, let app = workspace.browsers[appID]?.tabs.first?.webView {
                            app.stopLoading(); app.loadHTMLString(Self.samplePage, baseURL: link.url)
                        }
                        _ = view
                        workspace.close(id)
                    }
                    if args.contains("--tab-switch-test"), let id = workspace.state.activeID, let session = workspace.browsers[id] {
                        let first = session.selectedID
                        let view = session.add(url: URL(string: "https://example.org")!)
                        view?.stopLoading()
                        view?.loadHTMLString(Self.samplePage.replacingOccurrences(of: "Try the browser", with: "Try second tab"), baseURL: URL(string: "https://example.org"))
                        session.selectedID = first
                    }
                    if args.contains("--scroll-under-test"), let id = workspace.state.activeID,
                       let tab = workspace.browsers[id]?.tabs.first, let webView = tab.webView {
                        let fixture = TahoeScrollFixture(tab: tab)
                        webView.configuration.userContentController.add(fixture, name: "scrollFixture")
                        webView.stopLoading()
                        webView.loadHTMLString(fixture.page(1), baseURL: URL(string: "https://example.com/scroll/1"))
                    }
                    if args.contains("--browser-reference"), let id = workspace.state.activeID, let session = workspace.browsers[id] {
                        let first = session.selectedID
                        session.add(url: URL(string: "https://example.org")!, load: false)
                        session.tabs.last?.title = "A second website"
                        session.selectedID = first
                    }
                    if args.contains("--settings") {
                        workspace.open(.settings)
                        if let window = workspace.state.windows.last {
                            workspace.state.resize(window.id, from: window.frame, edge: .bottomRight, translation: CGSize(width: -60, height: 70))
                            if let adjusted = workspace.state.windows.last { workspace.state.move(adjusted.id, from: adjusted.frame, translation: CGSize(width: workspace.state.canvas.width - adjusted.frame.maxX - 20, height: 95)) }
                        }
                    }
                    if args.contains("--applications") { workspace.state.activateDesktop(); workspace.present(.launchpad) }
                    if args.contains("--fullscreen"), let id = workspace.state.activeID {
                        workspace.state.toggleFullscreen(id)
                        if args.contains("--reveal") {
                            try? await Task.sleep(for: .milliseconds(400))
                            TahoeFullscreenChrome.shared.reveal()
                            TahoeFullscreenChrome.shared.menuOpen = true
                        }
                    }
                }
                // CI must wait for the app, rather than photographing the
                // launch screen on a busy hosted Simulator.
                try? await Task.sleep(for: .seconds(1))
                if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                    try? Data("ready".utf8).write(to: cache.appendingPathComponent("tahoe-preview-ready"), options: .atomic)
                }
            }
    }
    private func showcase() {
        for id in workspace.state.windows.map(\.id) { workspace.close(id) }
        do {
            try TahoeFileStore.shared.prepare()
            let welcome = TahoeFileStore.shared.root.appendingPathComponent("Welcome.txt")
            if !FileManager.default.fileExists(atPath: welcome.path) { try "Welcome to your desktop.\nDrag windows, use Spotlight and make this workspace yours.".write(to: welcome, atomically: true, encoding: .utf8) }
        } catch { workspace.error = error.localizedDescription }
        workspace.openFiles(TahoeFileStore.shared.root)
        if let window = workspace.state.windows.last {
            workspace.state.resize(window.id, from: window.frame, edge: .bottomRight, translation: CGSize(width: -180, height: -50))
            if let adjusted = workspace.state.windows.last { workspace.state.move(window.id, from: adjusted.frame, translation: CGSize(width: -12, height: -12)) }
        }
        workspace.openBrowser(url: URL(string: "https://example.com")!)
        if let id = workspace.state.activeID, let session = workspace.browsers[id], let tab = session.tabs.first, let view = tab.webView {
            view.stopLoading()
            view.loadHTMLString(Self.samplePage, baseURL: URL(string: "https://example.com"))
            if let window = workspace.state.windows.last {
                workspace.state.resize(id, from: window.frame, edge: .bottomRight, translation: CGSize(width: -100, height: -60))
                if let adjusted = workspace.state.windows.last { workspace.state.move(id, from: adjusted.frame, translation: CGSize(width: 240, height: 90)) }
            }
        }
        workspace.overlay = nil
    }
    private static let samplePage = """
    <!doctype html><html><meta name="viewport" content="width=device-width, initial-scale=1"><title>A place for your ideas</title>
    <style>body{margin:0;font:16px -apple-system;background:#f8fafc;color:#18384e}main{padding:48px 40px}small{letter-spacing:3px;font-size:11px;color:#397f8e}h1{font-size:42px;letter-spacing:-1.5px;line-height:1.05;margin:24px 0}p{line-height:1.65;color:#5a7182;max-width:430px}.cards{display:flex;gap:12px;margin-top:32px}.card{background:white;border:1px solid #e2eaf0;border-radius:14px;padding:22px;flex:1;font-size:13px}button{border:0;background:#0088ff;color:white;padding:12px 18px;border-radius:8px;font:14px -apple-system}</style>
    <main><small>YOUR DESKTOP · YOUR SPACE</small><h1>A place for<br>your ideas.</h1><p>Real browser pages, a familiar desktop, and room to focus. This local preview page runs inside a native WKWebView.</p><button onclick="this.textContent='Clicked '+(++window.clicks)">Try the browser</button><div class="cards"><div class="card">⌘ Space<br><br><b>Find anything</b></div><div class="card">↔<br><br><b>Make room</b></div><div class="card">◉<br><br><b>Stay focused</b></div></div></main><script>window.clicks=0</script></html>
    """
}

/// A simulator-only review surface. These are the production controls, with
/// local input state; no hosted applications or system behaviour are simulated.
private struct TahoeControlReview: View {
    @ObservedObject private var preferences = TahoePreferences.shared
    @State private var query = ""
    @State private var toggle = true
    @State private var mixed = TahoeCheckState.mixed
    @State private var slider = 48.0
    @State private var segment = "list"
    @State private var multiple: Set<String> = ["one"]
    @State private var radio = "desktop"
    @State private var selection: String? = "one"
    private struct Tab: Identifiable { var id: String; var title: String }
    @State private var tabs = [Tab(id: "one", title: "First tab"), Tab(id: "two", title: "Second tab")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Native control review").font(.system(size: 26, weight: .bold)); Spacer(); TahoeHelpButton(title: "Control review", message: "Production desktop controls, shown in a simulator-only review surface.") }
                TahoeSettingsGroup(title: "Buttons and sizes") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(TahoeControlSize.allCases.enumerated()), id: \.offset) { _, size in
                            HStack(spacing: 16) {
                                Button("Default") { }.buttonStyle(TahoeControlStyle(size: size))
                                Button("Continue") { }.buttonStyle(TahoeControlStyle(variant: .accent, size: size))
                                Button("Delete") { }.buttonStyle(TahoeControlStyle(variant: .destructive, size: size))
                                Button("Disabled") { }.buttonStyle(TahoeControlStyle(size: size)).disabled(true)
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    TahoeSettingsGroup(title: "Selection and fields") {
                        VStack(alignment: .leading, spacing: 14) {
                            TahoeSearchField(text: $query).accessibilityIdentifier("review-search")
                            Toggle("Desktop option", isOn: $toggle).toggleStyle(TahoeSwitchStyle())
                            Toggle("Disabled option", isOn: $toggle).toggleStyle(TahoeSwitchStyle()).disabled(true)
                            TahoeCheckbox(title: "Mixed selection", state: $mixed)
                            TahoeRadioGroup(options: [TahoeChoice(id: "desktop", title: "Desktop websites"), TahoeChoice(id: "mobile", title: "Mobile websites"), TahoeChoice(id: "disabled", title: "Unavailable", enabled: false)], selection: $radio, label: "Website mode")
                        }
                    }
                    TahoeSettingsGroup(title: "Values and feedback") {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack { TahoeSlider(value: $slider, range: 36...64, step: 2, ticks: true, label: "Icon size"); TahoeStepper(value: $slider, range: 36...64, step: 2, label: "Icon size") }
                            TahoeSegments(options: [TahoeChoice(id: "icons", title: "Icons", symbol: "square.grid.2x2"), TahoeChoice(id: "list", title: "List", symbol: "list.bullet")], selection: $segment, label: "View mode")
                            TahoeSegments(options: [TahoeChoice(id: "one", title: "One"), TahoeChoice(id: "two", title: "Two"), TahoeChoice(id: "three", title: "Three")], selection: $multiple, label: "Multiple selection")
                            TahoeProgress(value: 0.6, label: "Download progress")
                            HStack { TahoeSpinner(); TahoeBadge(title: "Ready", tint: .green); TahoeBadge(title: "Paused", tint: .orange) }
                            TahoeDisclosure(title: "More information") { Text("Disclosure content is keyboard and touch accessible.") }
                        }
                    }
                }
                TahoeSettingsGroup(title: "Tabs") {
                    TahoeTabs(items: tabs, selection: $selection, close: { id in tabs.removeAll { $0.id == id }; if selection == id { selection = tabs.first?.id } }, add: { let tab = Tab(id: UUID().uuidString, title: "New tab"); tabs.append(tab); selection = tab.id }) { tab in Text(tab.title).font(.system(size: 12)) }
                }
            }.padding(32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(TahoeDesign.window).preferredColorScheme(preferences.colorScheme).tint(preferences.value.accentColor)
    }
}


/// Deterministic local documents exercise the production navigation delegate.
/// This handler exists only in the simulator preview, never in the device host.
@MainActor private final class TahoeScrollFixture: NSObject, WKScriptMessageHandler {
    private weak var tab: TahoeBrowserTab?
    private var number = 1
    init(tab: TahoeBrowserTab) { self.tab = tab; super.init() }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.body as? String == "next", let webView = tab?.webView else { return }
        number += 1
        webView.loadHTMLString(page(number), baseURL: URL(string: "https://example.com/scroll/\(number)"))
    }
    func page(_ number: Int) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Scroll fixture \(number)</title><style>
        html,body{margin:0;padding:0;font:16px -apple-system;background:white;color:#111}
        header{height:20px;background:#ffb020;font:16px/20px -apple-system}
        main{height:3200px;background:repeating-linear-gradient(#209cff 0px,#209cff 160px,#e8f6ff 160px,#e8f6ff 320px)}
        nav{position:fixed;bottom:20px;left:20px;display:flex;gap:12px}
        button{font:16px -apple-system;padding:12px;background:white;color:#111;border:2px solid #111;border-radius:8px}
        </style></head><body><header>DOCUMENT START \(number)</header><main>Scrollable content</main>
        <nav><button onclick="window.scrollTo(0,0)">Back to top</button>
        <button onclick="window.webkit.messageHandlers.scrollFixture.postMessage('next')">Open next page</button></nav>
        </body></html>
        """
    }
}
#endif
