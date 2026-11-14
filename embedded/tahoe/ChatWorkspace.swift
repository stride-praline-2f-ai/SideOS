import SwiftUI
import WebKit
import CoreFoundation

/// Every conversation is an ordinary browser page with the owning profile's
/// data store. The host is only a workspace; pages can be transferred intact.
@MainActor
final class TahoeChatWorkspace: ObservableObject {
    weak var host: TahoeBrowserTab?
    @Published private(set) var state: TahoeChatWorkspaceState
    private(set) var pages: [UUID: TahoeBrowserTab] = [:]
    weak var surface: TahoeChatSurfaceView?
    private var ready: Set<UUID> = []
    private var contentWidth: Double = 0
    private var viewportWidth: CGFloat = 1
    private var paneRect = CGRect.zero
    private var tabFrames: [UUID: CGRect] = [:]
    private var stripFrame = CGRect.zero
    private var dragDelegates: [UUID: TahoeChatTabDrag] = [:]
    private var lastConfigurations: [UUID: String] = [:]
    private var documents: [UUID: String] = [:]
    private var isRefreshing = false
    private var isDisposed = false

    var focusedPage: TahoeBrowserTab? { pages[state.focused] }
    var saved: TahoeSavedChatWorkspace { state.saved }
    var canHibernate: Bool { !state.items.contains(where: \.hasProtectedWork) }
    var protectedCount: Int { state.items.filter(\.hasProtectedWork).count }

    init(host: TahoeBrowserTab, initial: TahoeBrowserTab, saved: TahoeSavedChatWorkspace?) {
        self.host = host
        state = saved.flatMap { TahoeChatWorkspaceState(saved: $0, firstID: initial.id) }
            ?? TahoeChatWorkspaceState(id: initial.id, url: initial.currentURL ?? TahoeChatWorkspaceState.home)
        pages[initial.id] = initial
        wire(initial)
        for item in state.items where item.id != initial.id {
            let page = host.makeChatPage(id: item.id, url: item.url)
            wire(page); pages[item.id] = page
        }
    }
    private func wire(_ page: TahoeBrowserTab) {
        page.workspace = host?.workspace
        page.chatOwner = self
        page.openTab = host?.openTab
        page.requestClose = { [weak self, weak page] in if let page { self?.close(page.id) } }
        page.changed = { [weak self] in self?.changed() }
    }
    func activate() { changed() }
    func selectChat(_ id: UUID) { state.select(id); changed() }
    func canAdopt(_ page: TahoeBrowserTab) -> Bool {
        guard let host, page.chatWorkspace == nil, page.profile == host.profile,
              page.dataStoreForTransfer === host.dataStoreForTransfer, let url = page.currentURL, TahoeChatWorkspaceState.allows(url) else { return false }
        return TahoeChatWorkspaceState.conversationKey(url).map { key in !state.items.contains { TahoeChatWorkspaceState.conversationKey($0.url) == key } } ?? true
    }
    func adopt(_ page: TahoeBrowserTab, before target: UUID?) {
        guard let url = page.currentURL, state.adopt(id: page.id, url: url, title: page.title, before: target) else { return }
        let work = page.transferredChatState
        state.update(page.id, url: url, title: page.title, hasDraft: work?.hasDraft ?? page.hasDirtyForm,
            generating: work?.generating ?? false, hasContent: work?.hasContent ?? false)
        page.transferredChatState = nil
        pages[page.id] = page; wire(page); changed()
    }
    func move(_ id: UUID, before target: UUID) { state.move(id, before: target); changed() }
    func reconnect() { for page in pages.values { wire(page) } }
    func resumePages() {
        for item in state.items where item.id != state.focused {
            pages[item.id]?.resumeIfNeeded()
        }
        pages[state.focused]?.resumeIfNeeded(priority: host?.isPresented == true)
    }

