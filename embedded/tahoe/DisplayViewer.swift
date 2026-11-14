import SwiftUI
import AVFoundation

@MainActor final class TahoeDisplayViewer: ObservableObject {
    @Published private(set) var status = "Choose the host device and enter its pairing key."
    @Published private(set) var ready = false
    private var channel: TahoeDisplayTransport?
    private var receiver: TahoeDisplayReceiver?
    private var generation = UUID()
    var pixel: ((CVPixelBuffer) -> Void)?
    func connect(peer: TahoeDisplayPeer?, host: String, port: UInt16, key: String, mode: TahoeDisplayMode) {
        disconnect(); let run = generation
        do {
            try mode.validate()
            let slot = TahoeDisplayReceiverSlot()
            let transport = TahoeDisplayTransport(status: { [weak self] text, state in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.status = text
                    if state == .connected { self.channel?.send(TahoeDisplayControl(type: "offer", mode: mode)) }
                    else if state == .failed { self.disconnect(keeping: text) }
                }
            }, packet: { slot.receive($0) })
            channel = transport
            let mailbox = TahoeDisplayPixelMailbox { [weak self] pixel in
                guard let self, self.generation == run, self.ready else { return }
                self.pixel?(pixel.buffer)
            }
            let receiver = TahoeDisplayReceiver(mode: mode, accepted: { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.ready = true; self.status = "Connected · move a window to Wireless Display on the host."
                }
            }, output: { mailbox.submit($0) },
            consumed: { [weak transport] sequence in transport?.send(TahoeDisplayControl(type: "ack", sequence: sequence)) },
            failure: { [weak self] text in
                Task { @MainActor in guard let self, self.generation == run else { return }; self.disconnect(keeping: text) }
            })
            self.receiver = receiver; slot.install(receiver)
            transport.connect(endpoint: peer?.endpoint, host: host, port: port, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
            status = "Pairing over the local network…"
        } catch { disconnect(keeping: error.localizedDescription) }
    }
    func disconnect(keeping message: String? = nil) {
        generation = UUID(); ready = false
        channel?.stop(); channel = nil; receiver?.stop(); receiver = nil
        status = message ?? "Display disconnected."
    }
}

struct TahoeDisplayViewerScreen: View {
    @StateObject private var viewer = TahoeDisplayViewer()
    @StateObject private var discovery = TahoeDisplayDiscovery()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var selected: TahoeDisplayPeer?
    @State private var manual = false
    @State private var host = ""
    @State private var port = ""
    @State private var key = ""
    @State private var started = false
    @State private var hidden = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black
                if started {
                    TahoeDisplayVideoSurface(viewer: viewer, toggle: { hidden.toggle() })
                        .accessibilityLabel("Read-only extended SideOS display")
                        .accessibilityHint("Three-finger tap shows or hides local display controls.")
                        .accessibilityAction(named: Text(hidden ? "Show display controls" : "Hide display controls")) { hidden.toggle() }
                    if !hidden || !viewer.ready {
                        HStack {
                            Button("Disconnect") { viewer.disconnect(); started = false; discovery.start() }
                            Spacer(); Text(viewer.status).font(.caption).lineLimit(2); Spacer()
                            if viewer.ready { Button("Hide") { hidden = true } }
                            Button("Done") { dismiss() }
                        }.padding(12).background(.regularMaterial)
                    }
                } else {
                    NavigationStack {
                        Form {
                            Section("Use this device as an extended display") {
                                Text("Apps run on the host. This screen receives a separate SideOS display over your local Wi-Fi network. It sends no mouse, touch or keyboard input. Rotate to the orientation you want before connecting.")
                                ForEach(discovery.peers) { peer in
                                    Button { selected = peer } label: {
                                        HStack { Text(peer.label); Spacer(); if selected?.id == peer.id { Image(systemName: "checkmark") } }
                                    }
                                }
                                if discovery.peers.isEmpty { Text("No hosts found yet. Start the display link on the other device and allow Local Network access on both.").font(.footnote) }
                                Toggle("Use manual IP and port", isOn: $manual)
                                if manual {
                                    TextField("Host's local IPv4 address", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                    TextField("Connection port", text: $port).keyboardType(.numberPad)
                                }
                                SecureField("43-character pairing key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                                Text("Keys last for one host session and are never saved or advertised. Only pair devices you trust. No internet relay or port forwarding is used.").font(.footnote)
                                Button("Connect extended display") {
                                    let scale = geometry.size.width > 0 ? (TahoeWorkspace.shared.hostWindow?.screen.nativeScale ?? 2) : 2
                                    let mode = TahoeDisplayMode(width: Int((geometry.size.width * scale).rounded()), height: Int((geometry.size.height * scale).rounded()),
                                        pointsWide: Int(geometry.size.width.rounded()), pointsHigh: Int(geometry.size.height.rounded()))
                                    discovery.stop(); started = true; hidden = false
                                    viewer.connect(peer: manual ? nil : selected, host: host, port: UInt16(port) ?? 0, key: key, mode: mode)
                                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).count != 43 || (manual ? host.isEmpty || (UInt16(port) ?? 0) == 0 : selected == nil))
                                Text(viewer.status).font(.footnote)
                            }
                            Section("On the host") {
                                Text("Use Window → Move to Wireless Display, the window's Dock menu, or Settings → Wireless Display. The display shows a separate app window while the main screen stays available. Bring the window back to interact with it. Disconnecting automatically returns every window to the main screen.")
                                Text("Keep both devices in the foreground. The display path is capped at 60 frames per second and uses hardware H.264 compression with at most two outstanding frames. Protected or uncapturable content may be blank; verify each hosted app on the actual devices before relying on it.").font(.footnote)
                            }
                        }.navigationTitle("Extended Display")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(started && hidden)
        .onAppear { discovery.start() }
        .onChange(of: viewer.ready) { _, ready in UIApplication.shared.isIdleTimerDisabled = ready; if !ready { hidden = false } }
        .onChange(of: phase) { _, value in
            if value == .background { viewer.disconnect(); discovery.stop(); started = false; UIApplication.shared.isIdleTimerDisabled = false }
            else if value == .active && !started { discovery.start() }
        }
        .onDisappear { discovery.stop(); viewer.disconnect(); UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct TahoeDisplayVideoSurface: UIViewRepresentable {
    let viewer: TahoeDisplayViewer
    let toggle: () -> Void
    func makeUIView(context: Context) -> TahoeDisplayVideoView {
        let view = TahoeDisplayVideoView(); view.toggle = toggle
        viewer.pixel = { [weak view] pixel in view?.show(pixel) }; return view
    }
    func updateUIView(_ view: TahoeDisplayVideoView, context: Context) { view.toggle = toggle }
    static func dismantleUIView(_ view: TahoeDisplayVideoView, coordinator: ()) { view.toggle = nil; view.display.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil) }
}

private final class TahoeDisplayVideoView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var display: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    var toggle: (() -> Void)?
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .black; display.videoGravity = .resizeAspect
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls)); tap.numberOfTouchesRequired = 3
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { return nil }
    @objc private func toggleControls() { toggle?() }
    func show(_ pixel: CVPixelBuffer) {
        var format: CMVideoFormatDescription?, sample: CMSampleBuffer?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &format) == noErr, let format else { return }
        var time = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: format, sampleTiming: &time, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary], let first = attachments.first { first[kCMSampleAttachmentKey_DisplayImmediately] = true }
        if display.sampleBufferRenderer.status == .failed { display.sampleBufferRenderer.flush() }
        if display.sampleBufferRenderer.isReadyForMoreMediaData { display.sampleBufferRenderer.enqueue(sample) }
    }
}
