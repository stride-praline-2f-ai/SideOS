import SwiftUI

struct TahoeBrowserTabTransfer {
    let tabID: UUID
    let windowID: UUID
    let token: String
    let strip: CGRect
    weak var chats: TahoeChatWorkspace? = nil
    var accepted = false
}

/// The private, process-local drag token lets the desktop accept a tab without
/// interpreting external URLs or copying a page into a fresh web view.
struct TahoeBrowserTabDesktopDrop: DropDelegate {
    let workspace: TahoeWorkspace
    func validateDrop(info: DropInfo) -> Bool {
        workspace.tabTransfer != nil && info.hasItemsConforming(to: ["com.aault.tahoe.browser-tab"])
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let transfer = workspace.tabTransfer,
              !transfer.strip.insetBy(dx: -12, dy: -24).contains(info.location),
              let provider = info.itemProviders(for: ["com.aault.tahoe.browser-tab"]).first else { return false }
        let point = info.location
        workspace.tabTransfer?.accepted = true
        provider.loadDataRepresentation(forTypeIdentifier: "com.aault.tahoe.browser-tab") { data, _ in
            let valid = data.map { $0.count <= 64 && String(data: $0, encoding: .utf8) == transfer.token } ?? false
            DispatchQueue.main.async {
                guard workspace.tabTransfer?.token == transfer.token else { return }
                workspace.tabTransfer = nil
                guard valid else { return }
                if let chats = transfer.chats { workspace.detachChat(chats, id: transfer.tabID, screenPoint: point) }
                else { workspace.detachBrowserTab(transfer.tabID, from: transfer.windowID, screenPoint: point) }
            }
        }
        return true
    }
}