    func navigationChanged(_ page: TahoeBrowserTab, url: URL) {
        guard !isDisposed else { return }
        guard TahoeChatWorkspaceState.allows(url) else {
            // Login, account changes, projects and other sites remain ordinary
            // web navigation. Clear this workspace rather than mixing accounts.
            leave(using: page); return
        }
        if let item = state.items.first(where: { $0.id == page.id }) {
            state.update(page.id, url: url, title: page.title, hasDraft: item.hasDraft, generating: item.generating, hasContent: item.hasContent)
        }
        lastConfigurations.removeValue(forKey: page.id)
        changed()
    }
    func receive(_ body: [String: Any], from page: TahoeBrowserTab) {
        guard !isDisposed, pages[page.id] === page, let type = body["type"] as? String else { return }
        switch type {
        case "status":
            guard let raw = body["url"] as? String, let url = URL(string: raw), TahoeChatWorkspaceState.allows(url) else { return }
            if body["ready"] as? Bool == true {
                if let document = body["document"] as? String, documents[page.id] != document {
                    documents[page.id] = document; lastConfigurations.removeValue(forKey: page.id)
                }
                ready.insert(page.id)
                state.update(page.id, url: url, title: body["title"] as? String ?? "New chat",
                             hasDraft: body["hasDraft"] as? Bool == true, generating: body["generating"] as? Bool == true,
                             hasContent: body["hasContent"] as? Bool == true)
                changed()
            } else {
                ready.remove(page.id)
                if page.id == state.left { state.collapse(); paneRect = .zero }
                changed()
            }
        case "layout":
            guard page.id == state.left, let width = number(body["width"]), let viewport = number(body["viewportWidth"]),
                  width > 0, width < 30_000, viewport > 0, viewport < 30_000 else { return }
            contentWidth = width; viewportWidth = CGFloat(viewport)
            stripFrame = rectangle(body["strip"]) ?? .zero
            tabFrames = [:]
            for raw in (body["tabs"] as? [[String: Any]] ?? []).prefix(200) {
                if let value = raw["id"] as? String, let id = UUID(uuidString: value), pages[id] != nil, let frame = rectangle(raw) { tabFrames[id] = frame }
            }
            let previousRight = state.right
            state.fit(width: width)
            if let r = body["rect"] as? [String: Any], let x = number(r["x"]), let y = number(r["y"]),
               let w = number(r["width"]), let h = number(r["height"]), w >= 0, h >= 0,
               abs(x) < 30_000, abs(y) < 30_000, w < 30_000, h < 30_000 {
                paneRect = CGRect(x: x, y: y, width: w, height: h)
            } else { paneRect = .zero }
            if previousRight != state.right { changed() } else { surface?.setNeedsLayout() }
        case "focus":
            if page.id == state.left || page.id == state.right {
                let was = state.focused; state.select(page.id)
                if was != state.focused { changed() }
            }
        case "open":
            if let raw = body["url"] as? String, let url = URL(string: raw) { open(url) }
        case "new": open(TahoeChatWorkspaceState.home)
        case "reveal": state.revealed = true; changed()
        case "swap":
            state.swapPanes(); changed()
        case "select", "close", "split", "detach":
            guard let raw = body["id"] as? String, let id = UUID(uuidString: raw), pages[id] != nil else { return }
            switch type {
            case "select": state.select(id); changed()
            case "close": close(id)
            case "split":
                guard ready.contains(state.left), ready.contains(id) || pages[id]?.webView == nil else { return }
                state.split(id, width: contentWidth); changed()
            case "detach":
                let point: CGPoint?
                if let x = number(body["x"]), let y = number(body["y"]), let view = page.webView,
                   let surface, let width = number(body["viewportWidth"]), width > 0 {
                    let scale = view.bounds.width / CGFloat(width)
                    point = view.convert(CGPoint(x: x * scale, y: y * scale + max(0, -view.scrollView.contentOffset.y)), to: surface.window)
                } else { point = nil }
                TahoeWorkspace.shared.detachChat(self, id: id, screenPoint: point)
            default: break
            }
        case "collapse": state.collapse(); paneRect = .zero; changed()
        case "resize":
            if let ratio = number(body["ratio"]) { state.resize(ratio, width: contentWidth); changed() }
        case "reopen":
            if let id = state.reopen() { ensurePage(id); changed() }
        default: break
        }
    }
    private func rectangle(_ raw: Any?) -> CGRect? {
        guard let r = raw as? [String: Any], let x = number(r["x"]), let y = number(r["y"]),
              let w = number(r["width"]), let h = number(r["height"]), w > 0, h > 0,
              abs(x) < 30_000, abs(y) < 30_000, w < 30_000, h < 30_000 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    func dragTarget(at point: CGPoint, in web: WKWebView) -> (UUID, CGRect, CGRect)? {
        guard web === pages[state.left]?.webView else { return nil }
        let scale = web.bounds.width / max(1, viewportWidth)
        let offset = max(0, -web.scrollView.contentOffset.y)
        func local(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * scale, y: rect.minY * scale + offset, width: rect.width * scale, height: rect.height * scale)
        }
        guard local(stripFrame).contains(point) else { return nil }
        for (id, rect) in tabFrames {
            let frame = local(rect)
            if frame.contains(point) { return (id, frame, web.convert(local(stripFrame), to: web.window)) }
        }
        return nil
    }
    private func number(_ raw: Any?) -> Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    func open(_ url: URL) {
        guard let id = state.open(url) else { return }
        ensurePage(id); changed()
    }
    private func ensurePage(_ id: UUID) {
        guard pages[id] == nil, let host, let item = state.items.first(where: { $0.id == id }) else { return }
        let page = host.makeChatPage(id: id, url: item.url)
        wire(page); pages[id] = page
    }
    func close(_ id: UUID) {
        guard let item = state.items.first(where: { $0.id == id }) else { return }
        TahoeClosePolicy.perform(owner: id, protectedCount: item.hasProtectedWork ? 1 : 0,
            title: "Close chat tab?") { [weak self] in self?.finishClose(id) }
    }
    private func finishClose(_ id: UUID) {
        guard state.close(id, confirmed: true) else { return }
        dragDelegates.removeValue(forKey: id)?.detach()
        pages.removeValue(forKey: id)?.release()
        ready.remove(id); lastConfigurations.removeValue(forKey: id)
        ensurePage(state.left); changed()
    }
    func extract(_ id: UUID) -> TahoeBrowserTab? {
        guard let page = pages.removeValue(forKey: id) else { return nil }
        page.transferredChatState = state.items.first(where: { $0.id == id })
        dragDelegates.removeValue(forKey: id)?.detach()
        _ = state.close(id, confirmed: true)
        page.chatOwner = nil; page.changed = nil; page.requestClose = nil
        page.configureChat(["enabled": false])
        ready.remove(id); lastConfigurations.removeValue(forKey: id)
        ensurePage(state.left); changed()
        return page
    }
    func navigate(_ address: String) {
        guard let page = focusedPage else { return }
        page.address = address; page.navigate()
    }
    func leave(using page: TahoeBrowserTab, confirmed: Bool = false) {
        guard !isDisposed, let host else { return }
        if !confirmed, protectedCount > 0 {
            TahoeClosePolicy.perform(owner: host.id, protectedCount: protectedCount, title: "Leave chat workspace?") { [weak self, weak page] in
                if let page { self?.leave(using: page, confirmed: true) }
            }
            return
        }
        isDisposed = true
        page.configureChat(["enabled": false])
        page.chatOwner = nil
        host.restoreChatPage(page)
        for other in pages.values where other !== page { other.chatOwner = nil; other.release() }
        dragDelegates.values.forEach { $0.detach() }; dragDelegates.removeAll()
        pages.removeAll(); ready.removeAll(); surface = nil
        host.chatWorkspace = nil; host.restoredChatWorkspace = nil
        host.changed?()
    }
    func hibernate() {
        guard canHibernate else { return }
        for page in pages.values { page.hibernate() }
        dragDelegates.values.forEach { $0.detach() }; dragDelegates.removeAll()
        ready.removeAll(); lastConfigurations.removeAll(); paneRect = .zero
        host?.objectWillChange.send()
    }
    func release() {
        guard !isDisposed else { return }
        isDisposed = true
        for page in pages.values { page.chatOwner = nil; page.release() }
        dragDelegates.values.forEach { $0.detach() }; dragDelegates.removeAll()
        pages.removeAll(); surface = nil
    }
    func changed() {
        guard !isDisposed, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for id in [state.left, state.right].compactMap({ $0 }) {
            ensurePage(id)
            pages[id]?.resumeIfNeeded(priority: id == state.focused && host?.isPresented == true)
        }
        resumePages()
        for (id, page) in pages {
            let payload: [String: Any] = ["enabled": true, "role": id == state.right ? "secondary" : "primary",
                "items": state.items.map { ["id": $0.id.uuidString, "title": $0.title, "generating": $0.generating] as [String: Any] },
                "left": state.left.uuidString, "right": state.right?.uuidString as Any? ?? NSNull(),
                "focused": state.focused.uuidString, "ratio": state.ratio, "revealed": state.revealed,
                "canReopen": state.recentlyClosed != nil]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let key = String(data: data, encoding: .utf8), lastConfigurations[id] != key {
                lastConfigurations[id] = key; page.configureChat(payload)
            }
        }
        if let page = focusedPage {
            host?.title = page.title; host?.address = page.address; host?.favicon = page.favicon
        }
        objectWillChange.send(); host?.objectWillChange.send(); host?.changed?()
        surface?.synchronize()
    }
    func layout(in view: TahoeChatSurfaceView) {
        guard !isDisposed, surface === view else { return }
        let primary = pages[state.left]?.webView
        let validSplit = state.right != nil && ready.contains(state.left) && paneRect.width > 0 && paneRect.height > 0
        let scale = primary.map { $0.bounds.width / max(1, viewportWidth) } ?? 1
        var rightFrame = CGRect(x: paneRect.minX * scale, y: paneRect.minY * scale + max(0, -(primary?.scrollView.contentOffset.y ?? 0)), width: paneRect.width * scale, height: paneRect.height * scale)
        rightFrame = rightFrame.intersection(CGRect(x: 0, y: view.chromeInset, width: view.bounds.width, height: max(0, view.bounds.height-view.chromeInset)))
        for (id, page) in pages {
            guard let web = page.webView else { continue }
            if dragDelegates[id]?.webView !== web {
                dragDelegates.removeValue(forKey: id)?.detach()
                dragDelegates[id] = TahoeChatTabDrag(workspace: self, webView: web)
            }
            if web.superview !== view { web.removeFromSuperview(); web.translatesAutoresizingMaskIntoConstraints = true; view.addSubview(web) }
            let isLeft = id == state.left
            let isRight = id == state.right && validSplit && !rightFrame.isNull
            let show = view.isPageVisible && (isLeft || isRight)
            web.frame = isRight ? rightFrame : view.bounds
            page.updateChromeInset(isRight ? 0 : view.chromeInset, for: web)
            web.overrideUserInterfaceStyle = view.appearance
            if !show && !web.isHidden { web.endEditing(true) }
            web.isHidden = !show; web.isUserInteractionEnabled = show; web.accessibilityElementsHidden = !show
            if show { view.bringSubviewToFront(web) }
        }
        if validSplit, let id = state.right, let web = pages[id]?.webView { view.bringSubviewToFront(web) }

    }
}

