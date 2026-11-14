import Foundation

enum TahoeApplicationIdentity: Hashable, Sendable {
    case builtIn(TahoeWindowKind)
    case webApp(URL)
    case installed(String)
    var key: String {
        switch self {
        case .builtIn(let kind): return kind.rawValue
        case .webApp(let url): return "web-" + url.absoluteString
        case .installed(let path): return "guest-" + path
        }
    }
}
extension TahoeWindow {
    var applicationIdentity: TahoeApplicationIdentity {
        if kind == .guest { return .installed(applicationID ?? resourceID ?? id.uuidString) }
        if isWebApp, let resourceID, let url = URL(string: resourceID) { return .webApp(url) }
        return .builtIn(kind)
    }
}
