import Foundation

@main struct TahoeDesktopInteractionTests {
    static func main() {
        // Transparency remains independent of desktop/window focus and must
        // never leak into fullscreen, including with accessibility enabled.
        for fullscreen in [false, true] {
            for reduce in [false, true] {
                for enabled in [false, true] {
                    precondition(TahoeChromePolicy.clearMenu(enabled: enabled, fullscreen: fullscreen,
                        reduceTransparency: reduce) == (enabled && !fullscreen && !reduce))
                }
            }
        }
        func reveal(_ x: CGFloat, _ y: CGFloat, shown: Bool = false) -> Bool {
            TahoeChromePolicy.containsRevealPointer(CGPoint(x: x, y: y), revealed: shown,
                menuHeight: 30, trafficWidth: 92)
        }
        precondition(reveal(20, 20), "Hosted apps must reveal at the corner, not just the top six points")
        precondition(reveal(800, 3), "The thin top edge remains usable anywhere")
        precondition(!reveal(200, 20), "Hidden controls must not take ordinary app content")
        precondition(!reveal(20, 50), "Hidden controls do not occupy the future traffic-light row")
        precondition(reveal(20, 50, shown: true), "Moving from menu to traffic lights keeps controls visible")
        precondition(reveal(800, 20, shown: true))
        precondition(!reveal(200, 50, shown: true), "Moving into app content releases the controls")
        precondition(!reveal(-1, 3) && !reveal(3, -1) && !reveal(.nan, 3))
        for kind in [TahoeWindowKind.guest, .installer, .livecontainer, .settings, .files] {
            precondition(TahoeChromePolicy.showsFullscreenTrafficLights(kind: kind, webApp: false))
        }
        precondition(!TahoeChromePolicy.showsFullscreenTrafficLights(kind: .browser, webApp: false))
        precondition(TahoeChromePolicy.showsFullscreenTrafficLights(kind: .browser, webApp: true))
        var hover = TahoeFullscreenHoverState()
        hover.update("window", inside: true); hover.update("menu", inside: true)
        hover.update("window", inside: false); precondition(hover.inside)
        hover.update("menu", inside: false); precondition(!hover.inside)
        hover.update("guest", inside: true); hover.reset(); precondition(!hover.inside)
        var menu = TahoeMenuSession<String>()
        precondition(!menu.isOpen)
        menu.select("File")
        let firstRevision = menu.revision
        menu.select("File")
        precondition(menu.revision == firstRevision, "Repeated hover must not reset selection")
        menu.select("Edit")
        precondition(menu.bar == "Edit" && menu.contextID == nil && menu.revision == firstRevision + 1)
        let context = UUID()
        menu.showContext(context)
        precondition(menu.bar == nil && menu.contextID == context, "Context and bar menus must never coexist")
        menu.select("Window")
        precondition(menu.contextID == nil && menu.bar == "Window", "Bar menus replace contextual menus too")
        menu.dismiss()
        precondition(!menu.isOpen)
        let closedRevision = menu.revision
        menu.dismiss()
        precondition(menu.revision == closedRevision, "Dismissal is idempotent")

        let a = UUID(), b = UUID(), c = UUID()
        var apps = TahoeRunningApps()
        apps.attach(a, to: "First.app")
        apps.attach(b, to: "Second.app")
        apps.attach(c, to: "First.app")
        precondition(apps.applications.map(\.id) == ["First.app", "Second.app"])
        precondition(apps.application(for: c)?.windows == [a, c], "Multiple containers share one application icon")
        let stable = apps
        apps.attach(a, to: "Second.app")
        precondition(apps == stable, "A window cannot belong to two applications")
        apps.detach(a)
        precondition(apps.application(for: c)?.dockID == "guest-First.app", "Closing the first window preserves icon identity")
        apps.detach(c)
        precondition(apps.applications.map(\.id) == ["Second.app"], "Remove the icon only after its final window closes")
        apps.attach(a, to: "First.app")
        precondition(apps.applications.map(\.id) == ["Second.app", "First.app"], "Relaunch appends in launch order")

        var state = TahoeWindowState()
        state.setCanvas(CGSize(width: 1194, height: 834))
        let id = state.open(.browser, title: "Geometry")
        let original = state.windows[0].frame
        // Exercise corners, partially off-screen windows, extreme pointer deltas,
        // and the exact correspondence between live geometry and the drop.
        var samples = 0
        for dx in stride(from: -1600, through: 1600, by: 137) {
            for dy in stride(from: -1000, through: 1000, by: 191) {
                let translation = CGSize(width: dx, height: dy)
                let live = TahoeWindowGeometry.moved(original, translation: translation, area: state.desktopArea)
                state.move(id, from: original, translation: translation)
                precondition(state.windows[0].frame == live, "Release must not jump away from the live drag")
                precondition(live.minY >= state.desktopArea.minY && live.maxX >= 100 && live.minX <= state.canvas.width - 100)
                for edge in TahoeResizeEdge.allCases {
                    let resized = TahoeWindowGeometry.resized(original, edge: edge, translation: translation, area: state.desktopArea)
                    state.resize(id, from: original, edge: edge, translation: translation)
                    precondition(state.windows[0].frame == resized)
                    precondition(state.desktopArea.contains(resized) && resized.width >= 360 && resized.height >= 240)
                }
                samples += 1
            }
        }
        let tiled = CGRect(x: 0, y: 32, width: 597, height: 700)
        let pointer = CGPoint(x: tiled.width * 0.8, y: 44)
        let restored = TahoeWindowGeometry.restored(original, displayed: tiled, pointer: pointer, titleHeight: 53)
        precondition(abs((pointer.x - restored.minX) / restored.width - 0.8) < 0.0001,
                     "Pulling a tiled window away preserves the horizontal grab point")
        precondition(pointer.y - restored.minY == 12, "Restore preserves the vertical grab point")
        print("Desktop interaction tests passed (single-owner menus, app lifecycle, \(samples) drag/resize samples)")
    }
}