/// Native drag interaction for DOM tab hit regions. This lets touch and mouse
/// drags leave WebKit and land anywhere on the desktop without a page reload.
@MainActor
private final class TahoeChatTabDrag: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
    weak var workspace: TahoeChatWorkspace?
    weak var webView: WKWebView?
    private var interaction: UIDragInteraction!
    private var drop: UIDropInteraction!
    private var token: String?
    private var lifted: (UUID, CGRect)?
    init(workspace: TahoeChatWorkspace, webView: WKWebView) {
        self.workspace = workspace; self.webView = webView
        super.init()
        interaction = UIDragInteraction(delegate: self); interaction.isEnabled = true
        webView.addInteraction(interaction)
        drop = UIDropInteraction(delegate: self); webView.addInteraction(drop)
    }
    func detach() { if let interaction { webView?.removeInteraction(interaction) }; if let drop { webView?.removeInteraction(drop) } }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: ["com.aault.tahoe.browser-tab"]) && TahoeWorkspace.shared.tabTransfer != nil
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        guard let workspace, let webView, workspace.dragTarget(at: session.location(in: webView), in: webView) != nil else { return UIDropProposal(operation: .cancel) }
        return UIDropProposal(operation: .move)
    }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let desktop = TahoeWorkspace.shared
        guard let workspace, let webView, let (target, _, _) = workspace.dragTarget(at: session.location(in: webView), in: webView),
              let host = workspace.host, let destination = desktop.browsers.first(where: { $0.value.tabs.contains { $0 === host } })?.key,
              let transfer = desktop.tabTransfer, let provider = session.items.first?.itemProvider else { return }
        desktop.tabTransfer?.accepted = true
        provider.loadDataRepresentation(forTypeIdentifier: "com.aault.tahoe.browser-tab") { data, _ in
            DispatchQueue.main.async {
                guard desktop.tabTransfer?.token == transfer.token else { return }; desktop.tabTransfer = nil
                guard let data, data.count <= 64, String(data: data, encoding: .utf8) == transfer.token else { return }
                _ = desktop.moveTransfer(transfer, to: destination, before: target, chats: workspace)
            }
        }
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let workspace, let webView, let (id, frame, strip) = workspace.dragTarget(at: session.location(in: webView), in: webView) else { return [] }
        let value = UUID().uuidString; token = value; lifted = (id, frame)
        TahoeWorkspace.shared.beginChatTransfer(workspace, id: id, token: value, strip: strip)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "com.aault.tahoe.browser-tab", visibility: .ownProcess) { completion in
            completion(Data(value.utf8), nil); return nil
        }
        return [UIDragItem(itemProvider: provider)]
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        guard let (id, frame) = lifted, let webView else { return nil }
        let label = UILabel(frame: CGRect(origin: .zero, size: CGSize(width: max(120, min(220, frame.width)), height: max(30, frame.height))))
        label.text = workspace?.state.items.first(where: { $0.id == id })?.title
        label.font = .systemFont(ofSize: 13); label.textAlignment = .center
        label.backgroundColor = .secondarySystemBackground; label.layer.cornerRadius = 8; label.clipsToBounds = true
        label.overrideUserInterfaceStyle = webView.traitCollection.userInterfaceStyle
        let target = UIDragPreviewTarget(container: webView, center: CGPoint(x: frame.midX, y: frame.midY))
        return UITargetedDragPreview(view: label, parameters: UIDragPreviewParameters(), target: target)
    }
    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        if TahoeWorkspace.shared.tabTransfer?.token == token && TahoeWorkspace.shared.tabTransfer?.accepted != true { TahoeWorkspace.shared.tabTransfer = nil }
        token = nil; lifted = nil
    }
}

