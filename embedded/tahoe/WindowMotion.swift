import SwiftUI
import Metal

private final class TahoeMotionBundle: NSObject {}

@MainActor final class TahoeWindowMotion: ObservableObject {
    static let shared = TahoeWindowMotion()
    struct Capture {
        let image: UIImage
        let source: CGRect
        let target: CGRect
        let canvas: CGSize
        let lightweight: Bool
    }
    @Published private(set) var flights: [UUID: TahoeMotionTrack] = [:]
    private(set) var captures: [UUID: Capture] = [:]
    private var captureOrder: [UUID] = []
    private var completions: [UUID: Task<Void, Never>] = [:]
    private lazy var shaderAvailable: Bool = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle(for: TahoeMotionBundle.self)) else { return false }
        return library.makeFunction(name: "tahoeGenie") != nil
    }()
    /// Capture only an unobscured frontmost app-owned window. Guests, partially
    /// offscreen windows and mismatched host coordinates use the scale fallback.
    func prepare(_ window: TahoeWindow, workspace: TahoeWorkspace, target: CGPoint) {
        if captures[window.id] != nil && flights[window.id] != nil { return }
        cancel(window.id)
        guard !UIAccessibility.isReduceMotionEnabled,
              window.onWirelessDisplay != true,
              window.kind != .guest, window.kind != .installer, workspace.state.activeID == window.id,
              workspace.state.fullscreenID == nil, let host = TahoeKeyboard.window else { return }
        let frame = workspace.state.displayFrame(window)
        let canvas = workspace.state.canvas
        let viewport = TahoeDisplayMetrics.shared.layout(for: host.bounds.size)
        let hostFrame = viewport.hostFrame(frame)
        guard abs(viewport.viewport.width - canvas.width) < 2, abs(viewport.viewport.height - canvas.height) < 2,
              host.bounds.contains(hostFrame), frame.minY >= TahoeDesign.menuBarHeight,
              frame.maxY < canvas.height - workspace.state.dockInset else { return }
        // Bound retained textures. Eviction finishes the visual transition only;
        // semantic window state has already changed and remains authoritative.
        if captures.count >= 2, let oldest = captureOrder.first { cancel(oldest) }
        let format = UIGraphicsImageRendererFormat()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        format.scale = min(1, (lowPower ? 768 : 1024) / max(frame.width, frame.height))
        format.opaque = false
        var success = false
        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            context.cgContext.translateBy(x: -hostFrame.minX, y: -hostFrame.minY)
            success = host.drawHierarchy(in: host.bounds, afterScreenUpdates: false)
        }
        guard success else { return }
        captures[window.id] = Capture(image: image, source: frame,
            target: CGRect(x: target.x - 16, y: target.y - 16, width: 32, height: 32),
            canvas: canvas, lightweight: lowPower || !shaderAvailable)
        captureOrder.append(window.id)
    }
    func transition(_ id: UUID, minimized: Bool) {
        guard captures[id] != nil, !UIAccessibility.isReduceMotionEnabled else { cancel(id); return }
        completions[id]?.cancel()
        let now = Date.timeIntervalSinceReferenceDate
        let end = minimized ? 1.0 : 0.0
        let track = flights[id]?.reversed(at: now, to: end) ?? TahoeMotionTrack(
            token: UUID(), from: 1 - end, to: end, start: now,
            duration: TahoeMotionSpec.resolve(minimized ? .minimizeWindow : .restoreWindow, reduced: false).duration)
        flights[id] = track
        completions[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(track.duration))
            guard !Task.isCancelled, let self, self.flights[id]?.token == track.token else { return }
            self.flights.removeValue(forKey: id)
            self.completions.removeValue(forKey: id)
            if !minimized { self.captures.removeValue(forKey: id) }
        }
    }
    func cancel(_ id: UUID) {
        completions.removeValue(forKey: id)?.cancel()
        if flights[id] != nil { flights.removeValue(forKey: id) }
        captures.removeValue(forKey: id)
        captureOrder.removeAll { $0 == id }
    }
    func cancelAll() { for id in Set(captures.keys).union(flights.keys) { cancel(id) } }
}

struct TahoeWindowMotionOverlay: View {
    @ObservedObject private var motion = TahoeWindowMotion.shared
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(motion.flights.keys), id: \.self) { id in
                if let capture = motion.captures[id], let track = motion.flights[id] {
                    TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 60.0 : 1.0 / 120.0)) { tick in
                        let p = track.progress(at: tick.date.timeIntervalSinceReferenceDate)
                        if lowPower || capture.lightweight {
                            // No full-canvas distortion when the system is power-limited.
                            let frame = track.rectangle(from: capture.source, to: capture.target,
                                                        at: tick.date.timeIntervalSinceReferenceDate)
                            Image(uiImage: capture.image).resizable()
                                .frame(width: capture.source.width, height: capture.source.height)
                                .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.windowRadius))
                                .scaleEffect(x: frame.width / capture.source.width,
                                             y: frame.height / capture.source.height)
                                .position(x: frame.midX, y: frame.midY)
                        } else {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                            Image(uiImage: capture.image).resizable()
                                .frame(width: capture.source.width, height: capture.source.height)
                                .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.windowRadius))
                                .offset(x: capture.source.minX, y: capture.source.minY)
                        }.frame(width: capture.canvas.width, height: capture.canvas.height)
                            .compositingGroup()
                            .layerEffect(Shader(function: ShaderFunction(library: .bundle(Bundle(for: TahoeMotionBundle.self)), name: "tahoeGenie"), arguments: [
                                .float4(Float(capture.source.minX), Float(capture.source.minY), Float(capture.source.width), Float(capture.source.height)),
                                .float4(Float(capture.target.minX), Float(capture.target.minY), Float(capture.target.width), Float(capture.target.height)), .float(Float(p))
                            ]), maxSampleOffset: capture.canvas)
                        }
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}
