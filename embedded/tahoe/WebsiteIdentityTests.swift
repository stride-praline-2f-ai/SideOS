import Foundation

@main
struct TahoeWebsiteIdentityTests {
    static func main() throws {
        let modes = TahoeWebsiteIdentity.allCases
        precondition(modes.count == 3)
        precondition(modes.map(\.title) == ["iPadOS Original", "macOS Safari", "macOS Enhanced Spoofing"])
        precondition(!TahoeWebsiteIdentity.ipadOriginal.isMacOS)
        precondition(TahoeWebsiteIdentity.macOSSafari.isMacOS)
        precondition(TahoeWebsiteIdentity.macOSEnhanced.isMacOS)
        precondition(TahoeWebsiteIdentity.ipadOriginal.enhancedScript == nil)
        precondition(TahoeWebsiteIdentity.macOSSafari.enhancedScript == nil)
        guard let script = TahoeWebsiteIdentity.macOSEnhanced.enhancedScript else {
            throw NSError(domain: "TahoeWebsiteIdentity", code: 1)
        }
        precondition(script.contains("maxTouchPoints: 0"))
        precondition(script.contains("platform: \"MacIntel\""))
        let agent = TahoeWebsiteIdentity.macSafariUserAgent(systemMajor: 27, systemMinor: 2)
        precondition(agent.contains("Macintosh; Intel Mac OS X 10_15_7"))
        precondition(agent.contains("Version/27.2 Safari/605.1.15"))
        precondition(!agent.contains("iPad"))
        let decoded = try JSONDecoder().decode([TahoeWebsiteIdentity].self, from: JSONEncoder().encode(modes))
        precondition(decoded == modes)
        print("Website identity checks passed")
    }
}
