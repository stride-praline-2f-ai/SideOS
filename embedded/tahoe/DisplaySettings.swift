import SwiftUI

struct TahoeDisplaySettings: View {
    @ObservedObject private var link = TahoeWirelessDisplay.shared
    @EnvironmentObject private var workspace: TahoeWorkspace
    @State private var viewer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Wireless Extended Display", systemImage: "display.2").font(.title2.bold())
            Text("Use another SideOS device as a separate screen over the same local Wi-Fi network. Apps, cookies and files remain on this host. The other device only decodes video; it does not need JIT or its own copy of a hosted app.")
            Text("Experimental: native compilation and automated checks do not establish that every LiveContainer scene can be captured offscreen on your OS. Check the actual app content on the receiver. This is display-only; no remote input or clipboard/file transfer is provided.").font(.caption).foregroundStyle(.secondary)
            if link.hosting {
                Text(link.status).font(.callout).textSelection(.enabled)
                Text("Nearby host: SideOS · " + link.name.suffix(6)).font(.headline)
                if let port = link.port { Text("Manual connection port: \(port)").textSelection(.enabled) }
                Text(link.key).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Button("Copy session pairing key") {
                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: link.key]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                }.buttonStyle(TahoeControlStyle())
                Text("On the other device: Settings → Wireless Display → Use this device as a display. Select this host, enter the key and connect. Allow Local Network access on both. If discovery is blocked, use this device's Wi-Fi IP from iOS Settings and the port above.").font(.caption)
                Button("Stop sharing and return all windows") { link.stop() }.buttonStyle(TahoeControlStyle(variant: .destructive))
            } else {
                Button("Extend this SideOS desktop") { link.start() }.buttonStyle(TahoeControlStyle(variant: .accent))
                Text(link.status).font(.caption).foregroundStyle(.secondary)
                Button("Use this device as a display") { viewer = true }.buttonStyle(TahoeControlStyle())
            }
            if link.connected && workspace.state.wirelessCanvas != nil {
                Text("Windows").font(.headline)
                Text("The selected window fills the second screen. Choose another remote window in the Dock to switch it, or bring one back here to interact with it.").font(.caption)
                ForEach(workspace.state.windows) { window in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(window.title).lineLimit(1)
                            Text(window.onWirelessDisplay == true ? "Wireless display" : "Main display").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(window.onWirelessDisplay == true ? "Bring Back" : "Move to Display") { link.move(window.id, remote: window.onWirelessDisplay != true) }
                            .buttonStyle(TahoeControlStyle(size: .small))
                    }.padding(10).background(TahoeDesign.group, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("Only share with a trusted device. Anyone with the current key can see shared windows. The existing warning about malicious hosted apps and browser data still applies. Keep both apps open; backgrounding, disconnection or capture failure returns windows locally.").font(.caption).foregroundStyle(.secondary)
        }.fullScreenCover(isPresented: $viewer) { TahoeDisplayViewerScreen() }
    }
}
