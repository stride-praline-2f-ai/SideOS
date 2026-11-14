import SwiftUI

@MainActor final class TahoeWindowInteraction: ObservableObject {
    struct Presentation: Equatable {
        var frame: CGRect?
        var translation: CGSize = .zero
    }
    @Published private(set) var presentation = Presentation()
    private(set) var start: CGRect?
    var active: Bool { start != nil }
    func begin(_ frame: CGRect, restored: Bool = false) {
        start = frame
        if restored { presentation = Presentation(frame: frame) }
    }
    func move(_ translation: CGSize, area: CGRect) {
        guard let start else { return }
        let moved = TahoeWindowGeometry.moved(start, translation: translation, area: area)
        let next = Presentation(frame: presentation.frame,
            translation: CGSize(width: moved.minX - start.minX, height: moved.minY - start.minY))
        if presentation != next { presentation = next }
    }
    func resize(_ translation: CGSize, edge: TahoeResizeEdge, area: CGRect) {
        guard let start else { return }
        let next = Presentation(frame: TahoeWindowGeometry.resized(start, edge: edge, translation: translation, area: area))
        if presentation != next { presentation = next }
    }
    func reset() {
        start = nil
        if presentation != Presentation() { presentation = Presentation() }
    }
}

/// Only this small modifier subscribes to pointer-rate updates. Content keeps
/// its identity and original size during translation, including WKWebView and
/// LiveContainer's remote UIKit surface. Never rasterize either live surface.
struct TahoeWindowPlacement: ViewModifier {
    @ObservedObject var interaction: TahoeWindowInteraction
    let frame: CGRect
    let minimized: Bool
    let target: CGPoint
    let layout: TahoeWindowLayout
    let fullscreen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let display = interaction.presentation.frame ?? frame
        content.frame(width: display.width, height: display.height)
            .scaleEffect(minimized && !reduceMotion ? 0.10 : 1)
            .position(x: minimized && !reduceMotion ? target.x : display.midX,
                      y: minimized && !reduceMotion ? target.y : display.midY)
            .offset(interaction.presentation.translation)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.9), value: layout)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: minimized)
            .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: fullscreen)
            .transaction { if interaction.active { $0.animation = nil } }
    }
}
