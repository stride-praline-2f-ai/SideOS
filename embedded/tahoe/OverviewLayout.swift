import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// Aspect-preserving overview cells; no live web/guest views are reparented.
enum TahoeOverviewLayout {
    static func frames(sizes: [CGSize], canvas: CGSize) -> [CGRect] {
        guard !sizes.isEmpty, canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 else { return [] }
        let columns = min(sizes.count, max(1, Int(ceil(sqrt(Double(sizes.count))))))
        let rows = Int(ceil(Double(sizes.count) / Double(columns)))
        let gap: CGFloat = 28
        let cellW = max(1, (canvas.width - gap * CGFloat(columns + 1)) / CGFloat(columns))
        let cellH = max(1, (canvas.height - gap * CGFloat(rows + 1)) / CGFloat(rows))
        return sizes.enumerated().map { index, size in
            let scale = min(cellW / max(1, size.width), cellH / max(1, size.height))
            let w = max(1, size.width) * scale, h = max(1, size.height) * scale
            let row = index / columns, column = index % columns
            let rowCount = min(columns, sizes.count - row * columns)
            let rowWidth = CGFloat(rowCount) * cellW + CGFloat(rowCount - 1) * gap
            return CGRect(x: (canvas.width - rowWidth) / 2 + CGFloat(column) * (cellW + gap) + (cellW - w) / 2,
                          y: gap + CGFloat(row) * (cellH + gap) + (cellH - h) / 2, width: w, height: h)
        }
    }
}
