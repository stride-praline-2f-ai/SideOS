import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Semantic triggers, independent of SwiftUI or an upstream framework.
enum TahoeMotionEvent: CaseIterable {
    case dockHover, launchApp, minimizeWindow, restoreWindow, menuHover, openMenu
    case hoverTrafficLights, dragWindow, tapGlassButton, presentOverlay
}
struct TahoeMotionSpec {
    let duration: Double
    let displacement: Double
    static func resolve(_ event: TahoeMotionEvent, reduced: Bool) -> Self {
        if reduced { return Self(duration: 0, displacement: 0) }
        switch event {
        case .dragWindow: return Self(duration: 0, displacement: 0)
        case .dockHover: return Self(duration: 0.16, displacement: 0)
        case .launchApp: return Self(duration: 0.48, displacement: 12)
        case .minimizeWindow, .restoreWindow: return Self(duration: 0.42, displacement: 0)
        case .openMenu, .presentOverlay: return Self(duration: 0.16, displacement: 4)
        case .menuHover, .hoverTrafficLights: return Self(duration: 0.10, displacement: 0)
        case .tapGlassButton: return Self(duration: 0.12, displacement: 0.02)
        }
    }
}
/// Retarget from the current presentation progress; stale completions carry a token.
struct TahoeMotionTrack {
    let token: UUID
    let from: Double
    let to: Double
    let start: TimeInterval
    let duration: Double
    func progress(at time: TimeInterval) -> Double {
        guard duration > 0 else { return to }
        let t = min(1, max(0, (time - start) / duration))
        let eased = t * t * (3 - 2 * t)
        return from + (to - from) * eased
    }
    /// Basic screen-space interpolation for the low-power transition.
    func rectangle(from source: CGRect, to target: CGRect, at time: TimeInterval) -> CGRect {
        let p = CGFloat(progress(at: time))
        // Keep the same interpolation while avoiding exponential type-check
        // work on older pinned Swift compilers in the combined IPA host build.
        let x: CGFloat = source.minX + (target.minX - source.minX) * p
        let y: CGFloat = source.minY + (target.minY - source.minY) * p
        let width: CGFloat = source.width + (target.width - source.width) * p
        let height: CGFloat = source.height + (target.height - source.height) * p
        return CGRect(x: x, y: y, width: width, height: height)
    }
    func reversed(at time: TimeInterval, to target: Double) -> Self {
        let current = progress(at: time)
        return Self(token: UUID(), from: current, to: target, start: time,
                    duration: max(0.08, duration * abs(target - current) / max(0.001, abs(to - from))))
    }
}
