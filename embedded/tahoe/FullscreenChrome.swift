import SwiftUI

/// Presentation only: revealing chrome never changes the guest/web view's bounds.
@MainActor
final class TahoeFullscreenChrome: ObservableObject {
    static let shared = TahoeFullscreenChrome()
    @Published private(set) var revealed = false
    private var hover = TahoeFullscreenHoverState()
    private var pointerInside: Bool { hover.inside }
    var menuOpen = false { didSet { scheduleHide() } }
    private var popoverOwners = Set<UUID>()
    private var editingOwners = Set<UUID>()
    var browserPopoverOpen: Bool { !popoverOwners.isEmpty }
    var editing: Bool { !editingOwners.isEmpty }
    func setPopover(_ owner: UUID, open: Bool) { if open { popoverOwners.insert(owner) } else { popoverOwners.remove(owner) }; scheduleHide() }
    func setEditing(_ owner: UUID, active: Bool) { if active { editingOwners.insert(owner) } else { editingOwners.remove(owner) }; scheduleHide() }
    private var pending: Task<Void, Never>?

    func reset() {
        pending?.cancel(); pending = nil
        revealed = false; hover.reset(); menuOpen = false; popoverOwners.removeAll(); editingOwners.removeAll()
    }
    // Touch or swipe revelation remains usable without a hovering pointer.
    func reveal() { if !revealed { revealed = true }; scheduleHide(delay: .seconds(2)) }
    // The full-width menu strip and the top-left traffic lights are the
    // only sticky fullscreen reveal regions. The rest of the browser
    // toolbar/content must not keep the menu bar on screen.
    func pointer(location: CGPoint?, owner: String = "desktop") {
        let inside = location.map { point in
            TahoeChromePolicy.containsRevealPointer(point, revealed: revealed,
                menuHeight: TahoeDesign.menuBarHeight, trafficWidth: TahoeDesign.trafficInset, titleHeight: max(40, TahoeDesign.titleHeight))
        } ?? false
        let wasInside = pointerInside
        hover.update(owner, inside: inside)
        if pointerInside {
            if !wasInside || !revealed { reveal() }
        } else if wasInside { scheduleHide(delay: .milliseconds(220)) }
    }
    private func scheduleHide(delay: Duration = .milliseconds(240)) {
        pending?.cancel(); pending = nil
        guard revealed, !pointerInside, !menuOpen, !browserPopoverOpen, !editing else { return }
        pending = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.revealed = false
        }
    }
}

struct TahoeFullscreenReveal: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var chrome = TahoeFullscreenChrome.shared
    var body: some View {
        VStack(spacing: 0) {
            if chrome.revealed {
                TahoeMenuBar(workspace: workspace).background(.black).environment(\.colorScheme, .dark)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): chrome.pointer(location: location, owner: "menu")
                        case .ended: chrome.pointer(location: nil, owner: "menu")
                        }
                    }
                .onDisappear { chrome.pointer(location: nil, owner: "menu") }
            } else {
                VStack(spacing: 0) {
                    revealTarget(width: nil, height: 6, y: 0)
                    HStack(spacing: 0) {
                        revealTarget(width: TahoeDesign.trafficInset, height: TahoeDesign.menuBarHeight - 6, y: 6)
                        Spacer().allowsHitTesting(false)
                    }
                }
            }
            Spacer().allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            TahoeFullscreenTouchControls(workspace: workspace).padding(12)
        }
    }
    private func revealTarget(width: CGFloat?, height: CGFloat, y: CGFloat) -> some View {
        Button { chrome.reveal() } label: {
            Color.clear.frame(width: width, height: height).contentShape(Rectangle())
        }
        .buttonStyle(TahoePressStyle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): chrome.pointer(location: CGPoint(x: location.x, y: location.y + y), owner: "reveal-\(y)")
            case .ended: chrome.pointer(location: nil, owner: "reveal-\(y)")
            }
        }
        .onDisappear { chrome.pointer(location: nil, owner: "reveal-\(y)") }
        .accessibilityLabel("Show fullscreen controls")
        .accessibilityIdentifier(y == 0 ? "fullscreen-reveal" : "fullscreen-corner-reveal")
        .gesture(DragGesture(minimumDistance: 2).onChanged { _ in chrome.reveal() })
    }

}

/// Host-owned controls sit above every guest surface. They require no mouse,
/// remain discoverable when the menu auto-hides, and never resize a live app.
private struct TahoeFullscreenTouchControls: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var chrome = TahoeFullscreenChrome.shared
    @State private var expanded = false
    @State private var owner = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if expanded, let id = workspace.state.fullscreenID,
               let window = workspace.state.windows.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(window.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 8) {
                        command("minus", "Minimise", id: "fullscreen-minimize") { workspace.minimize(id) }
                        command("arrow.down.right.and.arrow.up.left", "Restore", id: "fullscreen-restore") { workspace.state.toggleFullscreen(id) }
                        command("rectangle.on.rectangle", "Windows", id: "fullscreen-windows") { workspace.present(.overview) }
                        command("xmark", "Close", id: "fullscreen-close") { workspace.close(id) }
                    }.tahoeGlassGroup(spacing: 8)
                }.padding(12).modifier(TahoeGlass(radius: 22))
            }
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.down" : "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 44).contentShape(Capsule())
            }.buttonStyle(TahoePressStyle(surface: true, radius: 100))
                .accessibilityLabel(expanded ? "Hide window controls" : "Window controls: minimise, restore or close")
                .accessibilityIdentifier("fullscreen-touch-controls")
        }
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.9), value: expanded)
        .onChange(of: expanded) { _, open in
            chrome.setPopover(owner, open: open)
        }
        .onChange(of: workspace.state.fullscreenID) { _, _ in collapse() }
        .onChange(of: workspace.overlay) { _, _ in collapse() }
        .onDisappear { chrome.setPopover(owner, open: false) }
    }
    private func collapse() { expanded = false; chrome.setPopover(owner, open: false) }
    private func command(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button { collapse(); action() } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                Text(title).font(.system(size: 10)).lineLimit(1)
            }.frame(width: 54).padding(.vertical, 4).contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(TahoePressStyle(surface: true, radius: 14))
            .accessibilityLabel(title + " fullscreen window").accessibilityIdentifier(id)
    }
}

/// Observe UIKit hover delivery even when a hosted guest handles the content's
/// SwiftUI pointer events. This observer does not intercept touch or clicks.
struct TahoeFullscreenPointerObserver: UIViewRepresentable {
    let enabled: Bool
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) { view.enabled = enabled }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }
    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var enabled = false
        private weak var observedWindow: UIWindow?
        private lazy var hover = UIHoverGestureRecognizer(target: self, action: #selector(moved(_:)))
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard observedWindow !== window else { return }
            detach()
            observedWindow = window
            hover.cancelsTouchesInView = false
            hover.delegate = self
            window?.addGestureRecognizer(hover)
        }
        func detach() { observedWindow?.removeGestureRecognizer(hover); observedWindow = nil; TahoeFullscreenChrome.shared.pointer(location: nil, owner: "window") }
        @objc private func moved(_ recognizer: UIHoverGestureRecognizer) {
            guard enabled else { return }
            let location: CGPoint? = recognizer.state == .ended || recognizer.state == .cancelled ? nil : recognizer.location(in: self)
            TahoeFullscreenChrome.shared.pointer(location: location, owner: "window")
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

