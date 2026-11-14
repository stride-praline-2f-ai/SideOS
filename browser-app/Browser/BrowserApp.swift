import SwiftUI
import WebKit

@MainActor final class BrowserSigningGate: ObservableObject {
    @Published private(set) var problems: [String] = []
    private(set) var applicationID = ""
    init() { check() }
    func check() {
        let snapshot = SideOSSigningSnapshot() as? [String: Any]
        applicationID = snapshot?["application-identifier"] as? String ?? ""
        problems = IsolationPolicy.findings(snapshot: snapshot, bundleID: Bundle.main.bundleIdentifier ?? "", info: Bundle.main.infoDictionary ?? [:])
    }
}

@main struct SideOSBrowserApp: App {
    @StateObject private var signing = BrowserSigningGate()
    var body: some Scene {
        WindowGroup("SideOS Browser", id: "browser") {
            Group {
                if signing.problems.isEmpty { BrowserScreen(signing: signing) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("Signing settings need correction", systemImage: "lock.shield").font(.title2.bold())
                            Text("Website sessions stay closed until this is verified as a separately installed browser with private storage and no debug access.")
                            ForEach(signing.problems, id: \.self) { Text($0).foregroundStyle(.red) }
                            Text("Install this IPA as its own app. Keep get-task-allow disabled and remove app-group, shared-keychain and wildcard entitlements when signing. Do not import this browser into LiveContainer.")
                            Button("Check Signature Again") { signing.check() }.buttonStyle(.borderedProminent)
                        }.padding(24).frame(maxWidth: 700)
                    }
                }
            }.preferredColorScheme(.dark)
        }
    }
}

struct BrowserScreen: View {
    @ObservedObject var signing: BrowserSigningGate
    @StateObject private var browser = BrowserWindows()
    @StateObject private var canaries = BrowserCanaries()
    @State private var address = ""
    @State private var showChecks = false
    @State private var incoming: URL?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var enteringAddress: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("SideOS Browser", systemImage: "lock.shield").font(.headline)
                Spacer()
                Menu {
                    ForEach(BrowserProfile.allCases) { profile in Button(profile.rawValue) { browser.add(profile: profile) } }
                } label: { Image(systemName: "plus").frame(width: 36, height: 32) }.accessibilityLabel("New tab")
                Button { showChecks = true } label: { Image(systemName: "checkmark.shield").frame(width: 36, height: 32) }.accessibilityLabel("Isolation checks")
            }.padding(.horizontal, 16).padding(.vertical, 10)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(browser.tabs) { tab in
                        BrowserTabLabel(tab: tab, selected: browser.selected == tab.id,
                            select: { browser.selected = tab.id }, close: { browser.close(tab.id) })
                    }
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }
            if let tab = browser.active {
                BrowserContent(tab: tab, address: $address, enteringAddress: $enteringAddress)
            }
        }.background(.background)
            .sheet(isPresented: $showChecks) { IsolationCheckView(applicationID: signing.applicationID, canaries: canaries) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { signing.check() } }
            .onOpenURL { url in if incoming == nil { incoming = IsolationPolicy.handoff(url) } }
            .alert("Open a Website from Another App?", isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } })) {
                Button("Cancel", role: .cancel) { incoming = nil }
                Button("Open") { if let incoming { browser.add(url: incoming) }; incoming = nil }
            } message: { Text(incoming?.absoluteString ?? "") }
    }
}

private struct BrowserTabLabel: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) { Label(tab.title, systemImage: tab.profile == .privateMode ? "hand.raised" : "globe").lineLimit(1).frame(width: 150, alignment: .leading) }
            Button(action: close) { Image(systemName: "xmark").font(.caption).padding(5) }.accessibilityLabel("Close \(tab.title)")
        }.buttonStyle(.plain).padding(10)
            .background(selected ? Color.white.opacity(0.18) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct BrowserContent: View {
    @ObservedObject var tab: BrowserTab
    @Binding var address: String
    var enteringAddress: FocusState<Bool>.Binding
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack)
                Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward)
                TextField("Search or enter an HTTPS address", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused(enteringAddress).textFieldStyle(.roundedBorder).onSubmit { tab.navigate(address); enteringAddress.wrappedValue = false }
                Button { tab.webView.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reload")
            }.padding(12)
            HStack {
                Text(tab.profile.rawValue).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if tab.loading { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 14).padding(.bottom, 8)
            if let error = tab.error { Text(error).font(.callout).foregroundStyle(.orange).padding(10) }
            BrowserWebSurface(tab: tab)
        }.onChange(of: tab.address, initial: true) { _, url in if !enteringAddress.wrappedValue { address = url } }
    }
}

private struct BrowserWebSurface: UIViewRepresentable {
    @ObservedObject var tab: BrowserTab
    func makeUIView(context: Context) -> WKWebView { tab.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
