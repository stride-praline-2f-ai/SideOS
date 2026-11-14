// Native adaptation of macos-ui's window state transitions; see Notices/.
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum TahoeWindowKind: String, Codable, CaseIterable, Hashable, Sendable { case browser, applications, files, settings, notes, calculator, downloads, guest, utilities, installer, livecontainer }
enum TahoeWindowLayout: String, Codable, CaseIterable, Sendable {
    case floating, maximized, left, right, thirdLeft, thirdCenter, thirdRight, topLeft, topRight, bottomLeft, bottomRight
    var title: String {
        switch self {
        case .floating: return "Restore Size"
        case .maximized: return "Fill"
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .thirdLeft: return "Left Third"
        case .thirdCenter: return "Center Third"
        case .thirdRight: return "Right Third"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        }
    }
}
enum TahoeChromeMetrics {
    static let menuHeight: CGFloat = 30
    static let menuGutter: CGFloat = 2
    static let workTop = menuHeight + menuGutter
}
enum TahoeResizeEdge: CaseIterable { case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }

struct TahoeWindow: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    let kind: TahoeWindowKind
    var frame: CGRect
    var layout: TahoeWindowLayout = .floating
    var minimized = false
    var resourceID: String?
    var space: Int = 0
    var preferredFrame: CGRect?
    var alwaysOnTop: Bool?
    var applicationID: String?
    var allSpaces: Bool?
    /// Connection-local placement. The original local frame/layout is retained
    /// so disconnecting or restoring a saved workspace never strands a window.
    var onWirelessDisplay: Bool?
    /// Pinned websites retain their launch URL across restoration.
    var isWebApp: Bool { kind == .browser && resourceID.map { $0.hasPrefix("https://") || $0.hasPrefix("http://") } == true }
}

