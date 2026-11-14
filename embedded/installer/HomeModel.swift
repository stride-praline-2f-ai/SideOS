import SwiftUI

@MainActor final class SideInstallerRefreshHistory: ObservableObject {
    static let shared = SideInstallerRefreshHistory()
    @Published private(set) var records: SideInstallerRefreshRecords
    private let file: SideInstallerRefreshRecordFile
    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = SideInstallerRefreshRecordFile(url: directory.appendingPathComponent("SideInstaller/refresh-history.json"))
        self.file = file; records = file.read()
    }
    func reload() { records = file.read() }
    func record(device: String?, app: String?) throws {
        guard let device, !device.isEmpty, let app, !app.isEmpty else { return }
        records = try file.record(device: device, app: app, date: Date())
    }
}

@MainActor final class SideInstallerHomeModel: ObservableObject {
    @Published private(set) var apps: [SideInstallerDeviceApp] = []
    @Published private(set) var loading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var message: String?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var deviceID: String?
    func reload() async {
        guard !loading else { return }
        let engine = Engine.shared
        guard !engine.isRunning, !AppRefreshService.shared.isRefreshing else {
            message = "An install or refresh is running. Check the device again when it finishes."; return
        }
        loading = true; message = nil
        defer { loading = false }
        do {
            let installed = try await engine.homeInstalledApps()
            guard !Task.isCancelled else { return }
            // A malformed record does not hide the other installed apps.
            var unique: [String: SideInstallerDeviceApp] = [:]
            for plist in installed { if let app = SideInstallerDeviceApp(plist: plist) { unique[app.id] = app } }
            apps = unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            deviceID = engine.deviceUDID; hasLoaded = true; checkedAt = Date()
            SideInstallerRefreshHistory.shared.reload()
        } catch is CancellationError { }
        catch {
            message = error.localizedDescription
            engine.log("Home device check: \(error.localizedDescription)")
        }
    }
}
