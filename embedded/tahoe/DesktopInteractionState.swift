import Foundation

/// One menu owns the pointer and keyboard at a time. Switching headings keeps
/// the same presentation alive, so neither outgoing panels nor focus linger.
struct TahoeMenuSession<Bar: Equatable>: Equatable {
    private(set) var bar: Bar?
    private(set) var contextID: UUID?
    private(set) var revision = 0
    var isOpen: Bool { bar != nil || contextID != nil }

    mutating func select(_ bar: Bar?) {
        guard self.bar != bar || contextID != nil else { return }
        self.bar = bar
        contextID = nil
        revision &+= 1
    }
    mutating func showContext(_ id: UUID) {
        bar = nil
        contextID = id
        revision &+= 1
    }
    mutating func dismiss() { select(nil) }
}

/// Launch order is independent of the window stack's focus order. A container
/// is a window of its application, not another application in the Dock.
struct TahoeRunningApps: Equatable {
    struct Application: Equatable, Identifiable {
        let id: String // LiveContainer's relativeBundlePath, not CFBundleIdentifier
        var windows: [UUID]
        var dockID: String { "guest-\(id)" }
    }
    private(set) var applications: [Application] = []
    mutating func attach(_ window: UUID, to launchPath: String) {
        guard !applications.contains(where: { $0.windows.contains(window) }) else { return }
        if let index = applications.firstIndex(where: { $0.id == launchPath }) {
            applications[index].windows.append(window)
        } else { applications.append(Application(id: launchPath, windows: [window])) }
    }
    mutating func detach(_ window: UUID) {
        for index in applications.indices { applications[index].windows.removeAll { $0 == window } }
        applications.removeAll { $0.windows.isEmpty }
    }
    func application(for window: UUID) -> Application? {
        applications.first { $0.windows.contains(window) }
    }
}

/// Desktop and fullscreen use separate menu treatments. Window focus is not
/// an input: opening an ordinary window must not change the saved preference.
enum TahoeChromePolicy {
    static func showsFullscreenTrafficLights(kind: TahoeWindowKind, webApp: Bool) -> Bool {
        kind != .browser || webApp
    }
    static func clearMenu(enabled: Bool, fullscreen: Bool, reduceTransparency: Bool) -> Bool {
        enabled && !fullscreen && !reduceTransparency
    }

    static func containsRevealPointer(_ point: CGPoint, revealed: Bool,
                                      menuHeight: CGFloat, trafficWidth: CGFloat, titleHeight: CGFloat = 40) -> Bool {
        guard point.x >= 0, point.y >= 0, point.x.isFinite, point.y.isFinite else { return false }
        // The corner is reachable without hitting a six-point edge precisely.
        // Only the thin top edge and small corner own input while hidden.
        let cornerBottom = menuHeight + (revealed ? titleHeight : 0)
        return point.y <= (revealed ? menuHeight : 6) ||
            (point.x <= trafficWidth && point.y <= cornerBottom)
    }
}

/// Hover observers release only their own lease, avoiding cross-view flicker.
struct TahoeFullscreenHoverState {
    private var owners = Set<String>()
    var inside: Bool { !owners.isEmpty }
    mutating func update(_ owner: String, inside: Bool) {
        if inside { owners.insert(owner) } else { owners.remove(owner) }
    }
    mutating func reset() { owners.removeAll() }
}
