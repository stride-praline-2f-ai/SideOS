import SwiftUI
import Darwin
import CoreFoundation

/// Hosted SideInstaller asks the real SideOS application to present Files.
/// This avoids a document-provider remote view inside another remote scene.
private struct SideInstallerIPAPicker: ViewModifier {
    @Environment(Engine.self) private var engine
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void
    @State private var standaloneURL: URL?

    func body(content: Content) -> some View {
#if SIDEINSTALLER_EMBEDDED
        content.task(id: isPresented) {
            guard isPresented else { return }
            do {
                engine.log("Files access runtime: SideOS host picker requested")
                let url = try await chooseFromHost()
                isPresented = false
                if let url { engine.log("Files access runtime: host selection received"); onPick(url) }
            } catch is CancellationError { isPresented = false }
            catch {
                isPresented = false
                engine.lastError = error.localizedDescription
                engine.log("Files access runtime: \(error.localizedDescription)")
            }
        }
#else
        content.sheet(isPresented: $isPresented, onDismiss: {
            guard let url = standaloneURL else { return }
            standaloneURL = nil; onPick(url)
        }) {
            FileImporterRepresentableView(allowedContentTypes: [.item]) { urls in
                standaloneURL = urls.first; isPresented = false
            }.ignoresSafeArea()
        }
#endif
    }

    private func chooseFromHost() async throws -> URL? {
        guard let text = getenv(TahoeHostPickerHandoff.channelEnvironment).map({ String(cString: $0) }),
              let channel = UUID(uuidString: text) else {
            throw pickerError("Reopen SideInstaller from the SideOS Dock to connect the Files picker.")
        }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let root = TahoeHostPickerHandoff.root(home: home, channel: channel)
        let id = UUID()
        let request = TahoeHostPickerHandoff.Request(id: id, action: .choose, created: Date())
        try TahoeHostPickerHandoff.write(request, at: root.appendingPathComponent("request.json"))
        notifyHost()
        do {
            // Only while Files is open. Bounded polling also survives missed
            // Darwin deliveries and resumes when the guest scene gains focus.
            for _ in 0..<Int(TahoeHostPickerHandoff.lifetime * 4) {
                try Task.checkCancellation()
                guard FileManager.default.fileExists(atPath: root.path) else {
                    throw pickerError("The Files connection was reset. Reopen SideInstaller and choose the IPA again.")
                }
                if let response = try? TahoeHostPickerHandoff.read(TahoeHostPickerHandoff.Response.self,
                    at: root.appendingPathComponent("response.json")), response.id == id {
                    switch response.status {
                    case .cancelled: return nil
                    case .failed: throw pickerError(response.message ?? "Files could not finish choosing this IPA.")
                    case .selected:
                        guard let url = TahoeHostPickerHandoff.selectedURL(response, root: root),
                              FileManager.default.fileExists(atPath: url.path) else {
                            throw pickerError("Files did not return a readable IPA. Choose it again.")
                        }
                        return url
                    }
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw pickerError("The Files picker timed out. Close Files and choose the IPA again.")
        } catch {
            let cancel = TahoeHostPickerHandoff.Request(id: id, action: .cancel, created: Date())
            try? TahoeHostPickerHandoff.write(cancel, at: root.appendingPathComponent("request.json"))
            notifyHost()
            throw error
        }
    }
    private func notifyHost() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: TahoeHostPickerHandoff.notification as CFString), nil, nil, true)
    }
    private func pickerError(_ message: String) -> NSError {
        NSError(domain: "SideOS.IPAPicker", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

extension View {
    func sideInstallerIPAImporter(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) -> some View {
        modifier(SideInstallerIPAPicker(isPresented: isPresented, onPick: onPick))
    }
}
