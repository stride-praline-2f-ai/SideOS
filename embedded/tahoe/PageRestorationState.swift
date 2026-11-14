import Foundation

/// One queue across browser windows: selected pages take the next available
/// slot, while background restoration cannot start an unbounded load burst.
struct TahoePageRestoreQueue<ID: Hashable> {
    let limit: Int
    private(set) var pending: [ID] = []
    private(set) var active: Set<ID> = []
    init(limit: Int = 2) { self.limit = max(1, limit) }
    mutating func enqueue(_ id: ID, priority: Bool = false) {
        guard !active.contains(id) else { return }
        if let index = pending.firstIndex(of: id) {
            guard priority else { return }
            pending.remove(at: index)
        }
        if priority { pending.insert(id, at: 0) } else { pending.append(id) }
    }
    mutating func next(allowed: Set<ID>? = nil) -> ID? {
        guard active.count < limit, let index = pending.firstIndex(where: { allowed?.contains($0) ?? true }) else { return nil }
        let id = pending.remove(at: index)
        active.insert(id)
        return id
    }
    mutating func remove(_ id: ID) {
        pending.removeAll { $0 == id }
        active.remove(id)
    }
}

/// WebKit can terminate a page independently of its WKWebView object. Recover
/// automatically, but stop a repeatedly crashing site from reloading forever.
struct TahoePageRecoveryBudget {
    private var attempts: [TimeInterval] = []
    mutating func allow(at time: TimeInterval) -> Bool {
        attempts.removeAll { time - $0 >= 60 }
        guard attempts.count < 2 else { return false }
        attempts.append(time)
        return true
    }
}
