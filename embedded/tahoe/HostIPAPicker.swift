import SwiftUI
import UniformTypeIdentifiers
import CoreFoundation

/// File-provider UI belongs to the actual SideOS application, outside the
/// remote guest scene. Only the selected IPA is copied into the installer's
/// already-shared container. This handoff does not provide a sandbox boundary
/// against malicious hosted apps elsewhere in the host runtime.
@MainActor @objc(TahoeInstallerPickerServer)
final class TahoeInstallerPickerServer: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    static let shared = TahoeInstallerPickerServer()
    private var channel: UUID?
    private var directory: TahoeHostPickerDirectory?
    private var root: URL?
    private var picker: UIDocumentPickerViewController?
    private var active: TahoeHostPickerHandoff.Request?
    private var finished = Set<UUID>()
    private var copying = Set<UUID>()
    private var observing = false

    private struct Staged: Codable { let channel: UUID; let request: UUID; let filename: String }
    private var staged: [Staged] = []
    private let stagedKey = "SideOS.HostPicker.Staged.v1"
    @objc static func prepareChannel() -> String? { shared.prepare() }
    private func prepare() -> String? {
        cancelActive()
        cleanupStaged()
        let channel = UUID()
        do { self.directory = try TahoeHostPickerDirectory(home: TahoeInstallerRuntime.directory, channel: channel) }
        catch { NSLog("SideOS host IPA picker could not prepare its private handoff: %@", error.localizedDescription); return nil }
        guard let directory else { return nil }
        self.channel = channel; self.root = directory.root; finished.removeAll()
        if !observing {
            observing = true
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                    guard let observer else { return }
                    let server = Unmanaged<TahoeInstallerPickerServer>.fromOpaque(observer).takeUnretainedValue()
                    Task { @MainActor in server.receive() }
                }, TahoeHostPickerHandoff.notification as CFString, nil, .deliverImmediately)
        }
        return channel.uuidString
    }
    private func receive() {
        guard let root, let directory, directory.pathUnchanged, let request = try? directory.request(), request.isFresh else { return }
        if request.action == .cancel {
            if active?.id == request.id { cancelActive() }
            return
        }
        guard !finished.contains(request.id), active?.id != request.id else { return }
        guard active == nil else {
            cancelActive()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300)); self?.receive()
            }
            return
        }
        guard let window = TahoeWorkspace.shared.hostWindow,
              let presenter = window.rootViewController, !window.isHidden,
              window.windowScene?.activationState == .foregroundActive else {
            respond(.init(id: request.id, status: .failed, message: "The SideOS window is not ready for Files. Reopen SideInstaller."), root: root)
            return
        }
        var top = presenter
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        guard !top.isBeingDismissed, !top.isBeingPresented, !(top is UIAlertController), top.presentedViewController?.isBeingDismissed != true else {
            respond(.init(id: request.id, status: .failed, message: "Wait for the current dialog to close, then choose the IPA again."), root: root)
            return
        }
        TahoeWorkspace.shared.menu = nil
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.title = "Choose an IPA for SideInstaller"
        picker.allowsMultipleSelection = false; picker.shouldShowFileExtensions = true
        picker.delegate = self
        self.picker = picker; active = request
        top.present(picker, animated: true)
        picker.presentationController?.delegate = self
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil, error: nil, controller: controller) }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let picker, presentationController.presentedViewController === picker else { return }
        guard let active, !copying.contains(active.id) else { return }
        finish(nil, error: nil, controller: picker)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard controller === picker, let request = active, let root, let directory else { return }
        guard let source = urls.first else { finish(nil, error: nil, controller: controller); return }
        guard TahoeHostPickerHandoff.validFilename(source.lastPathComponent) else {
            Self.discardTemporaryCopy(source)
            finish(nil, error: "Choose the .ipa file itself. Unzip a downloaded build ZIP first.", controller: controller); return
        }
        guard !copying.contains(request.id) else { return }
        guard copying.count < 2 else {
            finish(nil, error: "A previous IPA copy is still finishing. Please wait a moment and try again.", controller: controller); return
        }
        copying.insert(request.id)
        let name = source.lastPathComponent
        let response = TahoeHostPickerHandoff.Response(id: request.id, status: .selected, filename: name)
        guard let destination = TahoeHostPickerHandoff.selectedURL(response, root: root) else {
            copying.remove(request.id); finish(nil, error: "The selected filename is not supported.", controller: controller); return
        }
        if let channel { staged.append(Staged(channel: channel, request: request.id, filename: name)); persistStaged() }
        let scoped = source.startAccessingSecurityScopedResource()
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> String? in
                defer {
                    Self.discardTemporaryCopy(source)
                    if scoped { source.stopAccessingSecurityScopedResource() }
                }
                do {
                    let values = try source.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                    try directory.copyIPA(from: source, request: request.id, filename: name)
                    return nil
                } catch { return String(error.localizedDescription.prefix(600)) }
            }.value
            copying.remove(request.id)
            guard active?.id == request.id, self.root == root else {
                directory.removeImport(request: request.id, filename: name); return
            }
            let readable = directory.pathUnchanged && TahoeHostPickerHandoff.selectedURL(response, root: root) != nil && FileManager.default.fileExists(atPath: destination.path)
            finish(result == nil && readable ? name : nil,
                   error: result ?? (readable ? nil : "The private IPA handoff changed. Reopen SideInstaller and try again."), controller: controller)
        }
    }
    nonisolated private static func discardTemporaryCopy(_ url: URL) {
        if let copy = TahoeHostPickerHandoff.temporaryCopy(url, temporaryDirectory: FileManager.default.temporaryDirectory) {
            try? FileManager.default.removeItem(at: copy)
        }
    }
    private func finish(_ filename: String?, error: String?, controller: UIDocumentPickerViewController) {
        guard controller === picker, let request = active, let root else { return }
        picker = nil; active = nil
        let response = TahoeHostPickerHandoff.Response(id: request.id,
            status: error != nil ? .failed : filename != nil ? .selected : .cancelled,
            filename: filename, message: error)
        let complete: () -> Void = { [weak self] in self?.respond(response, root: root) }
        if controller.presentingViewController != nil { controller.dismiss(animated: true, completion: complete) }
        else { complete() }
    }
    func invalidate() {
        cancelActive()
        cleanupStaged()
        directory = nil; root = nil; channel = nil
    }
    private func persistStaged() {
        if let data = try? JSONEncoder().encode(Array(staged.suffix(128))) { UserDefaults.standard.set(data, forKey: stagedKey) }
    }
    private func cleanupStaged() {
        var records = staged
        if let data = UserDefaults.standard.data(forKey: stagedKey), data.count < 131_072,
           let saved = try? JSONDecoder().decode([Staged].self, from: data) { records += saved.prefix(128) }
        for entry in records where TahoeHostPickerHandoff.validFilename(entry.filename) {
            if let folder = try? TahoeHostPickerDirectory(home: TahoeInstallerRuntime.directory, channel: entry.channel, create: false) {
                folder.removeImport(request: entry.request, filename: entry.filename)
            }
        }
        staged.removeAll(); UserDefaults.standard.removeObject(forKey: stagedKey)
    }
    private func cancelActive() {
        guard let picker else { return }
        finish(nil, error: nil, controller: picker)
    }
    private func respond(_ response: TahoeHostPickerHandoff.Response, root: URL) {
        if self.root == root { finished.insert(response.id); if finished.count > 64 { finished = [response.id] } }
        guard self.root == root, let directory else { return }
        do { try directory.respond(response) }
        catch { NSLog("SideOS host IPA picker response failed: %@", error.localizedDescription) }
    }
}
