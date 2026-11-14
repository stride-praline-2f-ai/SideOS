import Foundation

/// Callback order is not guaranteed: extension cleanup can arrive before its
/// initialization error. Preserve the useful error and never revive a dead PID.
struct TahoeGuestLaunchState {
    enum Phase: Equatable { case starting, running, exited, closed }
    private(set) var phase = Phase.starting
    private(set) var pid: Int32 = 0
    private(set) var message: String?
    var terminated: Bool { phase == .exited || phase == .closed }
    var closed: Bool { phase == .closed }
    @discardableResult mutating func initialized(pid: Int32, error: String?) -> Bool {
        guard !closed else { return false }
        if let error { fail(error); return true }
        guard phase == .starting else { return false }
        guard pid > 0 else { fail("LiveProcess returned no valid guest PID."); return true }
        self.pid = pid; phase = .running; return true
    }
    mutating func exited() {
        guard !closed else { return }
        phase = .exited
        if message == nil { message = "This application has exited. Try reopening it. If this repeats, copy the error and build diagnostics." }
    }
    mutating func fail(_ error: String) { guard !closed else { return }; message = error; phase = .exited }
    mutating func close() { phase = .closed }
    static func validViewport(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 1 && size.height > 1
    }
}
