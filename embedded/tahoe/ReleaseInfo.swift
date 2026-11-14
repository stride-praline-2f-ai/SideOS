import SwiftUI

enum TahoeReleaseInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local" }
    static var revision: String { Bundle.main.object(forInfoDictionaryKey: "SIEmbeddedSourceRevision") as? String ?? "local" }
    static var runtimeLabel: String {
        let release = Bundle.main.object(forInfoDictionaryKey: "SILiveContainerRelease") as? String ?? "development"
        let revision = Bundle.main.object(forInfoDictionaryKey: "SILiveContainerRevision") as? String ?? "unknown"
        return "LiveContainer \(release) · \(revision.prefix(8))"
    }
    static var label: String { "SideOS \(version) · Build \(build) · \(revision.prefix(8))" }
    static var repository: String { Bundle.main.object(forInfoDictionaryKey: "SIEmbeddedSourceRepository") as? String ?? "stride-praline-2f-ai/SideOS" }
    static var buildsURL: URL { URL(string: "https://github.com/\(repository)/actions/workflows/private-build.yml")! }
    static var releasesURL: URL { URL(string: "https://github.com/\(repository)/releases")! }
    @MainActor static func diagnostics() -> String {
        let workspace = TahoeWorkspace.shared
        let pages = workspace.browsers.values.flatMap(\.tabs)
        let runtime = pages.flatMap { $0.chatWorkspace.map { Array($0.pages.values) } ?? [$0] }
        return """
        \(label)
        Device: \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        \(runtimeLabel)
        \(TahoeDisplayMetrics.shared.diagnostics)
        Physical memory: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MiB
        Windows: \(workspace.state.windows.count)
        Browser tabs: \(pages.count)
        Resident pages: \(runtime.filter { $0.webView != nil }.count)
        Sleeping pages: \(runtime.filter(\.isSleeping).count)
        Active downloads: \(TahoeDownloads.shared.items.filter(\.active).count)
        Hosted windows: \(workspace.guests.count)
        Thermal state: \(ProcessInfo.processInfo.thermalState.rawValue)
        Low power: \(ProcessInfo.processInfo.isLowPowerModeEnabled)
        This report excludes credentials, cookies, URLs, titles and chat contents.
        
        \(TahoePerformanceCapture.shared.report)
        """
    }
    @MainActor static func showDiagnostics() {
        let report = diagnostics()
        TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Diagnostics", message: report,
            primary: "Copy Report", cancel: "Done", accept: { _ in UIPasteboard.general.string = report })
    }
}
