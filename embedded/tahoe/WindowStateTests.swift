import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@main struct TahoeStateTests {
    static func main() {
        var state = TahoeWindowState()
        state.setCanvas(CGSize(width: 1194, height: 834))
        let browser = state.open(.browser, title: "Browser")
        let guest = state.open(.guest, title: "Guest", resourceID: "test-container")
        let original = state.windows.first(where: { $0.id == browser })!.frame

        state.minimize(guest)
        precondition(state.activeID == browser, "Minimising must focus the next visible window")
        state.focusVisible(guest)
        precondition(state.windows.first(where: { $0.id == guest })!.minimized && state.activeID == browser,
                     "A child-button tap must not restore the window it just minimised")
        state.focus(guest)
        precondition(!state.windows.last!.minimized && state.activeID == guest)
        state.toggleMaximize(browser)
        precondition(state.displayFrame(state.windows.last!) == state.workArea)
        state.toggleMaximize(browser)
        precondition(state.windows.last!.frame == original, "Maximise must not overwrite restore geometry")

        state.toggleFullscreen(guest)
        precondition(state.fullscreenID == guest)
        precondition(state.displayFrame(state.windows.last!).size == state.canvas)
        state.focus(browser)
        precondition(state.fullscreenID == nil, "Focusing another window must exit fullscreen")
        state.toggleFullscreen(browser)
        state.minimize(browser)
        precondition(state.fullscreenID == nil && state.activeID == guest)
        state.focus(browser)
        precondition(state.windows.last!.frame == original)

        let beforeMove = state.windows.first(where: { $0.id == browser })!.frame
        state.move(browser, from: beforeMove, translation: CGSize(width: 0, height: 450))
        let underDock = state.windows.first(where: { $0.id == browser })!.frame
        precondition(underDock.maxY > state.workArea.maxY, "Floating windows must move behind the Dock")
        precondition(underDock.minY < state.canvas.height && underDock.minY >= state.desktopArea.minY, "The title bar must remain reachable")
        state.move(browser, from: underDock, translation: CGSize(width: -100000, height: 100000))
        let outside = state.windows.first(where: { $0.id == browser })!.frame
        precondition(outside.maxX >= 100 && outside.minY <= state.canvas.height - 38)
        state.setDockInset(48)
        precondition(state.windows.first(where: { $0.id == browser })!.frame == outside, "Changing Dock size must preserve partially offscreen floating windows")
        state.toggleFullscreen(browser)
        precondition(state.displayFrame(state.windows.last!) == CGRect(origin: .zero, size: state.canvas), "Fullscreen must use every pixel, including the menu and Dock areas")
        state.toggleFullscreen(browser)
        precondition(state.windows.last!.frame == outside, "Exiting fullscreen restores the exact floating geometry")
        state.setCanvas(state.canvas)
        for edge in TahoeResizeEdge.allCases {
            state.resize(browser, from: original, edge: edge, translation: CGSize(width: 10000, height: -10000))
            let frame = state.windows.first(where: { $0.id == browser })!.frame
            precondition(frame.width >= 360 && frame.height >= 240)
            precondition(state.desktopArea.contains(frame), "Every resize edge must keep the frame inside the desktop, including beneath the Dock")
        }
        // Left/top resizing must preserve the opposite edge when minimum size is reached.
        state.resize(browser, from: original, edge: .topLeft, translation: CGSize(width: 10000, height: 10000))
        let resized = state.windows.first(where: { $0.id == browser })!.frame
        precondition(resized.maxX == original.maxX && resized.maxY == original.maxY)

        state.setLayout(.right, for: guest)
        let tiled = state.displayFrame(state.windows.last!)
        precondition(tiled.minX == state.workArea.midX && tiled.maxX == state.workArea.maxX)
        state.setCanvas(CGSize(width: 320, height: 240))
        for window in state.windows { precondition(state.desktopArea.contains(state.displayFrame(window))) }
        state.setCanvas(.zero)
        precondition(state.canvas.width == 320)
        state.close(guest)
        precondition(state.activeID == browser)
        state.close(browser)
        precondition(state.activeID == nil && state.windows.isEmpty)
        state.focus(UUID())
        state.toggleFullscreen(UUID())
        precondition(state.windows.isEmpty && state.fullscreenID == nil)

        let firstSpace = state.open(.notes, title: "Notes")
        state.switchSpace(1)
        precondition(state.activeID == nil && !state.isVisible(state.windows[0]))
        let secondSpace = state.open(.calculator, title: "Calculator")
        state.focus(firstSpace)
        precondition(state.currentSpace == 0 && state.activeID == firstSpace)
        state.showDesktop()
        precondition(!state.isVisible(state.windows.last!))
        state.focus(firstSpace)
        precondition(!state.desktopExposed)
        state.moveToSpace(firstSpace, space: 1)
        precondition(state.activeID == nil)
        state.switchSpace(1)
        precondition(state.activeID == firstSpace)
        state.cycleFocus()
        precondition(state.activeID == secondSpace)
        var saved = state.windows
        saved.append(saved[0])
        var native = saved[0]
        native = TahoeWindow(id: UUID(), title: "Never auto-launch", kind: .guest, frame: native.frame)
        saved.append(native)
        state.restore(saved, active: nil, space: 99, spaces: 99)
        precondition(state.spaceCount == 6 && state.currentSpace == 5)
        precondition(state.windows.count == 2 && !state.windows.contains { $0.kind == .guest })
        let snapshot = TahoeSavedWorkspace(windows: state.windows, browsers: [], active: nil, space: state.currentSpace, spaces: state.spaceCount)
        let roundTrip = try! JSONDecoder().decode(TahoeSavedWorkspace.self, from: JSONEncoder().encode(snapshot))
        precondition(roundTrip.windows == state.windows && roundTrip.spaces == 6)
        precondition(!TahoeStorage.isWebURL(URL(string: "file:///private/example")!))
        var calculator = TahoeCalculator()
        for key in ["2", "+", "3", "="] { calculator.press(key) }
        precondition(calculator.display == "5")
        for key in ["AC", "1", ".", "5", ".", "×", "2", "="] { calculator.press(key) }
        precondition(calculator.display == "3")
        for key in ["AC", "1", "0", "0", "%", "+/−"] { calculator.press(key) }
        precondition(calculator.display == "-1")
        for key in ["AC", "1", "÷", "0", "="] { calculator.press(key) }
        precondition(calculator.display == "Error")
        calculator.press("7")
        precondition(calculator.display == "7")

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Tahoe-Files-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sourceFile = fixture.appendingPathComponent("Original.txt")
        try! "keep me".write(to: sourceFile, atomically: true, encoding: .utf8)
        try! TahoeFileOperations.copy(sourceFile, name: "Original.txt", to: fixture)
        precondition(try! String(contentsOf: sourceFile, encoding: .utf8) == "keep me")
        precondition(try! String(contentsOf: fixture.appendingPathComponent("Original 2.txt"), encoding: .utf8) == "keep me")
        do {
            try TahoeFileOperations.copy(fixture.appendingPathComponent("Missing.txt"), name: "Failed.txt", to: fixture)
            preconditionFailure("Missing source must fail")
        } catch { }
        precondition(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("Failed.txt").path))
        let contents = try! FileManager.default.contentsOfDirectory(atPath: fixture.path)
        precondition(!contents.contains { $0.hasPrefix(".copy-") })
        for name in ["", " ", ".", "..", "a/b", "a:b", "a\0b"] { precondition(!TahoeFileOperations.validName(name)) }
        precondition(TahoeFileOperations.validName("A normal file.txt"))
        state.setDockInset(0)
        precondition(state.workArea.maxY == state.canvas.height)
        state.setDockInset(100)
        precondition(state.workArea.maxY == state.canvas.height - 100)

        precondition(TahoeAddress.url(for: " example.com/path ")?.absoluteString == "https://example.com/path")
        precondition(TahoeAddress.url(for: "https://example.com")?.scheme == "https")
        precondition(TahoeAddress.url(for: "http://localhost:8080")?.port == 8080)
        precondition(TahoeAddress.url(for: "example.com:8080/test")?.port == 8080)
        for input in ["", "  ", "javascript:alert(1)", "file:///private/test", "ftp://example.com", "mailto:user@example.com", "data:text/html,test"] {
            precondition(TahoeAddress.url(for: input) == nil)
        }
        let search = TahoeAddress.url(for: "swift ui & windows")!
        precondition(URLComponents(url: search, resolvingAgainstBaseURL: false)!.queryItems!.first!.value == "swift ui & windows")
        precondition(TahoeNumeric.stepping(9, direction: 1, in: 0...10, step: 3, wraps: true) == 10)
        precondition(TahoeNumeric.stepping(10, direction: 1, in: 0...10, step: 3, wraps: true) == 0)
        precondition(TahoeNumeric.stepping(0, direction: -1, in: 0...10, step: 3, wraps: true) == 10)
        precondition(TahoeNumeric.stepping(10, direction: 1, in: 0...10, step: 3, wraps: false) == 10)
        let folder = fixture.appendingPathComponent("Folder", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { try TahoeFileOperations.copy(fixture, name: "Recursive", to: folder); preconditionFailure("Copying a folder into itself must fail before starting") } catch { }
        do { try TahoeFileOperations.move(fixture, to: folder); preconditionFailure("Moving a folder into itself must fail") } catch { }
        let copied = fixture.appendingPathComponent("Original 2.txt")
        try! TahoeFileOperations.move(copied, to: folder)
        precondition(!FileManager.default.fileExists(atPath: copied.path))
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Original 2.txt").path))
        precondition(TahoeNumeric.value(7, in: 3...13, step: 3) == 6)
        precondition(TahoeNumeric.value(30, in: 3...13, step: 3) == 13)
        precondition(TahoeNumeric.value(-1, in: 0...10, step: 2) == 0)
        precondition(TahoeNumeric.value(.nan, in: 2...4) == 2)
        precondition(TahoeNumeric.fraction(4, in: 4...4) == 0)
        precondition(TahoeNumeric.fraction(5, in: 0...10) == 0.5)
        var selection = TahoeSelection<String>()
        let order = ["a", "b", "c", "d"]
        selection.select("b", ordered: order)
        selection.select("d", ordered: order, extending: true)
        precondition(selection.selected == ["b", "c", "d"])
        selection.select("c", ordered: order, toggling: true)
        precondition(selection.selected == ["b", "d"])
        selection.move(-1, ordered: order, extending: true)
        precondition(selection.selected == ["b", "c"])
        selection.reconcile(["a", "c"])
        precondition(selection.selected == ["c"])
        selection.clear(); selection.move(1, ordered: order)
        precondition(selection.selected == ["a"])
        selection.selectAll(order); precondition(selection.selected.count == 4)
        precondition(TahoeMenuNavigation.next(from: 2, direction: 1, enabled: [false, true, true]) == 1)
        precondition(TahoeMenuNavigation.next(from: nil, direction: -1, enabled: [true, false, true]) == 2)
        precondition(TahoeMenuNavigation.next(from: nil, direction: 1, enabled: [false, false]) == nil)
        precondition(TahoeMenuNavigation.match("do", titles: ["Documents", "Disabled", "Downloads"], enabled: [true, false, true], after: 0) == 2)
        for kind in [TahoeWindowKind.browser, .guest] {
            var hosted = TahoeWindowState()
            hosted.setCanvas(CGSize(width: 1376, height: 1032)); hosted.setDockInset(80)
            let id = hosted.open(kind, title: "Hosted", resourceID: kind == .browser ? "https://example.com/app" : "guest-container")
            let original = hosted.windows.last!.frame
            hosted.move(id, from: original, translation: CGSize(width: 45, height: 35))
            let moved = hosted.windows.last!.frame
            precondition(moved.minX == original.minX + 45)
            hosted.toggleMaximize(id)
            precondition(hosted.displayFrame(hosted.windows.last!) == hosted.workArea && hosted.fullscreenID == nil)
            hosted.toggleMaximize(id)
            precondition(hosted.windows.last!.frame == moved && hosted.windows.last!.id == id)
            for edge in TahoeResizeEdge.allCases {
                var resized = hosted
                resized.resize(id, from: moved, edge: edge, translation: CGSize(width: 20, height: 20))
                precondition(resized.windows.last!.frame != moved && resized.windows.last!.id == id)
                precondition(resized.windows.last!.resourceID == hosted.windows.last!.resourceID)
            }
            hosted.setLayout(.left, for: id)
            precondition(hosted.displayFrame(hosted.windows.last!).width == hosted.workArea.width / 2)
        }
        let appWindow = TahoeWindow(id: UUID(), title: "Notes", kind: .browser, frame: .zero, resourceID: "https://www.icloud.com/notes/")
        precondition(appWindow.isWebApp)
        precondition(!TahoeWindow(id: UUID(), title: "Browser", kind: .browser, frame: .zero).isWebApp)
        precondition(!TahoeWindow(id: UUID(), title: "Guest", kind: .guest, frame: .zero, resourceID: "https://example.com").isWebApp)
        let popup = TahoePopupGeometry.frame(anchor: CGRect(x: 970, y: 650, width: 20, height: 20), size: CGSize(width: 280, height: 300), canvas: CGSize(width: 1000, height: 700))
        precondition(popup.minX >= 4 && popup.maxX <= 996 && popup.minY >= 4 && popup.maxY <= 696)
        let childPopup = TahoePopupGeometry.frame(anchor: CGRect(x: 700, y: 150, width: 280, height: 25), size: CGSize(width: 280, height: 150), canvas: CGSize(width: 1000, height: 700), submenu: true)
        precondition(childPopup.maxX < 700, "Submenus flip left at the right edge")
        precondition(TahoeToolbarOverflow.visibleCount(widths: [28, 28, 28], available: 96) == 3)
        precondition(TahoeToolbarOverflow.visibleCount(widths: [28, 28, 28], available: 90) == 1)
        precondition(TahoeToolbarOverflow.visibleCount(widths: [28], available: 10) == 0)
        let icon = TahoeDesktopLayout.frame(index: 0, canvas: CGSize(width: 500, height: 400), saved: CGPoint(x: 9999, y: -1))
        precondition(CGRect(x: 0, y: 0, width: 500, height: 400).contains(icon))
        precondition(TahoeDesktopLayout.selection(from: CGPoint(x: 10, y: 40), to: CGPoint(x: 0, y: 5)) == CGRect(x: 0, y: 5, width: 10, height: 35))
        precondition(TahoeAddress.allowsPopup(URL(string: "about:blank")!))
        precondition(TahoeAddress.allowsPopup(URL(string: "https://example.com/login")!))
        precondition(!TahoeAddress.allowsPopup(URL(string: "file:///private/data")!))
        precondition(!TahoeAddress.allowsPopup(URL(string: "javascript:alert(1)")!))
        precondition(!TahoeAddress.allowsPopup(URL(string: "data:text/html,test")!))
        // Different app counts, screen widths and hover positions must fit
        // without losing separator space or making magnification oscillate.
        for available: CGFloat in [320, 768, 1024, 1280, 1376] {
            for count in [1, 6, 15, 30, 60] {
                let separators: Set<Int> = count > 3 ? [count - 2] : []
                let base = TahoeDockGeometry.layout(count: count, available: available, maximum: 64, automatic: true, separatorBefore: separators, magnification: true)
                precondition(base.widths.count == count && base.iconSize >= 20 && base.iconSize <= 64)
                for pointer in [CGFloat(0), base.naturalWidth / 2, base.naturalWidth] {
                    let hover = TahoeDockGeometry.layout(count: count, available: available, maximum: 64, automatic: true, separatorBefore: separators, magnification: true, pointer: pointer)
                    precondition(hover.iconSize == base.iconSize && hover.centers == base.centers, "Hover never changes the resting reference geometry")
                    precondition(hover.widths.allSatisfy { $0.isFinite && $0 >= base.iconSize })
                    if base.naturalWidth <= available { precondition(hover.renderedWidth <= available + 0.001, "Magnification must fit the screen") }
                }
            }
        }
        let crowded = TahoeDockGeometry.layout(count: 30, available: 1248, maximum: 64, automatic: true, separatorBefore: [28], magnification: true)
        let hovered = TahoeDockGeometry.layout(count: 30, available: 1248, maximum: 64, automatic: true, separatorBefore: [28], magnification: true, pointer: crowded.centers[14])
        precondition(hovered.widths[14] > crowded.iconSize, "A fitted Dock retains magnification room")
        let sparse = TahoeDockGeometry.layout(count: 6, available: 1248, maximum: 64, automatic: true)
        precondition(sparse.iconSize == 64 && sparse.iconSize > crowded.iconSize, "Removing apps restores the configured maximum")
        for count in [1, 6, 12, 30] {
            let touch = TahoeDockGeometry.layout(count: count, available: 640, maximum: 40, automatic: true, minimumSlot: 44)
            precondition(touch.iconSize <= 40 && touch.centers.count == count)
            for pair in zip(touch.centers, touch.centers.dropFirst()) { precondition(pair.1 - pair.0 >= 52) }
            precondition(touch.naturalWidth >= CGFloat(count) * 44 + 22 + CGFloat(count - 1) * 8)
            let hover = TahoeDockGeometry.layout(count: count, available: 640, maximum: 40, automatic: true, magnification: true, pointer: touch.centers[0], minimumSlot: 44)
            precondition(hover.renderedWidth >= hover.naturalWidth)
        }

        precondition(TahoeDockGeometry.layout(count: 0, available: 320, maximum: .nan, automatic: true).widths.isEmpty)
        print("Tahoe lifecycle, Spaces, restoration, resizing, addresses, calculator, file-copy, selection, control, menu and overflow fixtures passed.")
    }
}