/// Pure state: UI objects, guest processes and browser sessions live elsewhere.
/// Array order is back-to-front. Fullscreen never replaces the window's identity.
struct TahoeWindowState {
    private(set) var windows: [TahoeWindow] = []
    private(set) var activeID: UUID?
    private(set) var fullscreenID: UUID?
    private(set) var canvas = CGSize(width: 1024, height: 768)
    private(set) var currentSpace = 0
    private(set) var spaceCount = 3
    private(set) var desktopExposed = false
    private(set) var dockInset: CGFloat = 90
    private(set) var tileFraction: CGFloat = 0.5
    private(set) var menuHeight: CGFloat = TahoeChromeMetrics.menuHeight
    private(set) var prefersFilledWindows = false
    private(set) var compactDesktop = true
    private(set) var wirelessCanvas: CGSize?
    private(set) var wirelessActiveID: UUID?
    mutating func setWirelessCanvas(_ size: CGSize?) {
        if let size {
            guard size.width.isFinite, size.height.isFinite,
                  (240...4096).contains(size.width), (240...4096).contains(size.height) else { return }
            wirelessCanvas = size
        } else {
            wirelessCanvas = nil; wirelessActiveID = nil
            for index in windows.indices { windows[index].onWirelessDisplay = nil }
        }
    }
    mutating func moveToWirelessDisplay(_ id: UUID, enabled: Bool) {
        guard !enabled || wirelessCanvas != nil,
              let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].onWirelessDisplay = enabled ? true : nil
        if fullscreenID == id { fullscreenID = nil }
        if enabled { wirelessActiveID = id }
        else if wirelessActiveID == id { wirelessActiveID = windows.last(where: { $0.onWirelessDisplay == true && !$0.minimized })?.id }
        focus(id)
    }
    private mutating func repairWirelessFocus() {
        if !windows.contains(where: { $0.id == wirelessActiveID && $0.onWirelessDisplay == true && !$0.minimized }) {
            wirelessActiveID = windows.last(where: { $0.onWirelessDisplay == true && !$0.minimized })?.id
        }
    }
    private var workTop: CGFloat { menuHeight + TahoeChromeMetrics.menuGutter }
    mutating func setViewportChrome(menuHeight: CGFloat, prefersFilled: Bool, compact: Bool = true) {
        self.menuHeight = min(48, max(30, menuHeight)); prefersFilledWindows = prefersFilled
        compactDesktop = compact
    }
    var displayedTileFraction: CGFloat {
        guard workArea.width >= 720 else { return 0.5 }
        return min(1 - 360 / workArea.width, max(360 / workArea.width, tileFraction))
    }

    var workArea: CGRect {
        CGRect(x: 0, y: workTop, width: canvas.width, height: max(1, canvas.height - workTop - dockInset))
    }
    /// Floating windows may extend underneath the floating Dock. Fill/tile
    /// deliberately use workArea so their controls stay above it.
    var desktopArea: CGRect { CGRect(x: 0, y: workTop, width: canvas.width, height: max(1, canvas.height - workTop)) }

    mutating func activateDesktop() { activeID = nil }

    mutating func setDockInset(_ inset: CGFloat) {
        guard inset.isFinite, inset >= 0, dockInset != inset else { return }
        dockInset = min(240, inset)
        // Only Fill/Tile use this inset. Floating restore frames must not move
        // when Dock contents or automatic sizing changes.
    }

    mutating func setCanvas(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
        let changed = canvas != size; canvas = size
        for index in windows.indices {
            let desired = changed ? windows[index].preferredFrame ?? windows[index].frame : windows[index].frame
            let fitted = constrain(desired)
            if changed { windows[index].preferredFrame = desired == fitted ? nil : desired }
            windows[index].frame = fitted
        }
    }

    @discardableResult mutating func open(_ kind: TahoeWindowKind, title: String, resourceID: String? = nil) -> UUID {
        let id = UUID()
        // Fit new windows above the Dock and cascade from the center. Existing
        // saved frames and deliberate manual sizing remain unchanged.
        let area = workArea
        let preferred: CGSize
        switch kind {
        case .calculator: preferred = CGSize(width: 360, height: 470)
        case .settings: preferred = CGSize(width: 680, height: 520)
        case .files, .downloads: preferred = CGSize(width: 720, height: 480)
        case .installer: preferred = CGSize(width: 760, height: 560)
        default: preferred = CGSize(width: compactDesktop ? 760 : 800, height: 530)
        }
        let fraction: CGFloat = compactDesktop ? 0.88 : 0.94
        let size = CGSize(width: min(area.width, max(min(360, area.width), min(preferred.width, area.width * fraction))),
                          height: min(area.height, max(min(240, area.height), min(preferred.height, area.height * fraction))))
        let step = CGFloat(windows.filter { !$0.minimized && $0.space == currentSpace }.count % 5) * 18
        let x = min(area.maxX - size.width, area.midX - size.width / 2 + step)
        let y = min(area.maxY - size.height, area.midY - size.height / 2 + step)
        let frame = constrain(CGRect(origin: CGPoint(x: x, y: y), size: size))
        windows.append(TahoeWindow(id: id, title: title, kind: kind, frame: frame, resourceID: resourceID, space: currentSpace))
        if prefersFilledWindows && kind != .calculator { windows[windows.count - 1].layout = .maximized }
        focus(id)
        return id
    }

    mutating func focus(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        var window = windows.remove(at: index)
        if window.allSpaces != true { currentSpace = window.space }
        desktopExposed = false
        window.minimized = false
        windows.append(window)
        activeID = id
        if window.onWirelessDisplay == true { wirelessActiveID = id }
        if fullscreenID != id { fullscreenID = nil }
    }

    /// A tap bubbling from a child control must never undo its minimise/close
    /// action. Explicit Dock activation still uses focus(_:), which restores.
    mutating func focusVisible(_ id: UUID) {
        guard let window = windows.first(where: { $0.id == id }), isVisible(window) else { return }
        focus(id)
    }

    mutating func close(_ id: UUID) {
        windows.removeAll { $0.id == id }
        repairWirelessFocus()
        if fullscreenID == id { fullscreenID = nil }
        if activeID == id { activeID = windows.last(where: { !$0.minimized && belongs($0, to: currentSpace) })?.id }
    }

    mutating func minimize(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].minimized = true
        repairWirelessFocus()
        if fullscreenID == id { fullscreenID = nil }
        if activeID == id { activeID = windows.last(where: { !$0.minimized && belongs($0, to: currentSpace) })?.id }
    }

    mutating func setLayout(_ layout: TahoeWindowLayout, for id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].layout = layout
        focus(id)
    }

    mutating func toggleMaximize(_ id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        setLayout(window.layout == .maximized ? .floating : .maximized, for: id)
    }

    mutating func toggleFullscreen(_ id: UUID) {
        guard windows.contains(where: { $0.id == id }) else { return }
        // The display-only projection already fills its independent canvas.
        // Never make its identity the primary display's fullscreen owner.
        if windows.first(where: { $0.id == id })?.onWirelessDisplay == true { focus(id); return }
        let wasFullscreen = fullscreenID == id
        focus(id)
        fullscreenID = wasFullscreen ? nil : id
    }

    func displayFrame(_ window: TahoeWindow) -> CGRect {
        if window.onWirelessDisplay == true, let wirelessCanvas { return CGRect(origin: .zero, size: wirelessCanvas) }
        if fullscreenID == window.id { return CGRect(origin: .zero, size: canvas) }
        return window.layout == .floating ? window.frame : layoutFrame(window.layout)
    }
    func canApply(_ layout: TahoeWindowLayout) -> Bool {
        switch layout {
        case .floating, .maximized: return true
        case .thirdLeft, .thirdCenter, .thirdRight: return workArea.width >= 1080 && workArea.height >= 240
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return workArea.width >= 720 && workArea.height >= 480
        default: return workArea.width >= 720 && workArea.height >= 240
        }
    }
    func layoutFrame(_ layout: TahoeWindowLayout) -> CGRect {
        let a = workArea
        guard canApply(layout) else { return a }
        switch layout {
        case .left: return CGRect(x: a.minX, y: a.minY, width: a.width * displayedTileFraction, height: a.height)
        case .right: return CGRect(x: a.minX + a.width * displayedTileFraction, y: a.minY, width: a.width * (1 - displayedTileFraction), height: a.height)
        case .thirdLeft, .thirdCenter, .thirdRight:
            let column: CGFloat = layout == .thirdLeft ? 0 : layout == .thirdCenter ? 1 : 2
            return CGRect(x: a.minX + column * a.width / 3, y: a.minY, width: a.width / 3, height: a.height)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let right = layout == .topRight || layout == .bottomRight
            let bottom = layout == .bottomLeft || layout == .bottomRight
            return CGRect(x: right ? a.midX : a.minX, y: bottom ? a.midY : a.minY, width: a.width / 2, height: a.height / 2)
        default: return a
        }
    }
    mutating func setTileFraction(_ value: CGFloat) {
        guard value.isFinite, workArea.width >= 720 else { return }
        tileFraction = min(1 - 360 / workArea.width, max(360 / workArea.width, value))
    }
    mutating func setAlwaysOnTop(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].alwaysOnTop = !(windows[index].alwaysOnTop ?? false)
    }
    mutating func setFrame(_ frame: CGRect, for id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].frame = constrain(frame); windows[index].preferredFrame = nil
    }
    mutating func setResource(_ resource: String?, for id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }; windows[index].resourceID = resource
    }
    mutating func setApplication(_ path: String, for id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }; windows[index].applicationID = path
    }

    func isVisible(_ window: TahoeWindow) -> Bool {
        guard !desktopExposed, belongs(window, to: currentSpace), !window.minimized else { return false }
        if window.onWirelessDisplay == true { return wirelessCanvas != nil && wirelessActiveID == window.id }
        return fullscreenID == nil || fullscreenID == window.id
    }

    func belongs(_ window: TahoeWindow, to space: Int) -> Bool { window.allSpaces == true || window.space == space }
    mutating func toggleAllSpaces(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].allSpaces = !(windows[index].allSpaces ?? false)
        if windows[index].allSpaces != true { windows[index].space = currentSpace }
    }

    mutating func showDesktop() {
        desktopExposed.toggle(); fullscreenID = nil
        activeID = desktopExposed ? nil : windows.last(where: { !$0.minimized && belongs($0, to: currentSpace) })?.id
    }

    mutating func switchSpace(_ space: Int) {
        guard (0..<spaceCount).contains(space) else { return }
        currentSpace = space
        fullscreenID = nil
        desktopExposed = false
        activeID = windows.last(where: { !$0.minimized && belongs($0, to: space) })?.id
    }

    mutating func addSpace() { if spaceCount < 6 { spaceCount += 1; switchSpace(spaceCount - 1) } }

    mutating func removeSpace(_ space: Int) {
        guard spaceCount > 1, (0..<spaceCount).contains(space) else { return }
        let fallback = max(0, space - 1)
        for index in windows.indices {
            if windows[index].space == space { windows[index].space = fallback }
            else if windows[index].space > space { windows[index].space -= 1 }
        }
        let next = currentSpace == space ? fallback : currentSpace > space ? currentSpace - 1 : currentSpace
        spaceCount -= 1
        switchSpace(next)
    }

    mutating func moveToSpace(_ id: UUID, space: Int) {
        guard (0..<spaceCount).contains(space), let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].space = space; windows[index].allSpaces = false
        switchSpace(currentSpace)
    }

    mutating func cycleFocus() {
        let visible = windows.filter { !$0.minimized && belongs($0, to: currentSpace) }
        if let first = visible.first { focus(first.id) }
    }

    mutating func rename(_ id: UUID, title: String) {
        if let index = windows.firstIndex(where: { $0.id == id }) { windows[index].title = String(title.prefix(120)) }
    }

    mutating func restore(_ saved: [TahoeWindow], active: UUID?, space: Int, spaces: Int) {
        spaceCount = min(6, max(1, spaces))
        currentSpace = min(spaceCount - 1, max(0, space))
        var seen: Set<UUID> = []
        windows = saved.filter { window in
            let f = window.frame
            return window.kind != .guest && seen.insert(window.id).inserted &&
                [f.minX, f.minY, f.width, f.height].allSatisfy { $0.isFinite } && f.width > 0 && f.height > 0
        }.map { window in
            var window = window
            window.onWirelessDisplay = nil
            let desired = window.preferredFrame ?? window.frame
            window.frame = constrain(desired)
            window.preferredFrame = window.frame == desired ? nil : desired
            window.space = min(spaceCount - 1, max(0, window.space))
            return window
        }
        activeID = windows.first(where: { $0.id == active && !$0.minimized && belongs($0, to: currentSpace) })?.id ??
            windows.last(where: { !$0.minimized && belongs($0, to: currentSpace) })?.id
        fullscreenID = nil
        desktopExposed = false
    }

    mutating func move(_ id: UUID, from initial: CGRect, translation: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }), fullscreenID == nil else { return }
        windows[index].layout = .floating
        windows[index].preferredFrame = nil
        windows[index].frame = TahoeWindowGeometry.moved(initial, translation: translation, area: desktopArea)
    }

    mutating func resize(_ id: UUID, from initial: CGRect, edge: TahoeResizeEdge, translation: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }), fullscreenID == nil else { return }
        windows[index].layout = .floating
        windows[index].preferredFrame = nil
        windows[index].frame = TahoeWindowGeometry.resized(initial, edge: edge, translation: translation, area: desktopArea)
    }

    private func constrain(_ frame: CGRect) -> CGRect {
        let width = min(max(360, frame.width), desktopArea.width)
        let height = min(max(240, frame.height), desktopArea.height)
        return CGRect(x: min(max(desktopArea.minX, frame.minX), desktopArea.maxX - width),
                      y: min(max(desktopArea.minY, frame.minY), desktopArea.maxY - height), width: width, height: height)
    }
}

