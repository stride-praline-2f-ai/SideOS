import SwiftUI

/// Resolve presentation against the actual host scene, rather than whichever
/// foreground UIWindow happens to be returned first by UIApplication.
struct TahoeSceneWindow: UIViewRepresentable {
    let workspace: TahoeWorkspace
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.workspace = workspace; view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: Probe, context: Context) { view.workspace = workspace; view.updateMetrics() }
    final class Probe: UIView {
        weak var workspace: TahoeWorkspace?
        override func didMoveToWindow() { super.didMoveToWindow(); updateMetrics() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); updateMetrics() }
        override func layoutSubviews() { super.layoutSubviews(); updateMetrics() }
        func updateMetrics() {
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, window.isKeyWindow || self.workspace?.hostWindow == nil else { return }
                self.workspace?.hostWindow = window
                TahoeDisplayMetrics.shared.update(window: window)
            }
        }
    }
}
