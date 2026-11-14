import Foundation

/// Native window points drive layout. Pixel dimensions are diagnostics, never
/// used as point dimensions or as a guessed device-specific screen resolution.
enum TahoeViewportPolicy {
    struct Insets: Equatable {
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
    }
    struct Layout: Equatable {
        let viewport: CGSize
        let insets: Insets
        let usesTouchLayout: Bool
        let innerDisplay: Bool
        var menuHeight: CGFloat { usesTouchLayout ? 44 : 30 }
        var prefersFilledWindows: Bool { usesTouchLayout && (viewport.width < 900 || viewport.height < 650) }
        var compactMenus: Bool { !innerDisplay && viewport.width < 600 }
        func hostFrame(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: insets.left, dy: insets.top) }
        var label: String { innerDisplay ? "iPhone Duo inner screen · iPad desktop layout" : usesTouchLayout ? "Compact phone layout" : "iPad desktop layout" }
    }
    static func layout(size: CGSize, safe: Insets, phone: Bool, mode: String?) -> Layout {
        let width = size.width.isFinite ? max(1, size.width) : 1
        let height = size.height.isFinite ? max(1, size.height) : 1
        func inset(_ value: CGFloat, limit: CGFloat) -> CGFloat { value.isFinite ? min(max(0, value), limit * 0.4) : 0 }
        var safe = phone || mode == "duo" ? Insets(top: inset(safe.top, limit: height), left: inset(safe.left, limit: width),
            bottom: inset(safe.bottom, limit: height), right: inset(safe.right, limit: width)) : Insets()
        let viewport = CGSize(width: max(1, width - safe.left - safe.right), height: max(1, height - safe.top - safe.bottom))
        let short = min(viewport.width, viewport.height), long = max(viewport.width, viewport.height)
        // The unfolded display uses the same desktop chrome and floating
        // window behavior as iPad. Phone-sized controls belong to the outer
        // display, not to a phone's tablet-sized inner screen.
        let inner = mode != "desktop" && short >= 450 &&
            (mode == "duo" || (phone && long / short <= 1.8))
        let touch = !inner && (mode == "duo" || (mode != "desktop" && phone))
        // Keep top/camera and side protections, but let the inner desktop reach
        // the bottom edge instead of leaving a separate strip below the Dock.
        if inner { safe.bottom = min(12, safe.bottom) }
        let fitted = CGSize(width: viewport.width, height: max(1, height - safe.top - safe.bottom))
        return Layout(viewport: fitted, insets: safe, usesTouchLayout: touch,
                      innerDisplay: inner)
    }

    static func isPhone(idiom: Bool, model: String, hardware: String) -> Bool {
        idiom || model.localizedCaseInsensitiveContains("iPhone") ||
            model.localizedCaseInsensitiveContains("Duo") || hardware.hasPrefix("iPhone")
    }
}
