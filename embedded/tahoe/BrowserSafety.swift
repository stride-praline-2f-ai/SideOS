import SwiftUI

enum TahoeBrowserSafety {
    static let height: CGFloat = 44
    static let title = "Browser security warning"
    static let compact = "Don’t save sensitive details here. Malicious LiveContainer apps may access browser data."
    static let message = "The embedded browser is not sandboxed away from hosted LiveContainer apps. Malicious hosted apps may access browser cookies, signed-in sessions and saved data. Do not store passwords, payment details or other sensitive information here. Use Safari or another trusted, separately sandboxed browser for sensitive activity."
    static let hostWarning = "Only run hosted apps you trust. SideOS does not isolate malicious hosted code from browser sessions, signing credentials, pairing records or permissions granted to the host. Use a trusted separate browser for sensitive activity. Signing and pairing inside this host are not a secure vault."
}

struct TahoeBrowserSafetyBanner: View {
    @EnvironmentObject private var workspace: TahoeWorkspace
    var body: some View {
        Button { workspace.openTools("Security") } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                Text(TahoeBrowserSafety.compact).font(.system(size: 11, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }.padding(.horizontal, 12).frame(height: TahoeBrowserSafety.height)
                .background(TahoeDesign.window).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle(scale: 1)).foregroundStyle(.primary)
            .accessibilityLabel(TahoeBrowserSafety.message).accessibilityHint("Open browser safety guidance")
            .accessibilityIdentifier("browser-safety-warning")
    }
}

struct TahoeBrowserSafetyCard: View {
    let acknowledge: () -> Void
    @EnvironmentObject private var workspace: TahoeWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(TahoeBrowserSafety.title, systemImage: "exclamationmark.shield.fill").font(.headline).foregroundStyle(.orange)
            Text(TahoeBrowserSafety.hostWarning).font(.callout)
            HStack {
                Button("Read safety guidance") { acknowledge(); workspace.openTools("Security") }.buttonStyle(TahoeControlStyle())
                Button("Understood", action: acknowledge).buttonStyle(TahoeControlStyle(variant: .accent))
            }.tahoeGlassGroup()
        }.padding(16).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.5), lineWidth: 1) }
    }
}

struct TahoeBrowserSafetyGuide: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(TahoeBrowserSafety.title, systemImage: "exclamationmark.shield.fill").font(.title2.bold()).foregroundStyle(.orange)
                Text(TahoeBrowserSafety.message)
                Text("Signing and pairing share the host’s trust boundary").font(.headline)
                Text(TahoeBrowserSafety.hostWarning)
                Text("Browser profiles are not a sandbox boundary").font(.headline)
                Text("Personal, Work and Private separate website stores or restoration behaviour. They do not guarantee protection against a malicious app running inside this host. Private mode does not solve this threat.")
                Text("Keep sensitive activity in a trusted separate browser").font(.headline)
                Text("Do not save banking, passwords, payment information, identity documents or confidential work here. Closing or clearing a tab does not prove a malicious guest has not already read data. Only install hosted apps you trust.")
                Link("Security and privacy documentation", destination: URL(string: "https://github.com/stride-praline-2f-ai/SideOS/blob/main/SECURITY.md")!)
            }.padding(24)
        }
    }
}
