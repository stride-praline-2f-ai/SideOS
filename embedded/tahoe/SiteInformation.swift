import SwiftUI
import WebKit

extension TahoeBrowserTab {
    var siteOrigin: String {
        guard let url = currentURL, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        parts.path = ""; parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        return parts.string ?? ""
    }
    func mediaChoice(_ kind: String, origin: String? = nil) -> String {
        let key = profile.rawValue + "|" + (origin ?? siteOrigin) + "|" + kind
        if profile == .privateBrowsing { return privateMediaChoices[key] ?? "ask" }
        return TahoePreferences.shared.value.siteMediaChoices?[key] ?? "ask"
    }
    func setMediaChoice(_ kind: String, value: String) {
        let key = profile.rawValue + "|" + siteOrigin + "|" + kind
        if profile == .privateBrowsing { privateMediaChoices[key] = value }
        else { var choices = TahoePreferences.shared.value.siteMediaChoices ?? [:]; choices[key] = value; TahoePreferences.shared.value.siteMediaChoices = choices }
        if value == "deny" {
            if kind == "camera" { webView?.setCameraCaptureState(.muted, completionHandler: nil) }
            if kind == "microphone" { webView?.setMicrophoneCaptureState(.muted, completionHandler: nil) }
        }
        objectWillChange.send()
    }
}

struct TahoeSiteInformation: View {
    @ObservedObject var page: TahoeBrowserTab
    @State private var status: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label(TahoeStrings.ui("Website Information"), systemImage: page.currentURL?.scheme == "https" ? "lock" : "network").font(.headline); Spacer(); Button(TahoeStrings.ui("Done")) { TahoeWorkspace.shared.overlay = nil } }
            Text(page.siteOrigin).font(.body.monospaced()).textSelection(.enabled)
            Text(page.currentURL?.absoluteString ?? page.address).font(.callout).textSelection(.enabled)
            Text("Profile: \(page.profile.title)").font(.callout)
            Button("Open in Isolated Browser") { TahoeIsolatedBrowserLink.open(page.currentURL) }
                .buttonStyle(TahoeControlStyle()).disabled(page.currentURL?.scheme != "https")
            Button(TahoeStrings.ui("Copy Full URL")) { UIPasteboard.general.string = page.currentURL?.absoluteString ?? page.address }.buttonStyle(TahoeControlStyle())
            Divider()
            permission("Camera", kind: "camera"); permission("Microphone", kind: "microphone")
            Text(TahoeStrings.ui("These choices apply to this origin and profile. iPadOS permission is still required. Deny mutes current capture and blocks future requests.")).font(.caption).foregroundStyle(.secondary)
            Toggle(TahoeStrings.ui("Keep this tab awake"), isOn: $page.pinned)
            Toggle(TahoeStrings.ui("Exempt this site from tracker blocking"), isOn: Binding(get: { (TahoePreferences.shared.value.contentBlockingExceptions ?? []).contains(page.currentURL?.host ?? "") }, set: { exempt in
                guard let host = page.currentURL?.host else { return }; var exceptions = TahoePreferences.shared.value.contentBlockingExceptions ?? []
                exceptions.removeAll { $0 == host }; if exempt { exceptions.append(host) }; TahoePreferences.shared.value.contentBlockingExceptions = exceptions
            }))
            Button(TahoeStrings.ui("Clear This Site's Stored Data…"), role: .destructive) {
                let origin = page.siteOrigin
                TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Clear Site Data?", message: "Cookies and website storage for \(origin) and its related site records will be removed from \(page.profile.title). This can sign you out. Other profiles are kept.", primary: "Clear", destructive: true, accept: { _ in
                    let store = page.dataStoreForTransfer, host = page.currentURL?.host ?? ""
                    store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                        let matching = records.filter { $0.displayName == host || host.hasSuffix("." + $0.displayName) }
                        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching) { Task { @MainActor in status = "Site data cleared. Reload the page when ready." } }
                    }
                })
            }.buttonStyle(TahoeControlStyle())
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }.padding(22).frame(maxWidth: 480).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 16)).shadow(radius: 24).padding(24)
    }
    private func permission(_ title: String, kind: String) -> some View {
        Picker(title, selection: Binding(get: { page.mediaChoice(kind) }, set: { page.setMediaChoice(kind, value: $0) })) {
            Text(TahoeStrings.ui("Ask")).tag("ask"); Text(TahoeStrings.ui("Allow")).tag("allow"); Text(TahoeStrings.ui("Deny")).tag("deny")
        }.pickerStyle(.segmented)
    }
}
