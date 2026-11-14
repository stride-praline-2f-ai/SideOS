import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main struct DuoFeatureTests {
    static func main() throws {
        func require(_ condition: Bool) { precondition(condition) }
        func rejects(_ message: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(message) } catch {}
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = base.appendingPathComponent("SideInstaller", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let channel = UUID(), request = UUID()
        let folder = try TahoeHostPickerDirectory(home: home, channel: channel)
        let now = Date()
        let selection = TahoeHostPickerHandoff.Request(id: request, action: .choose, created: now)
        try TahoeHostPickerHandoff.write(selection, at: folder.root.appendingPathComponent("request.json"))
        require(try folder.request() == selection)
        precondition(selection.isFresh(at: now.addingTimeInterval(599)))
        precondition(!selection.isFresh(at: now.addingTimeInterval(601)))
        precondition(!selection.isFresh(at: now.addingTimeInterval(-31)))
        for bad in ["../bad.ipa", "a/b.ipa", "a\\b.ipa", "x\0.ipa", "document.zip", ".ipa", String(repeating: "a", count: 250) + ".ipa"] {
            precondition(!TahoeHostPickerHandoff.validFilename(bad))
            precondition(TahoeHostPickerHandoff.selectedURL(.init(id: request, status: .selected, filename: bad), root: folder.root) == nil)
        }
        let payload = Data((0..<65_537).map { UInt8($0 % 251) })
        let source = base.appendingPathComponent("Example.IPA"); try payload.write(to: source)
        try folder.copyIPA(from: source, request: request, filename: "Example.IPA")
        let response = TahoeHostPickerHandoff.Response(id: request, status: .selected, filename: "Example.IPA")
        let picked = TahoeHostPickerHandoff.selectedURL(response, root: folder.root)!
        require(try Data(contentsOf: picked) == payload)
        precondition(TahoeHostPickerHandoff.stagedDirectory(for: picked, home: home) == picked.deletingLastPathComponent())
        precondition(TahoeHostPickerHandoff.stagedDirectory(for: source, home: home) == nil)
        rejects("An existing stage must never be overwritten") { try folder.copyIPA(from: source, request: request, filename: "Example.IPA") }
        try folder.respond(response)
        require(try TahoeHostPickerHandoff.read(TahoeHostPickerHandoff.Response.self, at: folder.root.appendingPathComponent("response.json")) == response)

        // A guest can mutate its own mailbox. None of these mutations may make
        // privileged host reads/writes follow it into another host directory.
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let secretData = try JSONEncoder().encode(selection)
        let secret = outside.appendingPathComponent("secret.json"); try secretData.write(to: secret)
        precondition(TahoeHostPickerHandoff.temporaryCopy(secret, temporaryDirectory: home) == nil)
        let temporaryLink = home.appendingPathComponent("link.ipa")
        try FileManager.default.createSymbolicLink(at: temporaryLink, withDestinationURL: secret)
        precondition(TahoeHostPickerHandoff.temporaryCopy(temporaryLink, temporaryDirectory: home) == nil)
        precondition(TahoeHostPickerHandoff.temporaryCopy(picked, temporaryDirectory: home) == picked.resolvingSymlinksInPath())
        let requestFile = folder.root.appendingPathComponent("request.json")
        try FileManager.default.removeItem(at: requestFile)
        try FileManager.default.createSymbolicLink(at: requestFile, withDestinationURL: secret)
        rejects("Host must refuse request symlinks") { _ = try folder.request() }
        try FileManager.default.removeItem(at: requestFile)
        try Data(repeating: 65, count: TahoeHostPickerHandoff.metadataLimit + 1).write(to: requestFile)
        rejects("Oversized metadata must be bounded before reading") { _ = try folder.request() }
        try FileManager.default.removeItem(at: requestFile)
        precondition(requestFile.path.withCString { mkfifo($0, mode_t(0o600)) } == 0)
        rejects("A FIFO must not block the host UI") { _ = try folder.request() }
        try FileManager.default.removeItem(at: requestFile)
        let reply = folder.root.appendingPathComponent("response.json")
        try FileManager.default.removeItem(at: reply)
        try FileManager.default.createSymbolicLink(at: reply, withDestinationURL: secret)
        try folder.respond(.init(id: request, status: .cancelled))
        require(try Data(contentsOf: secret) == secretData)
        folder.removeImport(request: request, filename: "Example.IPA")
        precondition(!FileManager.default.fileExists(atPath: picked.path))
        let imports = folder.root.appendingPathComponent("imports")
        try FileManager.default.removeItem(at: imports)
        try FileManager.default.createSymbolicLink(at: imports, withDestinationURL: outside)
        rejects("Staging must refuse a symlink directory") { try folder.copyIPA(from: source, request: UUID(), filename: "Example.IPA") }
        require(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["secret.json"])
        try FileManager.default.removeItem(at: imports)
        try folder.copyIPA(from: source, request: request, filename: "Example.IPA")
        let moved = base.appendingPathComponent("OriginalMailbox")
        try FileManager.default.moveItem(at: folder.root, to: moved)
        try FileManager.default.createSymbolicLink(at: folder.root, withDestinationURL: outside)
        precondition(!folder.pathUnchanged)
        try folder.respond(response)
        precondition(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("response.json").path))
        folder.removeImport(request: request, filename: "Example.IPA")
        precondition(!FileManager.default.fileExists(atPath: moved.appendingPathComponent("imports/\(request.uuidString)/Example.IPA").path))
        require(try Data(contentsOf: secret) == secretData)

        // These are viewport fixtures, not claims about any device's specs.
        for size in [CGSize(width: 360, height: 800), .init(width: 600, height: 800), .init(width: 720, height: 960),
                     .init(width: 900, height: 700), .init(width: 1024, height: 768), .init(width: 1376, height: 1032)] {
            let layout = TahoeViewportPolicy.layout(size: size, safe: .init(top: 59, bottom: 34), phone: true, mode: "duo")
            let inner = min(layout.viewport.width, layout.viewport.height) >= 450
            precondition(layout.viewport.width == size.width && layout.viewport.height == size.height - (inner ? 71 : 93))
            precondition(layout.insets.bottom == (inner ? 12 : 34))
            precondition(layout.innerDisplay == inner)
            precondition(layout.menuHeight == (inner ? 30 : 44))
            precondition(layout.usesTouchLayout == !inner)
            var state = TahoeWindowState()
            state.setViewportChrome(menuHeight: layout.menuHeight, prefersFilled: layout.prefersFilledWindows)
            state.setCanvas(layout.viewport)
            let id = state.open(.browser, title: "Browser")
            let window = state.windows.first { $0.id == id }!
            let frame = state.displayFrame(window)
            precondition(frame.minY >= layout.menuHeight + 2 && frame.maxX <= layout.viewport.width && frame.maxY <= layout.viewport.height)
            precondition(layout.hostFrame(frame).minY == frame.minY + 59)
            if layout.prefersFilledWindows { precondition(frame == state.workArea) }
            if inner {
                // Same usable dimensions must produce the same desktop chrome
                // and initial floating window as iPad, without phone scaling.
                let ipad = TahoeViewportPolicy.layout(size: layout.viewport, safe: .init(), phone: false, mode: nil)
                precondition(layout.menuHeight == ipad.menuHeight && !layout.prefersFilledWindows)
                var reference = TahoeWindowState(); reference.setCanvas(ipad.viewport)
                _ = reference.open(.browser, title: "iPad reference")
                precondition(frame == reference.displayFrame(reference.windows[0]))
                precondition(window.layout == .floating && !layout.compactMenus)
            }
        }
        let autoInner = TahoeViewportPolicy.layout(size: .init(width: 720, height: 960), safe: .init(), phone: true, mode: nil)
        precondition(autoInner.innerDisplay && !autoInner.usesTouchLayout && autoInner.menuHeight == 30)
        let outer = TahoeViewportPolicy.layout(size: .init(width: 390, height: 844), safe: .init(), phone: true, mode: nil)
        precondition(!outer.innerDisplay && outer.usesTouchLayout && outer.compactMenus)
        precondition(TahoeViewportPolicy.isPhone(idiom: false, model: "Tablet", hardware: "iPhone"))
        precondition(!TahoeViewportPolicy.isPhone(idiom: false, model: "iPad", hardware: "iPad"))
        var state = TahoeWindowState(); state.setCanvas(.init(width: 1024, height: 768))
        let id = state.open(.browser, title: "Fold transition")
        state.setLayout(.left, for: id)
        let tiled = state.displayFrame(state.windows[0])
        state.setCanvas(.init(width: 360, height: 700))
        precondition(state.displayFrame(state.windows[0]) == state.workArea)
        state.setCanvas(.init(width: 1024, height: 768))
        precondition(state.displayFrame(state.windows[0]) == tiled && state.windows[0].layout == .left)
        // New windows always start above the Dock, including a crowded short
        // display. Touch fullscreen minimisation restores the same identity.
        for canvas in [CGSize(width: 390, height: 600), .init(width: 720, height: 520), .init(width: 900, height: 700), .init(width: 1376, height: 1032)] {
            var fitted = TahoeWindowState(); fitted.setCanvas(canvas); fitted.setDockInset(72)
            for kind in [TahoeWindowKind.browser, .installer, .livecontainer, .guest, .files, .settings, .downloads, .calculator] {
                let id = fitted.open(kind, title: "Touch window")
                let window = fitted.windows.last!
                precondition(fitted.workArea.contains(window.frame))
                let original = window.frame
                fitted.toggleFullscreen(id)
                precondition(fitted.fullscreenID == id)
                fitted.minimize(id)
                precondition(fitted.fullscreenID == nil && fitted.windows.last!.minimized)
                fitted.focus(id)
                precondition(fitted.windows.last!.id == id && fitted.windows.last!.frame == original && !fitted.windows.last!.minimized)
                fitted.toggleFullscreen(id); fitted.close(id)
                precondition(fitted.fullscreenID == nil && !fitted.windows.contains { $0.id == id })
            }
        }
        var compact = TahoeWindowState(); compact.setCanvas(.init(width: 900, height: 700))
        _ = compact.open(.browser, title: "Compact")
        var standard = TahoeWindowState(); standard.setViewportChrome(menuHeight: 30, prefersFilled: false, compact: false)
        standard.setCanvas(.init(width: 900, height: 700)); _ = standard.open(.browser, title: "Standard")
        precondition(compact.windows.last!.frame.width < standard.windows.last!.frame.width)
        let invalid = TahoeViewportPolicy.layout(size: .init(width: CGFloat.nan, height: -1), safe: .init(top: CGFloat.infinity), phone: true, mode: nil)
        precondition(invalid.viewport.width.isFinite && invalid.viewport.width >= 1 && invalid.viewport.height >= 1)
        let desktop = TahoeViewportPolicy.layout(size: .init(width: 1024, height: 768), safe: .init(top: 20, bottom: 20), phone: false, mode: nil)
        precondition(desktop.viewport == CGSize(width: 1024, height: 768) && desktop.menuHeight == 30)
        print("Host IPA handoff: bounded metadata, cancellation, symlink/FIFO refusal, descriptor-relative staging/cleanup; adaptive safe viewports and fold restoration passed")
    }
}
