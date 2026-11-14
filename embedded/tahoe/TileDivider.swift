import SwiftUI

struct TahoeTileDivider: View {
    @ObservedObject var workspace: TahoeWorkspace
    @State private var hovered = false
    private var shown: Bool {
        let visible = workspace.state.windows.filter { workspace.state.isVisible($0) }
        return workspace.state.fullscreenID == nil && workspace.overlay == nil && workspace.state.canApply(.left) &&
            visible.contains { $0.layout == .left } && visible.contains { $0.layout == .right }
    }
    var body: some View {
        if shown {
            let area = workspace.state.workArea
            Rectangle().fill(hovered ? TahoeDesign.accent.opacity(0.7) : Color.clear)
                .frame(width: 8, height: area.height)
                .position(x: area.minX + area.width * workspace.state.displayedTileFraction, y: area.midY)
                .contentShape(Rectangle()).onHover { hovered = $0 }
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tahoe-desktop")).onChanged { value in
                    workspace.state.setTileFraction((value.location.x - area.minX) / area.width)
                })
                .accessibilityElement().accessibilityLabel("Resize tiled windows")
                .accessibilityValue("\(Int(workspace.state.displayedTileFraction * 100)) percent left")
                .accessibilityAdjustableAction { workspace.state.setTileFraction(workspace.state.tileFraction + ($0 == .increment ? 0.05 : -0.05)) }
        }
    }
}
