import SwiftUI

struct TahoeWindowContent: View {
    let window: TahoeWindow
    @ObservedObject var workspace: TahoeWorkspace
    @ViewBuilder var body: some View {
        switch window.kind {
        case .browser: if let session = workspace.browsers[window.id] { TahoeBrowserView(session: session, windowID: window.id) }
        case .guest: if let session = workspace.guests[window.id] { TahoeGuestView(session: session, windowID: window.id) }
        case .installer: TahoeInstallerWindow(workspace: workspace, windowID: window.id)
        case .livecontainer: TahoeManagementWindow()
        case .applications: TahoeApplicationsView(workspace: workspace)
        case .files: TahoeFilesView(windowID: window.id)
        case .settings: TahoeSettingsView()
        case .notes: Color.clear.onAppear { workspace.close(window.id); workspace.open(.notes) }
        case .calculator: Color.clear.onAppear { workspace.close(window.id); workspace.open(.calculator) }
        case .downloads: TahoeDownloadsView()
        case .utilities: TahoeWorkspaceTools(workspace: workspace)
        }
    }
}
