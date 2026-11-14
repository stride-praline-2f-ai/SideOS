import Foundation

enum TahoeMenuPointerIntent {
    static func towardSubmenu(from previous: CGPoint, to point: CGPoint, submenu: CGRect) -> Bool {
        guard !submenu.contains(previous), previous != point else { return false }
        let edge = previous.x < submenu.minX ? submenu.minX : submenu.maxX
        guard abs(point.x - edge) < abs(previous.x - edge) else { return false }
        let b = CGPoint(x: edge, y: submenu.minY - 8), c = CGPoint(x: edge, y: submenu.maxY + 8)
        func cross(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) }
        let signs = [cross(previous, b, point), cross(b, c, point), cross(c, previous, point)]
        return signs.allSatisfy { $0 >= 0 } || signs.allSatisfy { $0 <= 0 }
    }
}
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Shared interaction rules, independent of SwiftUI so boundaries can be tested.
/// macos-components slider/menu behaviour, MacVue bounded controls and
/// macos_ui toolbar overflow are adapted here. See Notices/ for revisions.
enum TahoeNumeric {
    static func stepping(_ current: Double, direction: Int, in range: ClosedRange<Double>, step: Double, wraps: Bool) -> Double {
        guard step.isFinite, step > 0 else { return value(current, in: range) }
        let next = current + Double(direction < 0 ? -1 : 1) * step
        if next > range.upperBound { return wraps && current >= range.upperBound ? range.lowerBound : range.upperBound }
        if next < range.lowerBound { return wraps && current <= range.lowerBound ? range.upperBound : range.lowerBound }
        return value(next, in: range)
    }
    static func value(_ value: Double, in range: ClosedRange<Double>, step: Double = 0) -> Double {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else { return 0 }
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        guard step.isFinite, step > 0, clamped != range.upperBound else { return clamped }
        // Anchor steps at the lower bound, including non-zero/non-integral minima.
        let snapped = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, (snapped * 1_000_000).rounded() / 1_000_000))
    }
    static func fraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (self.value(value, in: range) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

enum TahoeCheckState: String { case off, on, mixed }

struct TahoeSelection<ID: Hashable> {
    var selected: Set<ID> = []
    var anchor: ID?
    var lead: ID?

    mutating func select(_ id: ID, ordered: [ID], extending: Bool = false, toggling: Bool = false) {
        guard ordered.contains(id) else { return }
        if extending, let anchor, let start = ordered.firstIndex(of: anchor), let end = ordered.firstIndex(of: id) {
            let range = Set(ordered[min(start, end)...max(start, end)])
            selected = toggling ? selected.union(range) : range
        } else if toggling {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        } else { selected = [id]; anchor = id }
        lead = id
    }
    mutating func move(_ offset: Int, ordered: [ID], extending: Bool = false) {
        guard !ordered.isEmpty else { return }
        let index = lead.flatMap { ordered.firstIndex(of: $0) } ?? (offset < 0 ? ordered.count : -1)
        select(ordered[min(ordered.count - 1, max(0, index + offset))], ordered: ordered, extending: extending)
    }
    mutating func selectAll(_ ordered: [ID]) { selected = Set(ordered); anchor = ordered.first; lead = ordered.last }
    mutating func clear() { selected.removeAll(); anchor = nil; lead = nil }
    mutating func reconcile(_ ordered: [ID]) {
        selected.formIntersection(ordered)
        if let anchor, !ordered.contains(anchor) { self.anchor = nil }
        if let lead, !ordered.contains(lead) { self.lead = ordered.first(where: { selected.contains($0) }) }
    }
}

enum TahoeMenuNavigation {
    static func next(from current: Int?, direction: Int, enabled: [Bool]) -> Int? {
        guard !enabled.isEmpty, enabled.contains(true) else { return nil }
        let delta = direction < 0 ? -1 : 1
        let start = current ?? (delta > 0 ? -1 : 0)
        for distance in 1...enabled.count {
            let index = ((start + distance * delta) % enabled.count + enabled.count) % enabled.count
            if enabled[index] { return index }
        }
        return nil
    }
    static func match(_ query: String, titles: [String], enabled: [Bool], after current: Int?) -> Int? {
        guard !query.isEmpty, titles.count == enabled.count, !titles.isEmpty else { return nil }
        for distance in 1...titles.count {
            let index = ((current ?? -1) + distance) % titles.count
            if enabled[index], titles[index].folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .hasPrefix(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) { return index }
        }
        return nil
    }
}

enum TahoePopupGeometry {
    static func frame(anchor: CGRect, size: CGSize, canvas: CGSize, submenu: Bool = false) -> CGRect {
        let width = min(max(0, size.width), max(0, canvas.width - 8))
        let height = min(max(0, size.height), max(0, canvas.height - 8))
        var x = submenu ? anchor.maxX + 2 : anchor.minX
        var y = submenu ? anchor.minY : anchor.maxY + 3
        if x + width > canvas.width - 4 { x = submenu ? anchor.minX - width - 2 : canvas.width - width - 4 }
        if y + height > canvas.height - 4 { y = submenu ? canvas.height - height - 4 : anchor.minY - height - 3 }
        return CGRect(x: max(4, min(x, canvas.width - width - 4)), y: max(4, min(y, canvas.height - height - 4)), width: width, height: height)
    }
}

enum TahoeToolbarOverflow {
    /// Preserve a visible prefix and reserve room for the overflow button only
    /// when required. Hidden commands keep their order and remain reachable.
    static func visibleCount(widths: [CGFloat], available: CGFloat, spacing: CGFloat = 6, overflow: CGFloat = 28) -> Int {
        let total = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * spacing
        if total <= available { return widths.count }
        var used: CGFloat = 0
        var count = 0
        for width in widths {
            let next = used + (count > 0 ? spacing : 0) + max(0, width)
            guard next + spacing + overflow <= available else { break }
            used = next; count += 1
        }
        return count
    }
}

enum TahoeDesktopLayout {
    static let itemSize = CGSize(width: 100, height: 96)
    static func frame(index: Int, canvas: CGSize, saved: CGPoint? = nil) -> CGRect {
        let rows = max(1, Int(max(96, canvas.height - 110) / 110))
        let point = saved ?? CGPoint(x: canvas.width - 66 - CGFloat(index / rows) * 114, y: 60 + CGFloat(index % rows) * 110)
        let half = CGSize(width: itemSize.width / 2, height: itemSize.height / 2)
        let center = CGPoint(x: max(half.width, min(point.x.isFinite ? point.x : half.width, canvas.width - half.width)),
                             y: max(half.height, min(point.y.isFinite ? point.y : half.height, canvas.height - half.height)))
        return CGRect(x: center.x - half.width, y: center.y - half.height, width: itemSize.width, height: itemSize.height)
    }
    static func selection(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

/// Resting geometry is independent of hover geometry, avoiding a feedback loop
/// as magnified icons move. Separators take an explicit slot in the fit budget.
struct TahoeDockGeometry {
    let iconSize: CGFloat
    let widths: [CGFloat]
    let naturalWidth: CGFloat
    let renderedWidth: CGFloat
    let centers: [CGFloat]
    static func layout(count: Int, available: CGFloat, maximum: CGFloat, automatic: Bool,
                       separatorBefore: Set<Int> = [], magnification: Bool = false, pointer: CGFloat? = nil,
                       minimumSlot: CGFloat = 0) -> Self {
        guard count > 0 else { return Self(iconSize: 0, widths: [], naturalWidth: 22, renderedWidth: 22, centers: []) }
        let separators = separatorBefore.filter { $0 > 0 && $0 < count }
        // HStack includes both gaps around each 6.5-point separator.
        let fixed = 22 + CGFloat(count - 1 + separators.count) * 8 + CGFloat(separators.count) * 6.5
        let maximum = min(128, max(24, maximum.isFinite ? maximum : 48))
        let available = max(1, available.isFinite ? available : 1)
        let reserve = magnification ? min(maximum * 1.2, available * 0.1) : 0
        let size = automatic ? min(maximum, max(20, (available - fixed - reserve) / CGFloat(count))) : maximum
        let slot = max(0, minimumSlot.isFinite ? minimumSlot : 0)
        let natural = fixed + CGFloat(count) * max(slot, size)
        var x: CGFloat = 11
        var centers: [CGFloat] = []
        for index in 0..<count {
            if separators.contains(index) { x += 14.5 }
            centers.append(x + max(slot, size) / 2)
            x += max(slot, size) + 8
        }
        let extra = centers.map { center -> CGFloat in
            guard let pointer, pointer.isFinite else { return 0 }
            let distance = (pointer - center) / (size * 1.05)
            return size * 0.45 * exp(-distance * distance / 2)
        }
        let requested = extra.reduce(0, +)
        let fraction = requested > 0 ? min(1, max(0, available - natural) / requested) : 0
        let widths = extra.map { size + $0 * fraction }
        return Self(iconSize: size, widths: widths, naturalWidth: natural,
                    renderedWidth: fixed + widths.reduce(0) { $0 + max(slot, $1) }, centers: centers)
    }
}
