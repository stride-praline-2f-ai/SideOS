import Foundation
@main struct PolicyTests {
    static func main() {
        let aid = "ABCDE12345." + IsolationPolicy.browserID
        let valid: [String: Any] = ["application-identifier": aid, "keychain-access-groups": [aid], "get-task-allow": false]
        precondition(IsolationPolicy.findings(snapshot: valid, bundleID: IsolationPolicy.browserID).isEmpty)
        precondition(!IsolationPolicy.findings(snapshot: nil, bundleID: IsolationPolicy.browserID).isEmpty)
        for info: [String: Any] in [["UIFileSharingEnabled": true], ["NSAppTransportSecurity": ["NSAllowsArbitraryLoadsInWebContent": true]]] {
            precondition(!IsolationPolicy.findings(snapshot: valid, bundleID: IsolationPolicy.browserID, info: info).isEmpty)
        }
        for key in IsolationPolicy.forbiddenFlags {
            var bad = valid; bad[key] = true
            precondition(!IsolationPolicy.findings(snapshot: bad, bundleID: IsolationPolicy.browserID).isEmpty)
        }
        for groups in [["ABCDE12345.*"], ["ABCDE12345.com.aault.livecontainer.sideinstaller"], [aid, "shared"]] {
            var bad = valid; bad["keychain-access-groups"] = groups
            precondition(!IsolationPolicy.findings(snapshot: bad, bundleID: IsolationPolicy.browserID).isEmpty)
        }
        var shared = valid; shared["com.apple.security.application-groups"] = ["group.host"]
        precondition(!IsolationPolicy.findings(snapshot: shared, bundleID: IsolationPolicy.browserID).isEmpty)
        precondition(!IsolationPolicy.findings(snapshot: valid, bundleID: "com.aault.livecontainer.sideinstaller").isEmpty)
        for bad in ["http://bank.example", "file:///cookies", "javascript:alert(1)", "https://user:password@example.com", "https://example.com:0"] { precondition(!IsolationPolicy.webURL(URL(string: bad)!)) }
        let target = URL(string: "https://chatgpt.com/c/123")!
        var handoff = URLComponents(); handoff.scheme = IsolationPolicy.scheme; handoff.host = "open"; handoff.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        precondition(IsolationPolicy.handoff(handoff.url!) == target)
        handoff.queryItems!.append(URLQueryItem(name: "callback", value: "https://evil.example"))
        precondition(IsolationPolicy.handoff(handoff.url!) == nil)
        let id = UUID(); let challenge = IsolationChallenge(version: 1, id: id, cookieName: "sideos_canary_" + id.uuidString,
            filePath: "/private/var/mobile/Containers/Data/Application/ABC/Library/Application Support/SideOSIsolationChecks/\(id.uuidString).canary", keychainGroup: aid, browserPID: 42, created: Date())
        precondition(challenge.validate())
        precondition(!challenge.validate(now: Date().addingTimeInterval(1900)))
        func result(file: Int32 = 13, keychain: Int32 = -34018, task: Int32 = 5, found: Bool = false) -> IsolationProbeResult {
            IsolationProbeResult(challenge: challenge, probePID: 50, fileStatus: file, keychainStatus: keychain, taskStatus: task,
                ownProcessControl: true, ownFileControl: true, ownCookieControl: true, ownKeychainControl: true, foundCanary: found, notes: [])
        }
        precondition(result().assessment.contains("not proof"))
        precondition(result(file: 2).assessment.hasPrefix("INCONCLUSIVE"))
        precondition(result(keychain: -25300).assessment.hasPrefix("INCONCLUSIVE"))
        precondition(result(found: true).assessment.hasPrefix("ISOLATION FAILURE"))
        precondition(result(task: 0).assessment.hasPrefix("ISOLATION FAILURE"))
        print("Browser isolation policy: fail-closed process identity/entitlements, HTTPS-only handoff, bounded canary challenges and honest probe outcomes passed.")
    }
}
