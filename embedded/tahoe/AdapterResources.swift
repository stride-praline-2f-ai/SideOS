import SwiftUI
import CryptoKit

/// Optional, owner-configured resource updates. The pinned public key verifies
/// the exact payload; native code, capabilities and bridge policy stay in IPA.
/// With no configured key/feed, the bundled adapter is always authoritative.
@MainActor final class TahoeAdapterResources: ObservableObject {
    static let shared = TahoeAdapterResources()
    @Published private(set) var status = "Bundled ChatGPT adapter"
    @Published private(set) var checking = false
    private var installed: TahoeAdapterPayload?
    private var key: String { TahoePreferences.shared.value.adapterPublicKey ?? "" }
    private var file: URL { TahoeStorage.root.appendingPathComponent("chat-adapter.signed.json") }
    init() { reloadCache() }
    var script: String {
        let source = installed?.script ?? TahoeChatGPTPageScript.source
        return "if(window.top===window&&location.protocol==='https:'&&location.hostname==='chatgpt.com'&&(!location.port||location.port==='443')){\n" + source + "\n}"
    }
    private func verified(_ data: Data) throws -> TahoeAdapterPayload {
        try TahoeAdapterSignature.verify(data, publicKey: key, hostVersion: TahoeReleaseInfo.version)
    }
    func reloadCache() {
        installed = nil
        if let data = try? Data(contentsOf: file), let payload = try? verified(data) { installed = payload; status = "Verified ChatGPT adapter v\(payload.version)" }
        else { status = "Bundled ChatGPT adapter" }
    }
    func check() {
        guard !checking else { return }
        guard let url = URL(string: TahoePreferences.shared.value.adapterFeed ?? ""), url.scheme == "https", url.user == nil, url.password == nil, url.query == nil else { status = "Configure a public HTTPS signed-adapter feed without credentials or query tokens first."; return }
        checking = true
        Task {
            defer { checking = false }
            do {
                let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 15
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (temporary, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 524_288 else { throw failure("The adapter feed did not return a valid update.") }
                let data = try Data(contentsOf: temporary), payload = try verified(data)
                guard payload.version > (installed?.version ?? 0) else { status = "Already using the latest verified adapter."; return }
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let previous = try? Data(contentsOf: file), (try? verified(previous)) != nil { try previous.write(to: file.appendingPathExtension("previous"), options: .atomic) }
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                installed = payload; status = "Verified adapter v\(payload.version) installed. New pages use it; Apply updates open ChatGPT controls."
            } catch { status = error.localizedDescription }
        }
    }
    func apply() {
        let script = script
        for root in TahoeWorkspace.shared.browsers.values.flatMap(\.tabs) {
            let pages = root.chatWorkspace.map { Array($0.pages.values) } ?? [root]
            for page in pages where page.currentURL.map(TahoeChatWorkspaceState.allows) == true {
                page.updateAdapterScript(script)
            }
        }
    }
    func useBundled() {
        installed = nil
        do { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
        catch { status = error.localizedDescription; return }
        status = "Bundled ChatGPT adapter"; apply()
    }
    func rollback() {
        guard let data = try? Data(contentsOf: file.appendingPathExtension("previous")), let payload = try? verified(data) else { useBundled(); return }
        do { try data.write(to: file, options: .atomic); installed = payload; status = "Rolled back to adapter v\(payload.version)"; apply() }
        catch { status = error.localizedDescription }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "SideOS.Adapter", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

struct TahoeAdapterUpdateSettings: View {
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var resources = TahoeAdapterResources.shared
    var body: some View {
        DisclosureGroup("Advanced: Signed ChatGPT Adapter Updates") {
            VStack(alignment: .leading, spacing: 10) {
                Text(TahoeStrings.ui("Optional. Configure only a feed and public key supplied by the app owner. Updates affect ChatGPT page controls; native changes still require an IPA. No GitHub token is used.")).font(.caption).foregroundStyle(.secondary)
                TextField(TahoeStrings.ui("HTTPS feed URL"), text: Binding(get: { preferences.value.adapterFeed ?? "" }, set: { preferences.value.adapterFeed = $0 })).textInputAutocapitalization(.never).autocorrectionDisabled().tahoeField()
                TextField(TahoeStrings.ui("Owner Ed25519 public key (base64)"), text: Binding(get: { preferences.value.adapterPublicKey ?? "" }, set: { preferences.value.adapterPublicKey = $0; resources.reloadCache() })).textInputAutocapitalization(.never).autocorrectionDisabled().tahoeField()
                Text(resources.status).font(.caption).textSelection(.enabled)
                HStack {
                    Button(resources.checking ? "Checking…" : "Check Adapter") { resources.check() }.disabled(resources.checking)
                    Button(TahoeStrings.ui("Apply")) { resources.apply() }
                    Button(TahoeStrings.ui("Roll Back")) { resources.rollback() }
                    Button(TahoeStrings.ui("Use Bundled Adapter")) { resources.useBundled() }
                }.buttonStyle(TahoeControlStyle())
            }.padding(.top, 8)
        }
    }
}
