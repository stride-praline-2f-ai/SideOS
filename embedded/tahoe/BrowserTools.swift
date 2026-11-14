import SwiftUI
import WebKit

@MainActor enum TahoeBrowserDocuments {
    static func savePDF(_ page: TahoeBrowserTab) {
        guard let view = page.webView else { return }
        let job = TahoeActivityCenter.shared.begin("Save Page as PDF", owner: "Browser")
        view.createPDF(configuration: WKPDFConfiguration()) { result in
            Task { @MainActor in
                do {
                    let data = try result.get()
                    let name = String(page.title.prefix(80)).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".pdf"
                    let destination = TahoeFileStore.shared.downloads
                    let file = try await TahoeGeneratedDocuments.shared.save(data, name: name, directory: destination)
                    TahoeFileStore.shared.revision += 1; TahoeActivityCenter.shared.finish(job)
                    TahoeWorkspace.shared.openFiles(destination, reveal: file)
                } catch { TahoeActivityCenter.shared.finish(job, error: error); TahoeWorkspace.shared.error = error.localizedDescription }
            }
        }
    }
    static func printPage(_ page: TahoeBrowserTab) {
        guard let view = page.webView else { return }
        let controller = UIPrintInteractionController.shared
        controller.printFormatter = view.viewPrintFormatter(); controller.present(from: view.bounds, in: view, animated: true, completionHandler: nil)
    }
    static func reader(_ page: TahoeBrowserTab) {
        page.webView?.evaluateJavaScript(readerScript, in: nil, in: .defaultClient) { result in
            if case .success(let value) = result, value as? Bool == false {
                Task { @MainActor in TahoeWorkspace.shared.error = "Reader is available on pages with an article. Interactive websites keep their normal layout." }
            }
        }
    }
    private static let readerScript = #"""
    (()=>{const old=document.getElementById('sideos-reader');if(old){old.dispatchEvent(new Event('sideos-close'));return true;}
      const source=document.querySelector('article');if(!source)return false;
      const article=source.cloneNode(true);for(const e of article.querySelectorAll('script,style,iframe,object,embed,svg,form,nav,button,input,textarea,[contenteditable]'))e.remove();
      for(const e of article.querySelectorAll('*')){for(const a of [...e.attributes])if(a.name.startsWith('on')||['style','id'].includes(a.name))e.removeAttribute(a.name);if(e.tagName==='A'){try{const u=new URL(e.getAttribute('href'),location.href);if(!['http:','https:'].includes(u.protocol))e.removeAttribute('href');else e.href=u.href;}catch(_){e.removeAttribute('href');}}}
      const host=document.createElement('div');host.id='sideos-reader';Object.assign(host.style,{position:'fixed',inset:'0',zIndex:'2147483647',overflow:'auto',background:matchMedia('(prefers-color-scheme:dark)').matches?'#1c1c1e':'#faf8f2',color:matchMedia('(prefers-color-scheme:dark)').matches?'#eee':'#222'});
      const shadow=host.attachShadow({mode:'closed'});const style=document.createElement('style');style.textContent='article{max-width:720px;margin:auto;padding:24px;font:20px/1.65 Georgia,serif}img,video{max-width:100%;height:auto}button{position:sticky;top:10px;margin:12px;padding:10px 16px;border-radius:9px;border:1px solid #888;background:inherit;color:inherit;font:16px system-ui}a{color:#2385dc}';shadow.append(style);
      const previous=[...document.body.children].map(e=>[e,e.inert]);const focus=document.activeElement;
      const restore=()=>{host.remove();for(const [e,inert] of previous)if(e.isConnected)e.inert=inert;if(focus?.isConnected)focus.focus();};
      host.addEventListener('sideos-close',restore,{once:true});
      const close=document.createElement('button');close.textContent='Done Reading';close.onclick=()=>host.dispatchEvent(new Event('sideos-close'));shadow.append(close,article);
      for(const [e] of previous)e.inert=true;document.body.append(host);close.focus();return true;})();
    """#
}
actor TahoeGeneratedDocuments {
    static let shared = TahoeGeneratedDocuments()
    func save(_ data: Data, name: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = TahoeFileOperations.unique(name, in: directory)
        try data.write(to: destination, options: .atomic); return destination
    }
}

@MainActor final class TahoeContentBlocking {
    static let shared = TahoeContentBlocking()
    private var rule: WKContentRuleList?
    private var compiling: Task<WKContentRuleList?, Never>?
    func install(on view: WKWebView, url: URL) async {
        let preferences = TahoePreferences.shared.value
        let controller = view.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard preferences.blockTrackers == true, !(preferences.contentBlockingExceptions ?? []).contains(url.host ?? "") else { return }
        if let rule { controller.add(rule); return }
        if compiling == nil {
            compiling = Task {
                let rules = #"[{"trigger":{"url-filter":"^https?://([^/]+\\.)?(doubleclick\\.net|googlesyndication\\.com|google-analytics\\.com)/"},"action":{"type":"block"}}]"#
                return await withCheckedContinuation { continuation in WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "SideOSBasicTrackers-v1", encodedContentRuleList: rules) { rule, _ in continuation.resume(returning: rule) } }
            }
        }
        rule = await compiling?.value; compiling = nil
        if let rule { controller.add(rule) }
    }
}
