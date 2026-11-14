import Foundation
#if !canImport(SwiftUI)
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif

@main struct TahoeProjectSafetyTests {
    @MainActor static func main() async throws {
        let descriptor = TahoeSavedTab(id: UUID(), url: URL(string: "https://example.com")!, profile: "personal", zoom: 1, identity: "automatic", pinned: false)
        var second = descriptor; second.id = UUID()
        var arrangement = TahoeSavedBrowser(windowID: UUID(), addresses: [descriptor.url, second.url], selected: 0, tabs: [descriptor, second], selectedTabID: second.id)
        arrangement.regenerateTabIDs()
        precondition(arrangement.selectedTabID == arrangement.tabs?[1].id, "Arrangement remapping must preserve the selected tab")
        precondition(arrangement.tabs?.contains(where: { $0.id == descriptor.id || $0.id == second.id }) == false)
        let storageName = "safety-" + UUID().uuidString + ".json"
        let storageFile = TahoeStorage.root.appendingPathComponent(storageName)
        let recoveredBefore = UserDefaults.standard.object(forKey: "TahoeRecoveredFile")
        defer {
            try? FileManager.default.removeItem(at: storageFile)
            try? FileManager.default.removeItem(at: storageFile.appendingPathExtension("previous"))
            UserDefaults.standard.set(recoveredBefore, forKey: "TahoeRecoveredFile")
        }
        try TahoeStorage.write(["previous"], to: storageName)
        try TahoeStorage.write(["current"], to: storageName)
        try Data(#"{"wrongSchema":true}"#.utf8).write(to: storageFile)
        let recovered = try TahoeStorage.read(storageName, as: [String].self)
        precondition(recovered == ["previous"])
        try TahoeStorage.write(["next"], to: storageName)
        let previous = try Data(contentsOf: storageFile.appendingPathExtension("previous"))
        let decodedPrevious = try JSONDecoder().decode([String].self, from: previous)
        precondition(decodedPrevious == ["previous"], "Invalid-schema JSON must not overwrite a good recovery file")
        var windows = TahoeWindowState()
        windows.setCanvas(CGSize(width: 1400, height: 1000))
        for index in 0..<45 { windows.open(.browser, title: "Window \(index)") }
        var restored = TahoeWindowState()
        restored.restore(windows.windows, active: windows.activeID, space: 0, spaces: 3)
        precondition(restored.windows.count == 45, "Large sessions must not silently lose windows")
        let id = windows.windows[0].id
        let initial = windows.windows[0].frame
        windows.setCanvas(CGSize(width: 400, height: 500)); windows.setCanvas(CGSize(width: 1400, height: 1000))
        precondition(windows.windows.first(where: { $0.id == id })!.frame == initial)
        for layout in TahoeWindowLayout.allCases where layout != .floating {
            precondition(windows.workArea.contains(windows.layoutFrame(layout)))
        }
        windows.setCanvas(CGSize(width: 500, height: 600))
        precondition(!windows.canApply(.left) && windows.layoutFrame(.left) == windows.workArea)
        windows.showDesktop(); precondition(windows.activeID == nil)
        let regular = TahoeWindow(id: UUID(), title: "Browser", kind: .browser, frame: .zero)
        let web = TahoeWindow(id: UUID(), title: "ChatGPT", kind: .browser, frame: .zero, resourceID: "https://chatgpt.com")
        let guestA = TahoeWindow(id: UUID(), title: "App", kind: .guest, frame: .zero, resourceID: "data-a", applicationID: "Installed.app")
        let guestB = TahoeWindow(id: UUID(), title: "App", kind: .guest, frame: .zero, resourceID: "data-b", applicationID: "Installed.app")
        precondition(regular.applicationIdentity != web.applicationIdentity)
        precondition(guestA.applicationIdentity == guestB.applicationIdentity)
        var spaces = TahoeWindowState(); let sticky = spaces.open(.browser, title: "Everywhere")
        spaces.toggleAllSpaces(sticky); spaces.switchSpace(1)
        precondition(spaces.isVisible(spaces.windows[0])); spaces.focus(sticky); precondition(spaces.currentSpace == 1)
        spaces.moveToSpace(sticky, space: 0); precondition(!spaces.isVisible(spaces.windows[0]))

        let urls = (0..<201).map { URL(string: "https://chatgpt.com/c/chat-\($0)")! }
        let saved = TahoeSavedChatWorkspace(urls: urls, left: 200, right: 199, focusRight: false, ratio: 0.4)
        var chats = TahoeChatWorkspaceState(saved: saved, firstID: UUID())!
        precondition(chats.items.count == 201 && chats.saved.left == 200)
        let selected = chats.focused, originalRight = chats.right
        chats.swapPanes(); precondition(chats.right == selected && chats.left == originalRight && chats.focused == selected)
        let newID = UUID()
        precondition(chats.adopt(id: newID, url: URL(string: "https://chatgpt.com/c/new-conversation")!, title: "New", before: chats.items[0].id))
        precondition(chats.items[0].id == newID)
        precondition(!chats.adopt(id: UUID(), url: urls[0], title: "Duplicate", before: nil))
        let bytes = try JSONEncoder().encode(chats.saved)
        let encoded = String(decoding: bytes, as: UTF8.self)
        precondition(!encoded.contains("hasDraft") && !encoded.contains("title"))
        precondition(TahoeChatBridgeOrigin.allows(scheme: "https", host: "chatgpt.com", port: 443, mainFrame: true, matchingPage: true))
        for (scheme, host, port, main, matching) in [("http", "chatgpt.com", 0, true, true), ("https", "chatgpt.com.evil.test", 443, true, true), ("https", "chatgpt.com", 8443, true, true), ("https", "chatgpt.com", 0, false, true), ("https", "chatgpt.com", 0, true, false)] {
            precondition(!TahoeChatBridgeOrigin.allows(scheme: scheme, host: host, port: port, mainFrame: main, matchingPage: matching))
        }

        precondition(TahoeAddress.url(for: "localhost:8080/path")?.absoluteString == "http://localhost:8080/path")
        precondition(TahoeAddress.url(for: "127.0.0.1:3000")?.scheme == "http")
        precondition(TahoeAddress.url(for: "[::1]:8080")?.scheme == "http")
        precondition(TahoeAddress.url(for: "javascript:alert(1)") == nil)
        precondition(TahoeMenuPointerIntent.towardSubmenu(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 160, y: 70), submenu: CGRect(x: 200, y: 20, width: 100, height: 200)))
        precondition(!TahoeMenuPointerIntent.towardSubmenu(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 80, y: 70), submenu: CGRect(x: 200, y: 20, width: 100, height: 200)))
        var queue = TahoePageRestoreQueue<UUID>()
        let background = UUID(), foreground = UUID()
        queue.enqueue(background); queue.enqueue(foreground)
        precondition(queue.next(allowed: [foreground]) == foreground)
        precondition(queue.next(allowed: []) == nil)
        queue.remove(foreground); precondition(queue.next() == background)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sideos-safety-" + UUID().uuidString)
        let documents = root.appendingPathComponent("Documents"), destination = root.appendingPathComponent("Destination"), trash = root.appendingPathComponent("Trash")
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = TahoeFileWorker.shared
        try await worker.prepare([documents, destination, trash])
        let a = documents.appendingPathComponent("a.txt"), b = documents.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        let clipboard = TahoeFileClipboard()
        clipboard.set([a], cut: true)
        try await clipboard.paste(to: destination, progress: { _, _ in clipboard.set([b], cut: false) })
        precondition(clipboard.urls == [b] && !clipboard.cut, "An older paste must not erase a newer Copy")
        let moved = destination.appendingPathComponent("a.txt")
        precondition(FileManager.default.fileExists(atPath: moved.path))
        try await worker.undoLast(); precondition(FileManager.default.fileExists(atPath: a.path))
        try await worker.trash(a, in: trash)
        try await worker.restore(trash.appendingPathComponent("a.txt"), fallback: destination, allowedRoot: root)
        precondition(FileManager.default.fileExists(atPath: a.path), "Trash must preserve the original directory")
        let rename = try await worker.batchRename([a, b], prefix: "Renamed")
        precondition(rename.count == 2 && FileManager.default.fileExists(atPath: documents.appendingPathComponent("Renamed 2.txt").path))
        try await worker.undoLast()
        precondition(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
        try Data("existing".utf8).write(to: documents.appendingPathComponent("Conflict 1.txt"))
        do { _ = try await worker.batchRename([a, b], prefix: "Conflict"); preconditionFailure("Collision must not replace a file") }
        catch { precondition(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path)) }
        do { _ = try await worker.move(documents, to: documents.appendingPathComponent("Nested")); preconditionFailure("Self-descendant moves must fail") } catch { }
        let cancelled = Task { try await worker.snapshot(documents) }; cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled enumeration must stop") } catch is CancellationError { }
        let snapshot = try await worker.snapshot(documents)
        precondition(snapshot.entries.contains(a) && snapshot.metadata[a]?.bytes == 1)
        print("Project safety: oversized sessions, profile-safe chat metadata, rotation/tiling, drag geometry, clipboard race, trash restore, transactional rename, undo and cancellation passed")
    }
}
