import SwiftUI

enum TahoeInstallerRuntime {
    static let bundle = "builtinSideStore" // The pinned runtime's built-in app routing ID.
    static let container = "sideos-builtin-sideinstaller"
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SideInstaller", isDirectory: true)
    }
    /// The installer already holds this OS lease during install/refresh. A
    /// window close must not kill its process halfway through an operation.
    static func canClose() throws -> Bool {
        let file = directory.appendingPathComponent("Library/Caches/SideInstaller-operation.lock")
        return try TahoeInstallerOperation.isIdle(at: file)
    }
}

struct TahoeInstallerWindow: View {
    @ObservedObject var workspace: TahoeWorkspace
    let windowID: UUID
    @State private var startRequested = false
    private var visible: Bool { workspace.state.windows.first(where: { $0.id == windowID }).map(workspace.state.isVisible) ?? false }
    var body: some View {
        Group {
            if startRequested, let session = workspace.guests[windowID], session.controller != nil || !workspace.launching {
                TahoeGuestView(session: session, windowID: windowID)
                    .overlay(alignment: .bottom) {
                        if session.terminated {
                            Button("Reopen SideInstaller") { workspace.openInstaller() }
                                .buttonStyle(TahoeControlStyle()).padding(16)
                        }
                    }
            } else {
                VStack(spacing: 12) { ProgressView(); Text(workspace.launching ? "Waiting for the current app launch…" : "Opening SideInstaller…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: visible, initial: true) { _, value in if value && !workspace.launching { startRequested = true } }
        .onChange(of: workspace.launching) { _, launching in if !launching && visible { startRequested = true } }
    }
}
