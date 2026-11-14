import SwiftUI
import CoreVideo

@MainActor final class TahoeWirelessDisplay: ObservableObject {
    static let shared = TahoeWirelessDisplay()
    @Published private(set) var hosting = false
    @Published private(set) var connected = false
    @Published private(set) var status = "Start a display link on the device running your apps."
    @Published private(set) var key = ""
    @Published private(set) var name = ""
    @Published private(set) var port: UInt16?
    private weak var anchor: UIView?
    private var content: (() -> AnyView)?
    private var displayWindow: UIWindow?
    private var transport: TahoeDisplayTransport?
    private var encoder: TahoeDisplayEncoder?
    private var captureTask: Task<Void, Never>?
    private var generation = UUID()
    private var mode: TahoeDisplayMode?
    private var credits = TahoeDisplayCredits()
    private var sequence: UInt64 = 0
    func configure(anchor: UIView, content: @escaping () -> AnyView) {
        self.anchor = anchor; self.content = content
        if let controller = displayWindow?.rootViewController as? UIHostingController<AnyView> { controller.rootView = content() }
    }
    func start() {
        stop()
        guard anchor?.window?.windowScene != nil, content != nil else { status = "Open the desktop before starting a display link."; return }
        do {
            key = try TahoeDisplayTransport.newKey(); name = "SideOS-" + UUID().uuidString
            hosting = true; status = "Starting an encrypted local display link…"
            let run = generation, credits = self.credits
            let channel = TahoeDisplayTransport(status: { [weak self] text, state in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.status = text
                    if state == .failed { self.stop(keeping: text) }
                    else { self.connected = state == .connected }
                }
            }, packet: { [weak self] packet in
                // The host never accepts image data or any application input.
                guard packet.kind == 1, let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data) else {
                    Task { @MainActor in guard let self, self.generation == run else { return }; self.stop(keeping: "The viewer sent invalid display data.") }; return
                }
                if command.type == "ack", let sequence = command.sequence { credits.consumed(sequence); return }
                Task { @MainActor in guard let self, self.generation == run else { return }; self.receive(command, run: run) }
            }, listening: { [weak self] port in
                Task { @MainActor in guard let self, self.generation == run else { return }; self.port = port }
            })
            transport = channel; channel.host(key: key, name: name)
        } catch { stop(keeping: error.localizedDescription) }
    }
    private func receive(_ control: TahoeDisplayControl, run: UUID) {
        guard control.type == "offer", let mode = control.mode, self.mode == nil, let main = anchor?.window,
              let scene = main.windowScene, let content, let transport else { stop(keeping: "Unexpected display negotiation. Pair again."); return }
        do {
            try control.validate()
            let created = try TahoeDisplayEncoder(mode: mode, output: { [weak transport, credits] data, sequence in
                guard let transport else { credits.sent(sequence, okay: false); return }
                transport.send(TahoeDisplayPacket(kind: 2, data: data), completion: { credits.sent(sequence, okay: $0) })
            }, failure: { [weak self] text in
                Task { @MainActor in guard let self, self.generation == run else { return }; self.stop(keeping: text) }
            }, dropped: { [credits] sequence in credits.sent(sequence, okay: false) })
            encoder = created; self.mode = mode
            let size = CGSize(width: CGFloat(mode.pointsWide), height: CGFloat(mode.pointsHigh))
            TahoeWorkspace.shared.state.setWirelessCanvas(size)
            // A separate non-key presentation window keeps the primary canvas
            // and its safe-area geometry unchanged. Guest sessions remain on
            // the host and are reparented, rather than relaunched or exported.
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.windowLevel = UIWindow.Level(rawValue: main.windowLevel.rawValue - 1)
            window.isUserInteractionEnabled = false; window.backgroundColor = .black
            let controller = UIHostingController(rootView: content())
            controller.safeAreaRegions = []
            window.rootViewController = controller; controller.view.frame = window.bounds
            displayWindow = window; window.isHidden = false
            transport.send(TahoeDisplayControl(type: "accept", mode: mode))
            status = "Display ready · \(mode.width) × \(mode.height). Move a window from the list below or its Dock menu."
            captureTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                let clock = ContinuousClock()
                while let self, self.generation == run, !Task.isCancelled {
                    // Include capture time in the frame period. A slow frame
                    // starts a fresh period rather than triggering catch-up bursts.
                    let started = clock.now
                    self.capture(run: run)
                    do { try await Task.sleep(for: TahoeDisplayTiming.delay(afterCapture: started.duration(to: clock.now))) } catch { return }
                }
            }
        } catch { stop(keeping: error.localizedDescription) }
    }
    private func capture(run: UUID) {
        guard generation == run, let mode, let window = displayWindow, let encoder else { return }
        guard abs(window.bounds.width - CGFloat(mode.pointsWide)) < 1, abs(window.bounds.height - CGFloat(mode.pointsHigh)) < 1 else {
            stop(keeping: "iOS restricted the secondary presentation size. Windows have returned locally."); return
        }
        if credits.oldestAge > 8 { stop(keeping: "The display decoder stopped acknowledging frames. Windows have returned locally."); return }
        sequence &+= 1; let number = sequence
        guard credits.begin(number) else { return }
        var pixel: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, encoder.pool, attributes, &pixel) == kCVReturnSuccess, let pixel else {
            credits.sent(number, okay: false); return
        }
        CVPixelBufferLockBaseAddress(pixel, [])
        var locked = true
        defer { if locked { CVPixelBufferUnlockBaseAddress(pixel, []) } }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: mode.codedWidth, height: mode.codedHeight,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            stop(keeping: "Cannot create the native display capture surface."); return
        }
        context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(x: 0, y: 0, width: CGFloat(mode.codedWidth), height: CGFloat(mode.codedHeight)))
        context.translateBy(x: 0, y: CGFloat(mode.codedHeight))
        context.scaleBy(x: CGFloat(mode.width) / CGFloat(mode.pointsWide), y: -CGFloat(mode.height) / CGFloat(mode.pointsHigh))
        UIGraphicsPushContext(context)
        let captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        UIGraphicsPopContext()
        guard captured else { stop(keeping: "iOS could not capture this hosted display. Windows have returned to the main screen."); return }
        CVPixelBufferUnlockBaseAddress(pixel, []); locked = false
        encoder.encode(TahoeDisplayPixel(buffer: pixel), sequence: number)
    }
    func move(_ id: UUID, remote: Bool) {
        guard !remote || mode != nil else { return }
        TahoeWindowMotion.shared.cancel(id)
        TahoeWorkspace.shared.state.moveToWirelessDisplay(id, enabled: remote)
    }
    func stop(keeping message: String? = nil) {
        generation = UUID(); captureTask?.cancel(); captureTask = nil
        transport?.stop(); transport = nil; encoder?.stop(); encoder = nil
        // Publish local placement first. The old projection wrapper can safely
        // dismantle after a fresh wrapper takes over the same guest controller.
        TahoeWorkspace.shared.state.setWirelessCanvas(nil)
        displayWindow?.isHidden = true; displayWindow?.rootViewController = nil; displayWindow = nil
        credits.reset(); credits = TahoeDisplayCredits(); sequence = 0; mode = nil
        hosting = false; connected = false; key = ""; name = ""; port = nil
        status = message ?? "Display link stopped. All windows are on the main display."
    }
}

