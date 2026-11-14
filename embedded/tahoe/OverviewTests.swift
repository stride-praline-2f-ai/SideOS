import Foundation
@main struct TahoeOverviewTests {
    static func main() {
        for canvas in [CGSize(width: 320, height: 240), CGSize(width: 1024, height: 650), CGSize(width: 1376, height: 850)] {
            for count in 1...40 {
                let sizes = (0..<count).map { i in i % 2 == 0 ? CGSize(width: 800, height: 530) : CGSize(width: 360, height: 700) }
                let frames = TahoeOverviewLayout.frames(sizes: sizes, canvas: canvas)
                precondition(frames.count == count)
                for (i, frame) in frames.enumerated() {
                    precondition(CGRect(origin: .zero, size: canvas).contains(frame))
                    precondition(abs(frame.width / frame.height - sizes[i].width / sizes[i].height) < 0.001)
                    for other in frames.dropFirst(i + 1) { precondition(!frame.intersects(other)) }
                }
            }
        }
        precondition(TahoeOverviewLayout.frames(sizes: [], canvas: CGSize(width: 1000, height: 700)).isEmpty)
        var state = TahoeWindowState()
        let guest = state.open(.guest, title: "Guest", resourceID: "container")
        state.moveToSpace(guest, space: 2)
        state.switchSpace(2)
        state.removeSpace(2)
        precondition(state.spaceCount == 2 && state.currentSpace == 1)
        precondition(state.windows.first(where: { $0.id == guest })?.space == 1)
        state.removeSpace(0); state.removeSpace(0)
        precondition(state.spaceCount == 1 && state.windows.contains(where: { $0.id == guest }))
        print("Overview aspect ratio, bounds and non-overlap checks passed for 1–40 windows")
    }
}
