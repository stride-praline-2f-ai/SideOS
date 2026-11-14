import Foundation

enum IsolationPolicy {
    static let browserID = "com.aault.sideos.browser"
    static let scheme = "sideos-isolated-browser"
    static let canaryDomain = "isolation.sideos.invalid"
    static let canaryService = "SideOSIsolationChecks"
    static let workStoreID = UUID(uuidString: "B10E3F46-B90C-48BD-B62C-B247C0AA1966")!
    static let forbiddenFlags = ["get-task-allow", "com.apple.security.get-task-allow", "task_for_pid-allow",
        "platform-application", "com.apple.system-task-ports", "dynamic-codesigning", "com.apple.security.cs.allow-jit",
        "com.apple.security.cs.disable-library-validation", "com.apple.private.security.no-sandbox", "com.apple.private.security.no-container"]

    static func findings(snapshot: [String: Any]?, bundleID: String, info: [String: Any] = [:]) -> [String] {
        guard let snapshot else { return ["The running process's signed entitlements could not be inspected."] }
        var errors: [String] = []
        let ownID = snapshot["application-identifier"] as? String
        let suffix = bundleID.hasPrefix(browserID + ".") ? String(bundleID.dropFirst(browserID.count + 1)) : ""
        if bundleID != browserID && !(suffix.count == 10 && suffix.allSatisfy({ $0.isUppercase || $0.isNumber })) {
            errors.append("This is not the separately installed SideOS Browser app.")
        }
        if ownID?.hasSuffix("." + bundleID) != true { errors.append("The process identity does not match this browser. Do not run it inside LiveContainer.") }
        for flag in forbiddenFlags {
            if snapshot[flag] as? Bool == true { errors.append("Signing grants \(flag). Re-sign without debug, JIT or sandbox-bypass access.") }
            else if let value = snapshot[flag], !(value is NSNull), value as? Bool == nil { errors.append("The \(flag) entitlement has an unverified format.") }
        }
        if info["UIFileSharingEnabled"] as? Bool == true || info["LSSupportsOpeningDocumentsInPlace"] as? Bool == true {
            errors.append("Private browser files must not be published through file sharing.")
        }
        let ats = info["NSAppTransportSecurity"] as? [String: Any] ?? [:]
        if ats["NSAllowsArbitraryLoads"] as? Bool == true || ats["NSAllowsArbitraryLoadsInWebContent"] as? Bool == true {
            errors.append("This app's network policy was weakened during signing or packaging.")
        }
        if let groups = snapshot["com.apple.security.application-groups"], !(groups is NSNull) {
            guard let groups = groups as? [String] else { return errors + ["App-group entitlement format could not be verified."] }
            if !groups.isEmpty { errors.append("This signature shares an app group. Re-sign without shared app groups.") }
        }
        if let groups = snapshot["keychain-access-groups"], !(groups is NSNull) {
            guard let groups = groups as? [String], let ownID else { return errors + ["Keychain entitlement format could not be verified."] }
            if groups.contains(where: { $0 != ownID }) { errors.append("This signature grants a shared or wildcard keychain group. Keep only this app's own group.") }
        }
        return errors
    }

    static func webURL(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 8192, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return false }
        return parts.port.map { (1...65535).contains($0) } ?? true
    }
    static func handoff(_ url: URL) -> URL? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
              parts.host == "open", parts.path.isEmpty || parts.path == "/", parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "url",
              let value = items[0].value, let target = URL(string: value), webURL(target) else { return nil }
        return target
    }
}

struct IsolationChallenge: Codable, Equatable {
    let version: Int
    let id: UUID
    let cookieName: String
    let filePath: String
    let keychainGroup: String
    let browserPID: Int32
    let created: Date
    func validate(now: Date = Date()) -> Bool {
        let path = URL(fileURLWithPath: filePath)
        return version == 1 && cookieName == "sideos_canary_" + id.uuidString && browserPID > 0 &&
            now.timeIntervalSince(created) >= -60 && now.timeIntervalSince(created) < 1800 &&
            path.lastPathComponent == id.uuidString + ".canary" && path.deletingLastPathComponent().lastPathComponent == "SideOSIsolationChecks" &&
            (filePath.hasPrefix("/var/mobile/Containers/Data/Application/") || filePath.hasPrefix("/private/var/mobile/Containers/Data/Application/")) &&
            !filePath.contains("/../") && !filePath.contains("/./") && !keychainGroup.isEmpty && !keychainGroup.contains("*")
    }
}

struct IsolationProbeResult: Codable {
    let challenge: IsolationChallenge
    let probePID: Int32
    let fileStatus: Int32
    let keychainStatus: Int32
    let taskStatus: Int32
    let ownProcessControl: Bool
    let ownFileControl: Bool
    let ownCookieControl: Bool
    let ownKeychainControl: Bool
    let foundCanary: Bool
    let notes: [String]
    var assessment: String {
        if foundCanary || fileStatus == 0 || keychainStatus == 0 || taskStatus == 0 { return "ISOLATION FAILURE: another process obtained a protected test resource." }
        let deniedFile = fileStatus == 1 || fileStatus == 13 // EPERM or EACCES, not merely a missing file.
        let deniedKeychain = keychainStatus == -34018 // errSecMissingEntitlement; item-not-found alone is inconclusive.
        if deniedFile && deniedKeychain && ownProcessControl && ownFileControl && ownCookieControl && ownKeychainControl {
            return "The tested access attempts were denied. This is evidence for these paths on this device, not proof against every attack."
        }
        return "INCONCLUSIVE: a positive control failed, or the result did not establish a sandbox denial."
    }
}
