import SwiftUI
import UniformTypeIdentifiers

struct TahoeBrowserTabFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

/// Attach one native drag interaction to the host window, with strict hit
/// regions for this tab strip. Ordinary button taps and keyboard focus remain
/// SwiftUI-owned. UIKit delivers end/cancel even when a drop is rejected.
struct TahoeNativeTabDrag: UIViewRepresentable {
    let session: TahoeBrowserSession
    let frames: [UUID: CGRect]
    func makeUIView(context: Context) -> Host { let view = Host(); view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: Host, context: Context) { view.session = session; view.frames = frames; view.install() }
    static func dismantleUIView(_ view: Host, coordinator: ()) { view.detach() }
    final class Host: UIView, UIDragInteractionDelegate {
        weak var session: TahoeBrowserSession?
        var frames: [UUID: CGRect] = [:]
        private weak var owner: UIWindow?
        private var token: String?
        private lazy var interaction = UIDragInteraction(delegate: self)
        override func didMoveToWindow() { super.didMoveToWindow(); install() }
        func install() {
            guard owner !== window else { return }; detach(); owner = window
            interaction.isEnabled = true; window?.addInteraction(interaction)
        }
        func detach() { owner?.removeInteraction(interaction); owner = nil }
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning drag: UIDragSession) -> [UIDragItem] {
            guard let session, let owner else { return [] }
            let workspace = TahoeWorkspace.shared
            guard let id = workspace.browsers.first(where: { $0.value === session })?.key,
                  workspace.state.activeID == id,
                  let window = workspace.state.windows.first(where: { $0.id == id }), workspace.state.isVisible(window) else { return [] }
            let point = drag.location(in: owner)
            guard let hit = frames.first(where: { $0.value.insetBy(dx: 0, dy: 0).contains(point) && point.x > $0.value.minX + 32 }),
                  session.visibleTabs.contains(where: { $0.id == hit.key }) else { return [] }
            let token = UUID().uuidString; self.token = token
            let strip = frames.values.reduce(CGRect.null) { $0.union($1) }
            TahoeWorkspace.shared.beginTabTransfer(hit.key, session: session, token: token, strip: strip)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "com.aault.tahoe.browser-tab", visibility: .ownProcess) { completion in completion(Data(token.utf8), nil); return nil }
            return [UIDragItem(itemProvider: provider)]
        }
        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
            let workspace = TahoeWorkspace.shared
            if workspace.tabTransfer?.token == token, workspace.tabTransfer?.accepted != true { workspace.tabTransfer = nil }
            token = nil
        }
        func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
        required init?(coder: NSCoder) { nil }
        override init(frame: CGRect) { super.init(frame: frame) }
    }
}

struct TahoeBrowserTabBarDrop: DropDelegate {
    let windowID: UUID
    let before: UUID
    func validateDrop(info: DropInfo) -> Bool { TahoeWorkspace.shared.tabTransfer != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        let workspace = TahoeWorkspace.shared
        guard let transfer = workspace.tabTransfer,
              let provider = info.itemProviders(for: ["com.aault.tahoe.browser-tab"]).first else { return false }
        workspace.tabTransfer?.accepted = true
        provider.loadDataRepresentation(forTypeIdentifier: "com.aault.tahoe.browser-tab") { data, _ in
            DispatchQueue.main.async {
                guard workspace.tabTransfer?.token == transfer.token else { return }
                workspace.tabTransfer = nil
                guard let data, data.count <= 64, String(data: data, encoding: .utf8) == transfer.token else { return }
                _ = workspace.moveTransfer(transfer, to: windowID, before: before)
            }
        }
        return true
    }
}
