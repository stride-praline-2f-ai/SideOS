import Foundation

enum TahoeSearchProvider: String, Codable, CaseIterable {
    case google, duckDuckGo, bing
    var title: String { switch self { case .google: return "Google"; case .duckDuckGo: return "DuckDuckGo"; case .bing: return "Bing" } }
    var endpoint: String { switch self { case .google: return "https://www.google.com/search"; case .duckDuckGo: return "https://duckduckgo.com/"; case .bing: return "https://www.bing.com/search" } }
}

enum TahoeAddress {
    /// Script-created blank windows are used by sign-in and document workflows.
    /// WebKit supplies their configuration and retains origin/security handling.
    static func allowsPopup(_ url: URL) -> Bool {
        TahoeStorage.isWebURL(url) || url.absoluteString == "about:blank"
    }
    static func url(for input: String, provider: TahoeSearchProvider = .google) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return url }
        if text.contains("://") { return nil }
        if !text.contains(where: { $0.isWhitespace }),
           let local = URLComponents(string: "http://" + text), let host = local.host,
           host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "[::1]" || host == "::1" || local.port != nil {
            guard local.user == nil, local.password == nil, local.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
            return local.url
        }
        // A hostname followed by a numeric port can resemble a URI scheme.
        // Everything else with an explicit non-web scheme stays out of WebKit.
        if let scheme = URLComponents(string: text)?.scheme, !scheme.contains(".") { return nil }
        if !text.contains(where: { $0.isWhitespace }), text.contains("."),
           let url = URL(string: "https://" + text), url.host != nil { return url }
        var search = URLComponents(string: provider.endpoint)!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }
}
