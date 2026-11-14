import SwiftUI
import WebKit

/// Reports protection flags only. No form values, page text or media URLs cross
/// this isolated-world bridge. Unknown page state is protected conservatively.
@MainActor final class TahoePageActivityBridge: NSObject, WKScriptMessageHandler {
    weak var page: TahoeBrowserTab?
    init(_ page: TahoeBrowserTab) { self.page = page }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let page, message.webView === page.webView,
              let body = message.body as? [String: Any],
              let dirty = body["dirty"] as? Bool, let media = body["media"] as? Bool else { return }
        let changed = !page.activityKnown || page.hasDirtyForm != dirty || page.playingMedia != media
        page.activityKnown = true; page.hasDirtyForm = dirty; page.playingMedia = media
        if changed { page.changed?() }
    }
    static let script = #"""
    (()=>{'use strict';if(window.top!==window)return;let dirty=false;
      const report=()=>{try{window.webkit.messageHandlers.sideosActivity.postMessage({dirty,media:[...document.querySelectorAll('audio,video')].some(m=>!m.paused&&!m.ended)});}catch(_){}};
      document.addEventListener('input',()=>{dirty=true;report();},true);
      document.addEventListener('change',()=>{dirty=true;report();},true);
      for(const event of ['play','pause','ended','emptied'])document.addEventListener(event,report,true);
      report();})();
    """#
}

@MainActor final class TahoeBrowserResources: ObservableObject {
    static let shared = TahoeBrowserResources()
    @Published private(set) var pressure = false
    @Published private(set) var sleepingCount = 0
    private weak var workspace: TahoeWorkspace?
    private var scheduled: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    func attach(_ workspace: TahoeWorkspace) {
        self.workspace = workspace
        guard tokens.isEmpty else { return }
        tokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setPressure(true) }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setPressure(ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue) }
        })
    }
    func schedule() {
        guard scheduled == nil else { return }
        scheduled = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.scheduled = nil; self?.enforce()
        }
    }
    private func setPressure(_ value: Bool) {
        pressure = value
        TahoePageRestoration.shared.setResourcePressure(value)
        recovery?.cancel()
        if value {
            workspace?.purgeThumbnails()
            enforce()
            recovery = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else { return }
                self?.setPressure(false)
            }
        }
    }
    private func enforce() {
        guard let workspace else { return }
        let roots = workspace.browsers.values.flatMap(\.tabs)
        let pages = roots.flatMap { $0.chatWorkspace.map { Array($0.pages.values) } ?? [$0] }
        let resident = pages.filter { $0.webView != nil }
        let configured = TahoePreferences.shared.value.residentPageLimit ?? 16
        let limit = pressure ? max(3, configured / 2) : max(4, configured)
        var excess = max(0, resident.count - limit)
        for page in resident.sorted(by: { $0.lastUse < $1.lastUse }) where excess > 0 {
            let visibleChat = page.chatOwner.map { $0.host?.isPresented == true && ($0.state.left == page.id || $0.state.right == page.id) } ?? false
            guard !page.isPresented, !visibleChat, !page.pinned, !page.chatHost.pinned,
                  page.activityKnown, !page.hasDirtyForm, !page.playingMedia, !page.loading,
                  !TahoeDownloads.shared.isActive(page.id),
                  page.chatOwner?.state.items.first(where: { $0.id == page.id }).map({ !$0.hasProtectedWork }) ?? true else { continue }
            page.sleep(); excess -= 1
        }
        sleepingCount = pages.filter(\.isSleeping).count
    }
}
