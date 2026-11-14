import SwiftUI

/// Public UIKit can observe delivered direct-touch gestures. System-reserved
/// trackpad swipes are not intercepted or remapped by this app.
struct TahoeOverviewGestureObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) { }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }
    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        private weak var host: UIWindow?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard host !== window else { return }
            detach(); host = window
            pan.minimumNumberOfTouches = 3; pan.maximumNumberOfTouches = 4
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pan.cancelsTouchesInView = false; pan.delegate = self
            window?.addGestureRecognizer(pan)
        }
        func detach() { host?.removeGestureRecognizer(pan); host = nil }
        @objc private func swiped(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let delta = recognizer.translation(in: host)
            guard abs(delta.y) > 70, abs(delta.y) > abs(delta.x) * 1.3 else { return }
            let workspace = TahoeWorkspace.shared
            if delta.y < 0 { if workspace.overlay != .overview { workspace.present(.overview) } }
            else if workspace.overlay == .overview { workspace.overlay = nil }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
