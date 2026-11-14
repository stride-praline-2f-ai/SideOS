import SwiftUI
import WebKit

struct TahoeBrowserPage: View {
    @ObservedObject var tab: TahoeBrowserTab
    let windowID: UUID
    let chromeInset: CGFloat
    @EnvironmentObject private var workspace: TahoeWorkspace
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.tahoeWindowActive) private var windowActive
    @Environment(\.tahoeWindowVisible) private var windowVisible
    var body: some View {
        ZStack(alignment: .top) {
            if let chats = tab.chatWorkspace {
                TahoeChatWorkspaceSurface(workspace: chats, chromeInset: chromeInset, appearance: preferences.value.appearance)
                    .accessibilityHidden(tab.activePage.dialog != nil || tab.activePage.authentication != nil)
            } else if let webView = tab.webView {
                TahoeWebSurface(tab: tab, webView: webView, appearance: preferences.value.appearance, chromeInset: chromeInset)
                    .id(ObjectIdentifier(webView))
                    .accessibilityHidden(tab.dialog != nil || tab.authentication != nil)
            } else {
                TahoeDesign.content
            }
            TahoeBrowserPageStatus(tab: tab.activePage, chromeInset: chromeInset)
        }
        .background(TahoeDesign.content)
        .onChange(of: windowActive) { _, active in if !active { tab.activePage.webView?.endEditing(true) } }
        .onChange(of: windowVisible, initial: true) { _, visible in
            tab.isPresented = visible
            if visible { tab.resumeIfNeeded(priority: true) }
            else { tab.activePage.webView?.endEditing(true) }
        }
        .onDisappear {
            // A display transfer remounts this surface while retaining its page.
            tab.isPresented = workspace.browsers[windowID]?.selectedID == tab.id &&
                workspace.state.windows.first(where: { $0.id == windowID }).map(workspace.state.isVisible) == true
        }
        .overlay { TahoeBrowserPageDialogs(tab: tab.activePage, windowVisible: windowVisible, windowActive: windowActive) }
        .onChange(of: preferences.value.chatTabsEnabled) { _, enabled in
            tab.setChatTabsEnabled(enabled)
        }

    }

}

private struct TahoeBrowserPageStatus: View {
    @ObservedObject var tab: TahoeBrowserTab
    let chromeInset: CGFloat
    var body: some View {
            VStack(spacing: 0) {
                TahoeProgress(value: tab.progress, height: 2, label: "Page loading").opacity(tab.loading ? 1 : 0)
                if let message = tab.message {
                    HStack {
                        Text(message).font(.caption).textSelection(.enabled)
                        Spacer()
                        if tab.needsAutomaticRestore {
                            ProgressView().controlSize(.small).accessibilityLabel("Restoring page automatically")
                        } else {
                            Button(tab.webView == nil ? "Resume" : "Retry") { tab.navigate() }
                        }
                    }.padding(10).background(Color.orange.opacity(0.12))
                }
            }.padding(.top, chromeInset)
    }
}

private struct TahoeBrowserPageDialogs: View {
    @ObservedObject var tab: TahoeBrowserTab
    let windowVisible: Bool
    let windowActive: Bool
    @FocusState private var dialogFocused: Bool
    @State private var dialogInput = ""
    var body: some View {
        Color.clear.allowsHitTesting(false)
        .overlay {
            if let authentication = tab.authentication { TahoeAuthenticationView(request: authentication, complete: tab.completeAuthentication).id(authentication.id) }
            if let dialog = tab.dialog {
                ZStack {
                    Color.black.opacity(0.20)
                    VStack(spacing: 16) {
                        Image(systemName: "safari").font(.largeTitle).foregroundStyle(TahoeDesign.accent)
                        Text(dialog.title).font(.headline)
                        Text(dialog.message).font(.system(size: 13)).multilineTextAlignment(.center).lineLimit(12)
                        if dialog.kind == .prompt { TextField(TahoeStrings.ui("Response"), text: $dialogInput).textFieldStyle(.plain).focused($dialogFocused).tahoeField(focused: dialogFocused) }
                        HStack {
                            if dialog.kind != .alert { Button(TahoeStrings.ui("Cancel")) { tab.completeDialog(nil) }.buttonStyle(TahoeControlStyle()) }
                            Button(TahoeStrings.ui("OK")) { tab.completeDialog(dialog.kind == .prompt ? dialogInput : "yes") }.buttonStyle(TahoeControlStyle(variant: .accent))
                        }.tahoeGlassGroup()
                    }.padding(24).frame(maxWidth: 340).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 24).padding(16).onAppear {
                            dialogInput = dialog.value; tab.webView?.endEditing(true)
                            dialogFocused = dialog.kind == .prompt && windowActive && windowVisible
                        }
                }
            }
        }
    }
}

private struct TahoeWebSurface: UIViewRepresentable {
    let tab: TahoeBrowserTab
    let webView: WKWebView
    let appearance: String
    let chromeInset: CGFloat
    @Environment(\.tahoeWindowVisible) private var visible
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        // Keep CSS prefers-color-scheme aligned with the chosen SideOS
        // appearance. System means inherit the iPadOS device appearance.
        webView.overrideUserInterfaceStyle = tahoeBrowserInterfaceStyle(appearance)
        // Both viewport layout and the actual scroll origin use the full
        // visible chrome height. Keep updates out of website CSS/JavaScript.
        tab.updateChromeInset(chromeInset, for: webView)
        // Hide the child UIKit view explicitly; SwiftUI owns the outer container.
        webView.isHidden = !visible
        webView.isUserInteractionEnabled = visible
        webView.accessibilityElementsHidden = !visible
        if !visible { webView.endEditing(true) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height, width.isFinite, height.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }
}

