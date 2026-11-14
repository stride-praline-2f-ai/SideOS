import SwiftUI

@MainActor enum TahoeIsolatedBrowserLink {
    static func open(_ page: URL? = nil) {
        let target = page ?? URL(string: "https://duckduckgo.com")!
        guard let parts = URLComponents(url: target, resolvingAgainstBaseURL: false), parts.scheme == "https",
              parts.host != nil, parts.user == nil, parts.password == nil else {
            TahoeWorkspace.shared.error = "The isolated browser accepts HTTPS websites without embedded usernames or passwords."
            return
        }
        var request = URLComponents(); request.scheme = "sideos-isolated-browser"; request.host = "open"
        request.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        guard let url = request.url else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { Task { @MainActor in
                TahoeWorkspace.shared.error = "Install SideOSBrowser from the device IPA artifact as a separate app, then open this link again. Cookies are kept in that app and are not copied from SideOS."
            } }
        }
    }
}