@MainActor
final class TahoeChatBridge: NSObject, WKScriptMessageHandler {
    weak var page: TahoeBrowserTab?
    init(page: TahoeBrowserTab) { self.page = page }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let page, TahoeChatBridgeOrigin.allows(scheme: message.frameInfo.securityOrigin.protocol,
            host: message.frameInfo.securityOrigin.host, port: message.frameInfo.securityOrigin.port,
            mainFrame: message.frameInfo.isMainFrame, matchingPage: page.webView != nil && message.webView === page.webView),
              let body = message.body as? [String: Any], body.count <= 16,
              (body["title"] as? String)?.utf8.count ?? 0 <= 4096,
              (body["url"] as? String)?.utf8.count ?? 0 <= 8192 else { return }
        if let owner = page.chatOwner { owner.receive(body, from: page); return }
        guard TahoePreferences.shared.value.chatTabsEnabled, page.chatWorkspace == nil,
              body["type"] as? String == "status", body["ready"] as? Bool == true,
              let url = page.webView?.url, TahoeChatWorkspaceState.allows(url) else {
            if !TahoePreferences.shared.value.chatTabsEnabled { page.configureChat(["enabled": false]) }
            return
        }
        page.activateChatWorkspace(report: body)
    }
}

@MainActor
final class TahoeChatSurfaceView: UIView {
    weak var workspace: TahoeChatWorkspace?
    var chromeInset: CGFloat = 0
    var isPageVisible = true
    var appearance: UIUserInterfaceStyle = .unspecified
    func synchronize() {
        let live = Set(workspace?.pages.values.compactMap(\.webView).map(ObjectIdentifier.init) ?? [])
        for child in subviews where child is WKWebView && !live.contains(ObjectIdentifier(child)) { child.removeFromSuperview() }
        setNeedsLayout()
    }
    override func layoutSubviews() { super.layoutSubviews(); workspace?.layout(in: self) }
}

struct TahoeChatWorkspaceSurface: UIViewRepresentable {
    @ObservedObject var workspace: TahoeChatWorkspace
    let chromeInset: CGFloat
    let appearance: String
    @Environment(\.tahoeWindowVisible) private var visible
    func makeUIView(context: Context) -> TahoeChatSurfaceView {
        let view = TahoeChatSurfaceView(); view.workspace = workspace; workspace.surface = view; return view
    }
    func updateUIView(_ view: TahoeChatSurfaceView, context: Context) {
        view.workspace = workspace
        workspace.surface = view
        view.chromeInset = chromeInset; view.isPageVisible = visible
        view.appearance = tahoeBrowserInterfaceStyle(appearance)
        view.synchronize()
    }
    static func dismantleUIView(_ view: TahoeChatSurfaceView, coordinator: ()) {
        if view.workspace?.surface === view { view.workspace?.surface = nil }
        view.workspace = nil
    }
}
