import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
struct TahoeIconCrop: Equatable {
    var zoom = 1.0
    var x = 0.0
    var y = 0.0
    func imageRect(size: CGSize, side: CGFloat) -> CGRect {
        guard side.isFinite, side > 0, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return .zero }
        let z = zoom.isFinite ? min(5, max(1, zoom)) : 1
        let scale = max(side / size.width, side / size.height) * z
        let width = size.width * scale, height = size.height * scale
        let px = x.isFinite ? min(1, max(-1, x)) : 0
        let py = y.isFinite ? min(1, max(-1, y)) : 0
        return CGRect(x: (side - width) / 2 + px * (width - side) / 2,
                      y: (side - height) / 2 + py * (height - side) / 2,
                      width: width, height: height)
    }
}