struct TahoeDisplayAnchor: UIViewRepresentable {
    @EnvironmentObject private var workspace: TahoeWorkspace
    @EnvironmentObject private var model: SharedModel
    @Environment(\.tahoeManagementHost) private var management
    @ObservedObject private var preferences = TahoePreferences.shared
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: UIView, context: Context) {
        let workspace = workspace, model = model, management = management
        let scheme = preferences.colorScheme, oled = preferences.value.appearance == "oled", accent = preferences.value.accentColor
        TahoeWirelessDisplay.shared.configure(anchor: view, content: {
            AnyView(TahoeWirelessCanvas(workspace: workspace).environmentObject(workspace).environmentObject(model)
                .environment(\.tahoeManagementHost, management).environment(\.tahoeOLED, oled)
                .preferredColorScheme(scheme).tint(accent))
        })
    }
}

private struct TahoeWirelessCanvas: View {
    @ObservedObject var workspace: TahoeWorkspace
    var body: some View {
        let size = workspace.state.wirelessCanvas ?? CGSize(width: 640, height: 480)
        ZStack(alignment: .topLeading) {
            TahoeWallpaper().allowsHitTesting(false)
            VStack(spacing: 12) {
                Image(systemName: "display.2").font(.system(size: 48))
                Text("SideOS Extended Display").font(.title2.bold())
                Text("Move a window here using Window → Move to Wireless Display on the host.")
                    .multilineTextAlignment(.center).font(.callout)
            }.padding(40).frame(width: size.width, height: size.height).foregroundStyle(.white).shadow(radius: 4)
            ForEach(Array(workspace.state.windows.filter { $0.onWirelessDisplay == true }.enumerated()), id: \.element.id) { index, window in
                TahoeDesktopWindow(window: window, workspace: workspace) { TahoeWindowContent(window: window, workspace: workspace) }
                    .zIndex(Double(index))
            }
        }.frame(width: size.width, height: size.height).clipped().coordinateSpace(name: "tahoe-desktop")
    }
}
