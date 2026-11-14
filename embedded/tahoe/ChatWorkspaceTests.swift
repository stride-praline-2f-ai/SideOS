import Foundation

@main struct ChatWorkspaceTests {
    static func main() throws {
        func url(_ path: String) -> URL { URL(string: "https://chatgpt.com" + path)! }
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
        for address in ["http://chatgpt.com/c/a", "https://chatgpt.com.evil.test/c/a", "https://evil.test/c/a", "https://chatgpt.com:444/c/a", "https://u:p@chatgpt.com/c/a", "https://chatgpt.com/share/a", "https://chatgpt.com/auth/login", "https://chatgpt.com/g/g-p123/project", "https://chatgpt.com/c/a%2Fb"] {
            check(!TahoeChatWorkspaceState.allows(URL(string: address)!), "unsupported origin/route: \(address)")
        }
        let original = UUID()
        var s = TahoeChatWorkspaceState(id: original, url: url("/c/first"))
        check(!s.revealed, "single chat keeps normal page")
        let second = s.open(url("/c/second"))!
        check(s.revealed && s.focused == second && s.items.count == 2, "second chat reveals row")
        check(s.open(url("/g/g-example/c/first?model=x")) == original && s.items.count == 2, "dedupe by conversation identity across GPT routes")
        s.split(second, width: 1000)
        check(s.left == original && s.right == second && s.focusRight, "split preserves both views")
        s.resize(-10, width: 1000)
        check(s.ratio * 994 >= 359.99, "minimum left width")
        s.resize(10, width: 1000)
        check((1 - s.ratio) * 994 >= 359.99, "minimum right width")
        s.fit(width: 700)
        check(s.left == second && s.right == nil, "narrowing keeps focused chat")
        let draft = s.open(url("/"))!
        check(s.open(url("/?model=other")) == draft, "reuse untouched empty chat")
        s.update(draft, url: url("/"), title: "Draft", hasDraft: true, generating: false)
        check(s.open(url("/")) != draft, "never overwrite an unsent draft")
        check(!s.close(draft), "unsent draft requires explicit confirmation")
        check(s.close(draft, confirmed: true), "confirmed close")
        let reopened = s.reopen()!
        check(s.items.contains { $0.id == reopened }, "reopen has a live selection")
        s.update(second, url: url("/c/second"), title: "Sensitive title", hasDraft: true, generating: true)
        check(!s.close(second), "generating chat is protected")
        let encoded = try JSONEncoder().encode(s.saved)
        let text = String(decoding: encoded, as: UTF8.self)
        check(!text.contains("Sensitive") && !text.contains("hasDraft") && !text.contains("generating"), "restoration never serializes titles/drafts/messages")
        let saved = try JSONDecoder().decode(TahoeSavedChatWorkspace.self, from: encoded)
        let restored = TahoeChatWorkspaceState(saved: saved, firstID: UUID())!
        check(restored.items.map(\.url) == s.items.map(\.url), "restore order and links")
        check(restored.items.allSatisfy { !$0.hasDraft && !$0.generating }, "restore has no fabricated page state")
        check(TahoeChatWorkspaceState(saved: TahoeSavedChatWorkspace(urls: [url("/c/a")], left: 2, right: nil, focusRight: false, ratio: 0.5), firstID: UUID()) == nil, "reject invalid restore index")
        check(TahoeChatWorkspaceState(saved: TahoeSavedChatWorkspace(urls: [url("/c/a"),url("/c/a")], left: 0, right: nil, focusRight: false, ratio: 0.5), firstID: UUID()) == nil, "reject duplicate saved identities")
        var last = TahoeChatWorkspaceState(id: UUID(), url: url("/c/only"))
        check(last.close(last.left) && last.items.count == 1 && last.items[0].url == TahoeChatWorkspaceState.home, "closing final tab returns new chat")
        check(s.open(URL(string: "https://example.org")!) == nil, "workspace cannot open other websites")
        let old = Data("{\"windowID\":\"\(UUID().uuidString)\",\"addresses\":[\"https://chatgpt.com/c/first\"],\"selected\":0}".utf8)
        let legacy = try JSONDecoder().decode(TahoeSavedBrowser.self, from: old)
        check(legacy.chatWorkspaces == nil, "old workspace files decode without new fields")
        let nested = TahoeSavedBrowser(windowID: UUID(), addresses: [url("/c/first"), url("/c/second")], selected: 1,
            chatWorkspaces: [nil, saved])
        let roundTrip = try JSONDecoder().decode(TahoeSavedBrowser.self, from: JSONEncoder().encode(nested))
        check(roundTrip.chatWorkspaces?.count == 2 && roundTrip.chatWorkspaces?[0] == nil && roundTrip.chatWorkspaces?[1] == saved,
              "optional per-browser-page restoration preserves aligned indexes")
        let temporaryID = UUID()
        let temporaryURL = url("/?temporary-chat=true")
        var temporary = TahoeChatWorkspaceState(id: temporaryID, url: temporaryURL)
        temporary.update(temporaryID, url: temporaryURL, title: "Temporary chat", hasDraft: false, generating: false, hasContent: true)
        check(temporary.open(TahoeChatWorkspaceState.home) != temporaryID && temporary.items.count == 2,
              "a completed temporary or unsaved conversation is not an untouched empty tab")
        print("Chat workspace origin, routing, deduplication, draft protection, split sizing and privacy-safe restoration checks passed")
    }
}
