import SwiftUI

struct TahoeJob: Identifiable {
    let id: UUID
    var title: String
    var owner: String
    var detail: String
    var progress: Double?
    var state = "Running"
    var cancellable = false
    var active: Bool { state == "Running" || state == "Queued" }
}
@MainActor final class TahoeActivityCenter: ObservableObject {
    static let shared = TahoeActivityCenter()
    @Published private(set) var jobs: [TahoeJob] = []
    private var cancellations: [UUID: () -> Void] = [:]
    func begin(_ title: String, owner: String, queued: Bool = false) -> UUID {
        let id = UUID(); jobs.insert(TahoeJob(id: id, title: title, owner: owner, detail: queued ? "Waiting to start" : "Starting…", state: queued ? "Queued" : "Running"), at: 0)
        if jobs.count > 100 { jobs = jobs.filter(\.active) + Array(jobs.filter { !$0.active }.prefix(50)) }
        return id
    }
    func update(_ id: UUID, detail: String, progress: Double? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = "Running"; jobs[index].detail = detail; jobs[index].progress = progress
    }
    func setCancellation(_ id: UUID, action: (() -> Void)?) {
        cancellations[id] = action
        if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].cancellable = action != nil }
    }
    func finish(_ id: UUID, error: Error? = nil, cancelled: Bool = false) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = cancelled ? "Cancelled" : error == nil ? "Completed" : "Failed"
        jobs[index].detail = error?.localizedDescription ?? jobs[index].state
        jobs[index].cancellable = false; cancellations.removeValue(forKey: id)
    }
    func cancel(_ id: UUID) { cancellations[id]?(); finish(id, cancelled: true) }
    func clearFinished() { jobs.removeAll { !$0.active } }
}
