import Foundation
@main struct TahoeMotionTests {
    static func main() {
        for event in TahoeMotionEvent.allCases {
            let reduced = TahoeMotionSpec.resolve(event, reduced: true)
            precondition(reduced.duration == 0 && reduced.displacement == 0)
        }
        precondition(TahoeMotionSpec.resolve(.dragWindow, reduced: false).duration == 0)
        precondition(TahoeMotionSpec.resolve(.minimizeWindow, reduced: false).duration == 0.42)
        let a = TahoeMotionTrack(token: UUID(), from: 0, to: 1, start: 10, duration: 0.5)
        precondition(a.progress(at: 9) == 0 && a.progress(at: 11) == 1)
        let reverse = a.reversed(at: 10.2, to: 0)
        precondition(abs(a.progress(at: 10.2) - reverse.progress(at: 10.2)) < 0.00001)
        precondition(reverse.token != a.token && reverse.progress(at: 11) == 0)
        let other = TahoeMotionTrack(token: UUID(), from: 0, to: 1, start: 10.1, duration: 0.5)
        precondition(other.token != reverse.token && other.progress(at: 11) == 1)
        precondition(TahoeMotionTrack(token: UUID(), from: 0, to: 1, start: 0, duration: 0).progress(at: 0) == 1)
        let start = CGRect(x: 20, y: 30, width: 800, height: 500)
        let finish = CGRect(x: 250, y: 700, width: 32, height: 32)
        precondition(a.rectangle(from: start, to: finish, at: 10) == start)
        precondition(a.rectangle(from: start, to: finish, at: 10.5) == finish)
        let halfway = a.rectangle(from: start, to: finish, at: 10.25)
        precondition(abs(halfway.midX - (start.midX + finish.midX) / 2) < 0.01)
        precondition(reverse.duration > 0 && reverse.duration < a.duration)
        print("Motion registry, reduced motion, retargeting and independent track checks passed")
    }
}
