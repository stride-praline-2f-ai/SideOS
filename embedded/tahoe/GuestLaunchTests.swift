import Foundation

@main struct GuestLaunchTests {
    static func main() {
        let realError = "The host signing framework could not load: missing required symbol"
        var earlyExit = TahoeGuestLaunchState()
        earlyExit.exited()
        precondition(earlyExit.terminated)
        precondition(earlyExit.initialized(pid: 0, error: realError))
        precondition(earlyExit.message == realError, "Cleanup must not swallow the initialization error")
        precondition(!earlyExit.initialized(pid: 42, error: nil), "Late success must not revive an exited session")
        var earlyError = TahoeGuestLaunchState()
        _ = earlyError.initialized(pid: 0, error: realError); earlyError.exited()
        precondition(earlyError.message == realError)
        var closed = TahoeGuestLaunchState(); closed.close()
        precondition(!closed.initialized(pid: 44, error: nil))
        precondition(!closed.initialized(pid: 0, error: realError) && closed.message == nil)
        var valid = TahoeGuestLaunchState(); _ = valid.initialized(pid: 44, error: nil)
        precondition(valid.pid == 44 && !valid.terminated)
        valid.exited(); precondition(valid.terminated)
        var invalid = TahoeGuestLaunchState(); _ = invalid.initialized(pid: 0, error: nil)
        precondition(invalid.terminated && invalid.message != nil)
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 400), CGSize(width: 400, height: CGFloat.infinity), CGSize(width: -1, height: 400)] {
            precondition(!TahoeGuestLaunchState.validViewport(size))
        }
        precondition(TahoeGuestLaunchState.validViewport(.init(width: 360, height: 500)))
        precondition(TahoeGuestLaunchState.validViewport(.init(width: 900, height: 700)))
        print("Guest launch: both callback orders, useful error preservation, closed-session rejection, no resurrection and valid phone/tablet viewport checks passed")
    }
}
