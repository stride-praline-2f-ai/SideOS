import Foundation
@main struct TahoeIconCropTests {
    static func main() {
        let side: CGFloat = 512
        for size in [CGSize(width: 1000, height: 500), CGSize(width: 500, height: 1000), CGSize(width: 512, height: 512)] {
            for z in [1.0, 2.0, 5.0] {
                for x in [-1.0, 0.0, 1.0] {
                    for y in [-1.0, 0.0, 1.0] {
                        let rect = TahoeIconCrop(zoom: z, x: x, y: y).imageRect(size: size, side: side)
                        precondition(rect.minX <= 0.001 && rect.minY <= 0.001)
                        precondition(rect.maxX >= side - 0.001 && rect.maxY >= side - 0.001)
                    }
                }
            }
        }
        precondition(TahoeIconCrop().imageRect(size: .zero, side: 512) == .zero)
        precondition(TahoeIconCrop(zoom: .nan, x: .infinity, y: .nan).imageRect(size: CGSize(width: 512, height: 512), side: 512) == CGRect(x: 0, y: 0, width: 512, height: 512))
        print("Icon crop landscape/portrait, zoom, pan coverage and invalid-input checks passed")
    }
}
