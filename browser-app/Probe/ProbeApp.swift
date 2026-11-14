import SwiftUI
import WebKit
import Security
import Darwin

@main struct IsolationProbeApp: App {
    var body: some Scene { WindowGroup { ProbeScreen() } }
}

struct ProbeScreen: View {
    @State private var challengeJSON = ""
    @State private var output = ""
    @State private var running = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Synthetic isolation probe") {
                    Text("Run this app inside LiveContainer while the separately installed SideOS Browser is open. It tests only the challenge's synthetic file/keychain item/cookies and requests a task port without reading process memory. It sends nothing over the network.")
                    Text("Disable custom tweaks for the baseline test. Test windowed and classic launch modes separately, alongside SideInstaller and other hosted apps. Repeat after reboot, re-signing or runtime updates.").font(.caption)
                }
                Section("Paste the browser's challenge JSON") {
                    TextEditor(text: $challengeJSON).frame(minHeight: 160).font(.caption.monospaced())
                    Button(running ? "Testing…" : "Run Canary Access Attempts") { Task { await run() } }.disabled(running)
                }
                Section("Report") {
                    Text(output.isEmpty ? "No test has run." : output).font(.caption.monospaced()).textSelection(.enabled)
                    if !output.isEmpty { Button("Copy Report JSON") { UIPasteboard.general.setItems([["public.utf8-plain-text": output]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(1800)]) } }
                }
            }.navigationTitle("Isolation Probe")
        }
    }
    @MainActor private func run() async {
        guard challengeJSON.utf8.count <= 65536, let bytes = challengeJSON.data(using: .utf8),
              let challenge = try? JSONDecoder().decode(IsolationChallenge.self, from: bytes), challenge.validate() else {
            output = "Invalid or expired challenge. Create a fresh one in the separately installed browser."; return
        }
        running = true; defer { running = false }
        let descriptor = open(challenge.filePath, O_RDONLY | O_NOFOLLOW)
        let fileStatus = descriptor >= 0 ? 0 : errno
        if descriptor >= 0 { close(descriptor) } // Opening proves access; no file contents are exported.
        let keychainStatus = SideOSRawKeychainStatus([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: IsolationPolicy.canaryService, kSecAttrAccount as String: challenge.cookieName,
            kSecAttrAccessGroup as String: challenge.keychainGroup, kSecMatchLimit as String: kSecMatchLimitOne])
        var task: mach_port_t = 0
        let taskStatus = task_for_pid(mach_task_self_, challenge.browserPID, &task)
        if taskStatus == KERN_SUCCESS { mach_port_deallocate(mach_task_self_, task) }
        var ownTask: mach_port_t = 0
        let ownTaskStatus = task_for_pid(mach_task_self_, getpid(), &ownTask)
        if ownTaskStatus == KERN_SUCCESS { mach_port_deallocate(mach_task_self_, ownTask) }
        let ownFile = FileManager.default.temporaryDirectory.appendingPathComponent("sideos-probe-" + challenge.id.uuidString)
        let ownFileControl: Bool
        do { try Data([1, 2, 3]).write(to: ownFile); ownFileControl = try Data(contentsOf: ownFile) == Data([1, 2, 3]); try? FileManager.default.removeItem(at: ownFile) }
        catch { ownFileControl = false }
        let ownStore = WKWebsiteDataStore.nonPersistent()
        let ownCookie = HTTPCookie(properties: [.domain: IsolationPolicy.canaryDomain, .path: "/", .name: "probe_control", .value: "synthetic"] )!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in ownStore.httpCookieStore.setCookie(ownCookie) { continuation.resume() } }
        let controlCookies = await cookies(ownStore)
        var found = false
        for store in [WKWebsiteDataStore.default(), WKWebsiteDataStore(forIdentifier: IsolationPolicy.workStoreID)] {
            let scopedCookies = await cookies(store)
            // Other cookie objects are neither reported nor exported. Only the reserved synthetic canary is tested.
            if scopedCookies.contains(where: { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == IsolationPolicy.canaryDomain && $0.name == challenge.cookieName }) { found = true }
        }
        let result = IsolationProbeResult(challenge: challenge, probePID: getpid(), fileStatus: fileStatus,
            keychainStatus: keychainStatus, taskStatus: taskStatus, ownProcessControl: ownTaskStatus == KERN_SUCCESS,
            ownFileControl: ownFileControl, ownCookieControl: controlCookies.contains { $0.name == "probe_control" && $0.value == "synthetic" },
            ownKeychainControl: SideOSRawKeychainControl(challenge.id.uuidString), foundCanary: found,
            notes: ["File open status: \(fileStatus); raw framework keychain status: \(keychainStatus); task-port status: \(taskStatus).",
                "Same-process execution: \(getpid() == challenge.browserPID). Checks cover synthetic canaries only; no browsing credentials or process memory are exported."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        output = (try? encoder.encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? "Report encoding failed."
    }
    private func cookies(_ store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) } }
    }
}
