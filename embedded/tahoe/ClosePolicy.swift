import SwiftUI

/// All destructive container exits share one decision. The bridge reports only
/// whether work exists; neither this policy nor restoration collects chat text.
@MainActor enum TahoeClosePolicy {
    private static var pending = Set<UUID>()
    static func perform(owner: UUID, protectedCount: Int, title: String,
                        cancel: @escaping () -> Void = {}, action: @escaping () -> Void) {
        guard protectedCount > 0 else { action(); return }
        guard pending.insert(owner).inserted else { cancel(); return }
        TahoeDialogCoordinator.shared.dialog = TahoeDialog(
            title: title,
            message: "\(protectedCount) tab\(protectedCount == 1 ? " contains" : "s contain") unsent changes, an active response or a conversation without a saved address. Continuing may discard that work. Saved conversations are not deleted.",
            symbol: "exclamationmark.bubble", primary: "Continue", destructive: true,
            accept: { _ in pending.remove(owner); action() },
            reject: { pending.remove(owner); cancel() })
    }
}