/// The same arithmetic drives the live surface and the committed window frame.
/// No window-array copy, persistence work or layout-state publication per sample.
enum TahoeWindowGeometry {
    static func moved(_ initial: CGRect, translation: CGSize, area: CGRect) -> CGRect {
        let frame = initial.offsetBy(dx: translation.width, dy: translation.height)
        let visibleTitle: CGFloat = min(100, frame.width)
        return CGRect(x: min(max(area.minX - frame.width + visibleTitle, frame.minX), area.maxX - visibleTitle),
                      y: min(max(area.minY, frame.minY), max(area.minY, area.maxY - 38)),
                      width: frame.width, height: frame.height)
    }
    static func restored(_ saved: CGRect, displayed: CGRect, pointer: CGPoint, titleHeight: CGFloat) -> CGRect {
        let fraction = min(1, max(0, (pointer.x - displayed.minX) / max(1, displayed.width)))
        return CGRect(x: pointer.x - saved.width * fraction,
                      y: pointer.y - min(titleHeight, max(0, pointer.y - displayed.minY)),
                      width: saved.width, height: saved.height)
    }
    static func resized(_ initial: CGRect, edge: TahoeResizeEdge, translation: CGSize, area: CGRect) -> CGRect {
        let minimum = CGSize(width: min(360, area.width), height: min(240, area.height))
        var left = initial.minX, right = initial.maxX, top = initial.minY, bottom = initial.maxY
        switch edge {
        case .left, .topLeft, .bottomLeft: left = min(max(area.minX, left + translation.width), right - minimum.width)
        case .right, .topRight, .bottomRight: right = max(min(area.maxX, right + translation.width), left + minimum.width)
        default: break
        }
        switch edge {
        case .top, .topLeft, .topRight: top = min(max(area.minY, top + translation.height), bottom - minimum.height)
        case .bottom, .bottomLeft, .bottomRight: bottom = max(min(area.maxY, bottom + translation.height), top + minimum.height)
        default: break
        }
        let width = min(max(minimum.width, right - left), area.width)
        let height = min(max(minimum.height, bottom - top), area.height)
        return CGRect(x: min(max(area.minX, left), area.maxX - width),
                      y: min(max(area.minY, top), area.maxY - height), width: width, height: height)
    }
}
