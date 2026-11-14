import Foundation

/// Website-facing identity only. This never changes the iPad's actual OS,
/// browser engine, storage partition, network route or permission decisions.
enum TahoeWebsiteIdentity: String, Codable, CaseIterable {
    case ipadOriginal
    case macOSSafari
    case macOSEnhanced

    var title: String {
        switch self {
        case .ipadOriginal: return "iPadOS Original"
        case .macOSSafari: return "macOS Safari"
        case .macOSEnhanced: return "macOS Enhanced Spoofing"
        }
    }

    var isMacOS: Bool { self != .ipadOriginal }

    static func macSafariUserAgent(systemMajor: Int, systemMinor: Int) -> String {
        let major = max(17, systemMajor)
        let minor = max(0, systemMinor)
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).\(minor) Safari/605.1.15"
    }

    /// Limited, explicit spoofing: avoid rewriting WebKit, screen, canvas,
    /// hardware, permissions or authentication surfaces. Subframes are covered
    /// by the WKUserScript's forMainFrameOnly=false setting.
    var enhancedScript: String? {
        guard self == .macOSEnhanced else { return nil }
        return #"""
        (() => {
          "use strict";
          const prototype = Object.getPrototypeOf(navigator);
          for (const [key, value] of Object.entries({ platform: "MacIntel", maxTouchPoints: 0 })) {
            try {
              Object.defineProperty(prototype, key, { configurable: true, get: () => value });
            } catch (_) {
              try { Object.defineProperty(navigator, key, { configurable: true, get: () => value }); }
              catch (_) { /* Read-only properties remain unchanged. */ }
            }
          }
        })();
        """#
    }
}
