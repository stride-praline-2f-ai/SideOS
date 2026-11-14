import SwiftUI
import Security
import WebKit
import Darwin

@MainActor final class BrowserCanaries: ObservableObject {
    @Published private(set) var challenge: IsolationChallenge?
    @Published private(set) var status = "Run this with synthetic test data before using real logins."
    @Published private(set) var working = false
    private var store: WKWebsiteDataStore { .default() }
    private var workStore: WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: IsolationPolicy.workStoreID) }
    var challengeJSON: String { challenge.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func start(applicationID: String) async {
        guard !working else { return }; working = true
        defer { working = false }
        await clear()
        do {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw checkError("Random test data could not be generated.") }
            let secret = Data(bytes)
            let id = UUID(), name = "sideos_canary_" + id.uuidString
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SideOSIsolationChecks")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Only this dedicated diagnostic folder is cleaned; browser data is never touched.
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "canary" {
                try? FileManager.default.removeItem(at: file)
            }
            let file = folder.appendingPathComponent(id.uuidString + ".canary")
            try secret.write(to: file, options: [.atomic, .completeFileProtection])
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: IsolationPolicy.canaryService,
                kSecAttrAccessGroup as String: applicationID] as CFDictionary)
            let challenge = IsolationChallenge(version: 1, id: id, cookieName: name, filePath: file.path,
                keychainGroup: applicationID, browserPID: getpid(), created: Date())
            self.challenge = challenge
            let keyStatus = SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: IsolationPolicy.canaryService,
                kSecAttrAccount as String: name, kSecAttrAccessGroup as String: applicationID, kSecValueData as String: secret,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary, nil)
            guard keyStatus == errSecSuccess else { throw checkError("Canary keychain write failed (\(keyStatus)).") }
            guard let cookie = HTTPCookie(properties: [.domain: IsolationPolicy.canaryDomain, .path: "/", .name: name,
                .value: secret.base64EncodedString(), .secure: "TRUE", .expires: Date().addingTimeInterval(1800), HTTPCookiePropertyKey("HttpOnly"): "TRUE"]) else { throw checkError("Test cookie creation failed.") }
            await set(cookie, on: store); await set(cookie, on: workStore)
            let ownFile = try Data(contentsOf: file) == secret
            let ownKey = SecItemCopyMatching(keyQuery(challenge) as CFDictionary, nil) == errSecSuccess
            let ownCookie = await cookies(store).contains { $0.name == name && $0.value == secret.base64EncodedString() }
            let ownWorkCookie = await cookies(workStore).contains { $0.name == name && $0.value == secret.base64EncodedString() }
            guard ownFile && ownKey && ownCookie && ownWorkCookie else { throw checkError("A browser positive control failed; the isolation test is inconclusive.") }
            status = "Synthetic file, private keychain item, and Personal/Work cookies are live. Keep this app open beside SideOS, copy the challenge to Isolation Probe, and run it as a hosted app. Test each launch mode you use."
        } catch { status = error.localizedDescription; await clear(keepStatus: true) }
    }
    func clear(keepStatus: Bool = false) async {
        guard let challenge else { return }
        try? FileManager.default.removeItem(atPath: challenge.filePath)
        SecItemDelete(keyQuery(challenge) as CFDictionary)
        for store in [store, workStore] {
            for cookie in await cookies(store) where cookie.name == challenge.cookieName && cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == IsolationPolicy.canaryDomain {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in store.httpCookieStore.delete(cookie) { continuation.resume() } }
            }
        }
        self.challenge = nil
        if !keepStatus { status = "Test canaries removed. No website login data was changed." }
    }
    func inspect(_ data: String) async {
        guard data.utf8.count <= 65536, let bytes = data.data(using: .utf8),
              let result = try? JSONDecoder().decode(IsolationProbeResult.self, from: bytes),
              let challenge, challenge.validate(), result.challenge == challenge,
              result.probePID != challenge.browserPID else { status = "This report does not match a live challenge from another process."; return }
        guard let secret = try? Data(contentsOf: URL(fileURLWithPath: challenge.filePath)), secret.count == 32,
              SecItemCopyMatching(keyQuery(challenge) as CFDictionary, nil) == errSecSuccess,
              await cookies(store).contains(where: { $0.name == challenge.cookieName && $0.value == secret.base64EncodedString() }),
              await cookies(workStore).contains(where: { $0.name == challenge.cookieName && $0.value == secret.base64EncodedString() }) else {
            status = "INCONCLUSIVE: the browser's positive controls are no longer live. Create a new challenge."; return
        }
        status = result.assessment + "\n" + result.notes.joined(separator: "\n")
    }
    private func set(_ cookie: HTTPCookie, on store: WKWebsiteDataStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in store.httpCookieStore.setCookie(cookie) { continuation.resume() } }
    }
    private func cookies(_ store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) } }
    }
    private func keyQuery(_ challenge: IsolationChallenge) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: IsolationPolicy.canaryService,
         kSecAttrAccount as String: challenge.cookieName, kSecAttrAccessGroup as String: challenge.keychainGroup]
    }
    private func checkError(_ text: String) -> NSError { NSError(domain: "SideOS.Isolation", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

struct IsolationCheckView: View {
    let applicationID: String
    @ObservedObject var canaries: BrowserCanaries
    @State private var report = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Operating-system boundary") {
                    Text("Signed application identity: \(applicationID)").font(.caption.monospaced()).textSelection(.enabled)
                    Text("This browser is a separate installed app. It requests no shared app/keychain groups and refuses website sessions if its running signature enables debugging or shared access.")
                    Text("This is not a 100% security certificate. Device compromise, OS/WebKit vulnerabilities, malicious re-signing, phishing and untrusted keyboard/VPN/certificate software remain outside this test.").font(.caption)
                    Text("An installer holding this app’s signing key can replace its code. Keep the browser’s signing identity outside SideOS; use a separate Apple ID/team for the stronger installer-threat model.").font(.callout)
                }
                Section("Canary access test") {
                    Button("Create Synthetic Test Canaries") { Task { await canaries.start(applicationID: applicationID) } }.disabled(canaries.working)
                    Text(canaries.status).textSelection(.enabled)
                    if canaries.challenge != nil {
                        ShareLink("Share Challenge JSON", item: canaries.challengeJSON)
                        Button("Copy Challenge JSON") { UIPasteboard.general.setItems([["public.utf8-plain-text": canaries.challengeJSON]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(1800)]) }
                        Button("Remove Test Canaries", role: .destructive) { Task { await canaries.clear() } }.disabled(canaries.working)
                    }
                }
                Section("Verify a probe report") {
                    Text("Paste only the JSON from the included Isolation Probe. A negative result establishes only the access paths that this probe attempted while the positive controls remained live.").font(.caption)
                    TextEditor(text: $report).frame(minHeight: 130).font(.caption.monospaced())
                    Button("Check Report") { Task { await canaries.inspect(report) } }.disabled(canaries.working)
                }
                Section("Build") { Text("\(Bundle.main.bundleIdentifier ?? "") · \(Bundle.main.object(forInfoDictionaryKey: "SIEmbeddedSourceRevision") as? String ?? "Development")").font(.caption.monospaced()).textSelection(.enabled) }
            }.navigationTitle("Isolation Checks").toolbar { Button("Done") { dismiss() } }
        }
    }
}
