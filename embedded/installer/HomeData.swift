import Foundation

/// Device evidence only. A capability enabled on Apple's portal does not prove
/// that the installed executable was signed with that entitlement.
struct SideInstallerDeviceApp: Identifiable, Equatable {
    let id: String
    let name: String
    let version: String?
    let applicationID: String?
    let extensionIDs: Set<String>
    let isSideloaded: Bool
    let increasedMemory: Bool

    init?(plist: [String: Any]) {
        guard let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        self.id = id
        let display = plist["CFBundleDisplayName"] as? String
        let bundle = plist["CFBundleName"] as? String
        name = display?.isEmpty == false ? display! : bundle?.isEmpty == false ? bundle! : id
        version = plist["CFBundleShortVersionString"] as? String
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        applicationID = (entitlements["application-identifier"] as? String).flatMap { value in
            guard let dot = value.firstIndex(of: ".") else { return nil }
            return String(value[value.index(after: dot)...])
        }
        isSideloaded = plist["ProfileValidated"] != nil
        increasedMemory = entitlements["com.apple.developer.kernel.increased-memory-limit"] as? Bool == true
        var plugins = Set<String>()
        func collect(_ value: Any) {
            if let entries = value as? [Any] { entries.forEach(collect) }
            if let entry = value as? [String: Any] {
                if let id = entry["CFBundleIdentifier"] as? String { plugins.insert(id) }
                for (key, value) in entry where key != "Entitlements" {
                    if value is [String: Any] || value is [Any] { collect(value) }
                }
            }
        }
        for key in ["PlugInKitPlugins", "AppExtensions"] { if let value = plist[key] { collect(value) } }
        extensionIDs = plugins
    }
}

enum SideInstallerAppIDAttribution {
    /// Each registration is counted once. Explicit device IDs win; otherwise
    /// assign a registered extension to the longest installed bundle prefix.
    /// This avoids charging com.example.app.other to com.example.app as well.
    static func counts(apps: [SideInstallerDeviceApp], registered: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for app in apps { result[app.id] = 0 }
        for id in Set(registered) {
            let exact = apps.filter { $0.id == id || $0.applicationID == id || $0.extensionIDs.contains(id) }
            let candidates = exact.isEmpty ? apps.filter { app in
                [app.id, app.applicationID].compactMap { $0 }.contains { id.hasPrefix($0 + ".") }
            } : exact
            let owner = candidates.sorted { a, b in
                let aExact = a.id == id || a.applicationID == id
                let bExact = b.id == id || b.applicationID == id
                if aExact != bExact { return aExact }
                if a.id.count != b.id.count { return a.id.count > b.id.count }
                return a.id < b.id
            }.first
            if let owner { result[owner.id, default: 0] += 1 }
        }
        return result
    }
}

struct SideInstallerRefreshRecords: Codable, Equatable {
    var devices: [String: [String: Date]] = [:]
    func lastRefresh(device: String, app: String) -> Date? { devices[device]?[app] }
    func latest(device: String) -> Date? { devices[device]?.values.max() }
    mutating func record(device: String, app: String, date: Date) {
        guard !device.isEmpty, !app.isEmpty else { return }
        let old = devices[device]?[app] ?? .distantPast
        devices[device, default: [:]][app] = max(old, date)
    }
}

struct SideInstallerRefreshRecordFile {
    let url: URL
    func read() -> SideInstallerRefreshRecords {
        for candidate in [url, url.appendingPathExtension("previous")] {
            if let data = try? Data(contentsOf: candidate),
               let value = try? JSONDecoder().decode(SideInstallerRefreshRecords.self, from: data) { return value }
        }
        return SideInstallerRefreshRecords()
    }
    @discardableResult func record(device: String, app: String, date: Date) throws -> SideInstallerRefreshRecords {
        var snapshot = read(); snapshot.record(device: device, app: app, date: date)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = try? Data(contentsOf: url), (try? JSONDecoder().decode(SideInstallerRefreshRecords.self, from: previous)) != nil {
            try previous.write(to: url.appendingPathExtension("previous"), options: .atomic)
        }
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        return snapshot
    }
}
