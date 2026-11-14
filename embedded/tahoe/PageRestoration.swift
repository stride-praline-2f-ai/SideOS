import Foundation

@MainActor final class TahoePageRestoration {
    static let shared = TahoePageRestoration()
    private final class Request {
        weak var page: TahoeBrowserTab?
        init(_ page: TahoeBrowserTab) { self.page = page }
    }
    private var queue = TahoePageRestoreQueue<UUID>()
    private var requests: [UUID: Request] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private var scheduled = false
    private var appActive = true
    private var resourcePressure = false
    private var priorities = Set<UUID>()
    private let timeout: Duration
    init(timeout: Duration = .seconds(45)) { self.timeout = timeout }
    func setResourcePressure(_ value: Bool) { resourcePressure = value; schedule() }

    func setActive(_ active: Bool) {
        guard appActive != active else { return }
        appActive = active
        if active {
            for id in queue.active {
                if let page = requests[id]?.page { watch(page) }
            }
            schedule()
        } else {
            // Time spent suspended by iPadOS is not a page-loading timeout.
            deadlines.values.forEach { $0.cancel() }
            deadlines.removeAll()
        }
    }
    func request(_ page: TahoeBrowserTab, priority: Bool = false) {
        guard page.needsAutomaticRestore else { return }
        if priority { priorities.insert(page.id) }
        requests[page.id] = Request(page)
        queue.enqueue(page.id, priority: priority)
        schedule()
    }
    func finish(_ id: UUID) {
        guard requests[id] != nil || queue.active.contains(id) else { return }
        queue.remove(id)
        priorities.remove(id)
        requests.removeValue(forKey: id)
        tokens.removeValue(forKey: id)
        deadlines.removeValue(forKey: id)?.cancel()
        schedule()
    }
    private func schedule() {
        guard appActive, !scheduled, !queue.pending.isEmpty else { return }
        scheduled = true
        // Start after state restoration and view mounting have completed. This
        // also prevents synchronous navigation callbacks from nesting pumps.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.pump()
        }
    }
    private func pump() {
        guard appActive else { return }
        while let id = queue.next(allowed: resourcePressure ? priorities : nil) {
            guard let page = requests[id]?.page, page.needsAutomaticRestore else {
                finish(id); continue
            }
            watch(page)
            if !page.beginAutomaticRestore() { finish(id) }
        }
    }
    private func watch(_ page: TahoeBrowserTab) {
        let id = page.id, token = UUID(), timeout = timeout
        tokens[id] = token
        deadlines.removeValue(forKey: id)?.cancel()
        deadlines[id] = Task { @MainActor [weak self, weak page] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.appActive, self.tokens[id] == token else { return }
            page?.automaticRestoreTimedOut()
            self.finish(id)
        }
    }
}
