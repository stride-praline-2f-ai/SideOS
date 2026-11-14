import Foundation

enum TahoeChatBridgeOrigin {
    static func allows(scheme: String, host: String, port: Int, mainFrame: Bool, matchingPage: Bool) -> Bool {
        mainFrame && matchingPage && scheme == "https" && host == "chatgpt.com" && (port == 0 || port == 443)
    }
}

/// Only public conversation URLs and layout belong in restoration. Page text,
/// drafts, response contents and titles are deliberately never encoded.
struct TahoeSavedChatWorkspace: Codable, Equatable, Sendable {
    var urls: [URL]
    var left: Int
    var right: Int?
    var focusRight: Bool
    var ratio: Double
}

struct TahoeChatItem: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var title = "New chat"
    var hasDraft = false
    var hasContent = false
    var generating = false
    var hasProtectedWork: Bool { hasDraft || generating || (hasContent && TahoeChatWorkspaceState.conversationKey(url) == nil) }
}

struct TahoeChatWorkspaceState {
    static let home = URL(string: "https://chatgpt.com/")!
    static let minimumSplitWidth: Double = 760
    var items: [TahoeChatItem]
    var left: UUID
    var right: UUID?
    var focusRight = false
    var ratio: Double = 0.5
    var revealed = false
    private(set) var recentlyClosed: URL?
    var focused: UUID { focusRight ? (right ?? left) : left }

    /// Exact origin and supported conversation routes. Never treat share links,
    /// auth pages, GPT directories, project pages or settings as conversations.
    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "chatgpt.com",
              url.port == nil || url.port == 443, url.user == nil, url.password == nil else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.isEmpty { return true }
        if parts.count == 2 && parts[0] == "c" { return validIdentifier(parts[1]) }
        if parts.count == 2 && parts[0] == "g" { return validIdentifier(parts[1]) }
        return parts.count == 4 && parts[0] == "g" && parts[2] == "c" &&
            validIdentifier(parts[1]) && validIdentifier(parts[3])
    }
    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 160 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
        }
    }
    static func conversationKey(_ url: URL) -> String? {
        guard allows(url) else { return nil }
        let parts = url.path.split(separator: "/")
        guard let index = parts.firstIndex(of: "c"), index + 1 < parts.count else { return nil }
        return String(parts[index + 1])
    }
    init(id: UUID, url: URL) { items = [TahoeChatItem(id: id, url: url)]; left = id }
    init?(saved: TahoeSavedChatWorkspace, firstID: UUID) {
        guard !saved.urls.isEmpty, saved.urls.allSatisfy(Self.allows) else { return nil }
        var keys = Set<String>()
        let urls = saved.urls.filter { url in
            guard let key = Self.conversationKey(url) else { return true }
            return keys.insert(key).inserted
        }
        // Do not remap indexes after dropping duplicate/corrupt saved entries.
        guard urls.count == saved.urls.count, urls.indices.contains(saved.left),
              saved.right == nil || (urls.indices.contains(saved.right!) && saved.right != saved.left) else { return nil }
        items = urls.enumerated().map { TahoeChatItem(id: $0.offset == saved.left ? firstID : UUID(), url: $0.element) }
        left = items[saved.left].id
        right = saved.right.map { items[$0].id }
        focusRight = saved.focusRight && right != nil
        ratio = saved.ratio.isFinite ? min(0.8, max(0.2, saved.ratio)) : 0.5
        revealed = items.count > 1
    }
    var saved: TahoeSavedChatWorkspace {
        TahoeSavedChatWorkspace(urls: items.map(\.url), left: items.firstIndex { $0.id == left } ?? 0,
            right: right.flatMap { id in items.firstIndex { $0.id == id } }, focusRight: focusRight, ratio: ratio)
    }
    @discardableResult mutating func open(_ url: URL, id: UUID = UUID()) -> UUID? {
        guard Self.allows(url) else { return nil }
        if let key = Self.conversationKey(url), let item = items.first(where: { Self.conversationKey($0.url) == key }) {
            select(item.id); return item.id
        }
        if Self.conversationKey(url) == nil,
           let empty = items.first(where: { Self.conversationKey($0.url) == nil && $0.url.path == url.path && !$0.hasDraft && !$0.hasContent && !$0.generating }) {
            select(empty.id); return empty.id
        }
        items.append(TahoeChatItem(id: id, url: url))
        revealed = true
        select(id)
        return id
    }
    mutating func select(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if id == left { focusRight = false }
        else if id == right { focusRight = true }
        else if focusRight && right != nil { right = id }
        else { left = id }
    }
    mutating func swapPanes() {
        guard let right else { return }
        let previousLeft = left
        left = right; self.right = previousLeft
        focusRight.toggle(); ratio = 1 - ratio
    }
    mutating func move(_ id: UUID, before target: UUID) {
        guard id != target, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if let index = items.firstIndex(where: { $0.id == target }) { items.insert(item, at: index) }
        else { items.append(item) }
    }
    mutating func adopt(id: UUID, url: URL, title: String, before target: UUID?) -> Bool {
        guard Self.allows(url), !items.contains(where: { $0.id == id }),
              Self.conversationKey(url).map({ key in !items.contains { Self.conversationKey($0.url) == key } }) ?? true else { return false }
        let item = TahoeChatItem(id: id, url: url, title: title)
        if let target, let index = items.firstIndex(where: { $0.id == target }) { items.insert(item, at: index) }
        else { items.append(item) }
        revealed = true; select(id); return true
    }
    mutating func split(_ id: UUID, width: Double) {
        guard width.isFinite, width >= Self.minimumSplitWidth, id != focused,
              items.contains(where: { $0.id == id }) else { return }
        left = focused; right = id; focusRight = true; revealed = true
        resize(ratio, width: width)
    }
    mutating func collapse() {
        left = focused; right = nil; focusRight = false
    }
    mutating func fit(width: Double) {
        if !width.isFinite || width < Self.minimumSplitWidth { collapse() }
        else { resize(ratio, width: width) }
    }
    mutating func resize(_ fraction: Double, width: Double) {
        guard fraction.isFinite, width.isFinite, width >= Self.minimumSplitWidth else { return }
        let lower = 360 / (width - 6)
        ratio = min(1 - lower, max(lower, fraction))
    }
    mutating func update(_ id: UUID, url: URL, title: String, hasDraft: Bool, generating: Bool, hasContent: Bool = false) {
        guard Self.allows(url), let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].url = url
        let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        items[index].title = clean.isEmpty || clean == "ChatGPT" ? "New chat" : clean
        items[index].hasDraft = hasDraft; items[index].generating = generating; items[index].hasContent = hasContent
    }
    @discardableResult mutating func close(_ id: UUID, confirmed: Bool = false) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              confirmed || !items[index].hasProtectedWork else { return false }
        recentlyClosed = items.remove(at: index).url
        if items.isEmpty {
            let item = TahoeChatItem(id: UUID(), url: Self.home)
            items = [item]; left = item.id; right = nil; focusRight = false
        } else if id == left || id == right {
            if let right {
                left = id == left ? right : left; self.right = nil; focusRight = false
            } else { left = items[min(index, items.count - 1)].id }
        }
        return true
    }
    @discardableResult mutating func reopen() -> UUID? {
        guard let url = recentlyClosed else { return nil }
        recentlyClosed = nil
        return open(url)
    }
}
