import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main struct InstallerHomeDataTests {
    static func main() throws {
        func app(_ id: String, memory: Bool? = nil, sideloaded: Bool = true, plugins: Any? = nil) -> SideInstallerDeviceApp {
            var entitlements: [String: Any] = ["application-identifier": "ABCDE12345." + id]
            if let memory { entitlements["com.apple.developer.kernel.increased-memory-limit"] = memory }
            var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleDisplayName": "Test App", "Entitlements": entitlements]
            if sideloaded { plist["ProfileValidated"] = true }
            if let plugins { plist["PlugInKitPlugins"] = plugins }
            return SideInstallerDeviceApp(plist: plist)!
        }
        precondition(app("com.example.memory", memory: true).increasedMemory)
        precondition(!app("com.example.normal", memory: false).increasedMemory)
        precondition(!app("com.example.unknown").increasedMemory)
        let portalOnly = SideInstallerDeviceApp(plist: ["CFBundleIdentifier": "com.example.portal", "INCREASED_MEMORY_LIMIT": true])!
        precondition(!portalOnly.increasedMemory, "Only the installed signature's entitlement enables the badge")
        precondition(!app("com.example.store", sideloaded: false).isSideloaded)
        precondition(SideInstallerDeviceApp(plist: [:]) == nil)

        let main = app("com.example.app", plugins: ["widget": ["CFBundleIdentifier": "com.example.app.widget"]])
        precondition(main.extensionIDs == ["com.example.app.widget"])
        let other = app("com.example.app.other")
        let sibling = app("com.example.apple")
        let ids = [main.id, "com.example.app.widget", "com.example.app.widget", other.id, "com.example.app.other.widget", sibling.id, "unassigned.registration"]
        let counts = SideInstallerAppIDAttribution.counts(apps: [main, other, sibling], registered: ids)
        precondition(counts[main.id] == 2 && counts[other.id] == 2 && counts[sibling.id] == 1)
        precondition(counts.values.reduce(0, +) == 5, "Duplicate and unrelated registrations must not inflate per-app totals")
        precondition(SideInstallerAppIDAttribution.counts(apps: [main], registered: [])[main.id] == 0)
        let detachedExtension = app("org.example.owner", plugins: [["CFBundleIdentifier": "com.example.app.detached"]])
        let owned = SideInstallerAppIDAttribution.counts(apps: [main, detachedExtension], registered: ["com.example.app.detached"])
        precondition(owned[detachedExtension.id] == 1 && owned[main.id] == 0,
                     "Explicit installed extension ownership takes priority over a namespace match")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("installer-home-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = SideInstallerRefreshRecordFile(url: directory.appendingPathComponent("history.json"))
        precondition(file.read().lastRefresh(device: "device-a", app: main.id) == nil)
        let first = Date(timeIntervalSince1970: 1000), second = Date(timeIntervalSince1970: 2000)
        try file.record(device: "device-a", app: main.id, date: first)
        try file.record(device: "device-b", app: main.id, date: second)
        let reopened = file.read()
        precondition(reopened.lastRefresh(device: "device-a", app: main.id) == first)
        precondition(reopened.latest(device: "device-b") == second)
        precondition(reopened.lastRefresh(device: "device-a", app: other.id) == nil)
        try file.record(device: "device-a", app: main.id, date: .distantPast)
        precondition(file.read().lastRefresh(device: "device-a", app: main.id) == first)
        try Data("corrupt".utf8).write(to: file.url)
        precondition(file.read() == reopened, "A corrupt latest file falls back to a valid previous history")

        let lock = directory.appendingPathComponent("operation.lock")
        let initiallyIdle = try TahoeInstallerOperation.isIdle(at: lock)
        precondition(initiallyIdle)
        let descriptor = open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        precondition(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        let busy = try TahoeInstallerOperation.isIdle(at: lock)
        precondition(!busy, "A running install's lease blocks closing SideInstaller")
        flock(descriptor, LOCK_UN); close(descriptor)
        let idle = try TahoeInstallerOperation.isIdle(at: lock)
        precondition(idle)

        var windows = TahoeWindowState()
        let id = windows.open(.installer, title: "SideInstaller")
        windows.minimize(id); windows.focus(id)
        let snapshot = try JSONEncoder().encode(windows.windows)
        let restored = try JSONDecoder().decode([TahoeWindow].self, from: snapshot)
        precondition(restored.first?.kind == .installer && restored.first?.minimized == false)
        print("Installer home: signed memory evidence, App ID attribution, device-bound durable refresh history, busy close protection and window restoration passed")
    }
}
