import SwiftUI

/// The upstream tab/navigation tree is created once. Parking it between window
/// openings keeps app delegates, imports and navigation state alive.
@MainActor final class TahoeManagementHost: ObservableObject {
    private var controller: UIHostingController<AnyView>?
    private weak var parking: UIViewController?
    private weak var destination: UIViewController?
    func configure(_ content: AnyView, parking: UIViewController) {
        self.parking = parking
        if let controller { controller.rootView = content }
        else { controller = UIHostingController(rootView: content) }
        move(to: destination ?? parking)
    }
    func show(in parent: UIViewController) { destination = parent; move(to: parent) }
    func park(from parent: UIViewController) {
        guard destination === parent else { return }
        destination = nil
        if let parking { move(to: parking) }
    }
    private func move(to parent: UIViewController) {
        guard let controller else { return }
        let oldSize = controller.view.bounds.size
        if controller.parent !== parent {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            parent.addChild(controller)
            parent.view.addSubview(controller.view)
            controller.didMove(toParent: parent)
        }
        if parent === parking {
            let size = oldSize.width > 1 && oldSize.height > 1 ? oldSize : TahoeWorkspace.shared.state.canvas
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.autoresizingMask = []
        } else {
            controller.view.frame = parent.view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        controller.view.clipsToBounds = true
    }
}

private struct TahoeManagementHostKey: EnvironmentKey {
    static let defaultValue: TahoeManagementHost? = nil
}
extension EnvironmentValues {
    var tahoeManagementHost: TahoeManagementHost? {
        get { self[TahoeManagementHostKey.self] }
        set { self[TahoeManagementHostKey.self] = newValue }
    }
}

struct TahoeManagementBootstrap: UIViewControllerRepresentable {
    let host: TahoeManagementHost
    let content: AnyView
    func makeUIViewController(context: Context) -> UIViewController {
        let parent = UIViewController()
        host.configure(content, parking: parent)
        return parent
    }
    func updateUIViewController(_ parent: UIViewController, context: Context) { host.configure(content, parking: parent) }
}

struct TahoeManagementWindow: UIViewControllerRepresentable {
    @Environment(\.tahoeManagementHost) private var host
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var host: TahoeManagementHost? }
    func makeUIViewController(context: Context) -> UIViewController {
        let parent = UIViewController()
        context.coordinator.host = host
        host?.show(in: parent)
        return parent
    }
    func updateUIViewController(_ parent: UIViewController, context: Context) {
        context.coordinator.host = host
        host?.show(in: parent)
    }
    static func dismantleUIViewController(_ parent: UIViewController, coordinator: Coordinator) { coordinator.host?.park(from: parent) }
}
