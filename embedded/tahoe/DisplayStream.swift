import Foundation

/// Immutable after install; the small lock also fences setup against callbacks.
final class TahoeDisplayReceiverSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TahoeDisplayReceiver?
    func install(_ value: TahoeDisplayReceiver) { lock.lock(); self.value = value; lock.unlock() }
    func receive(_ packet: TahoeDisplayPacket) {
        lock.lock(); let value = value; lock.unlock(); value?.receive(packet)
    }
}

/// Negotiation and submission happen on the transport queue, not main. This
/// rejects a flooding peer before posting any UI tasks or retaining frame data.
final class TahoeDisplayReceiver: @unchecked Sendable {
    private let mode: TahoeDisplayMode
    private let decoder: TahoeDisplayDecoder
    private let accepted: @Sendable () -> Void
    private let failure: @Sendable (String) -> Void
    private var paired = false // transport queue only
    init(mode: TahoeDisplayMode, accepted: @escaping @Sendable () -> Void,
         output: @escaping @Sendable (TahoeDisplayPixel) -> Void, consumed: @escaping @Sendable (UInt64) -> Void,
         failure: @escaping @Sendable (String) -> Void) {
        self.mode = mode; self.accepted = accepted; self.failure = failure
        decoder = TahoeDisplayDecoder(mode: mode, output: output, consumed: consumed, failure: failure)
    }
    func receive(_ packet: TahoeDisplayPacket) {
        if packet.kind == 2 {
            guard paired else { failure("Video arrived before display negotiation."); return }
            decoder.decode(packet.data)
        } else {
            guard let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data),
                  (try? command.validate()) != nil, command.type == "accept", command.mode == mode, !paired else {
                failure("Unexpected display response. Update SideOS on both devices."); return
            }
            paired = true; accepted()
        }
    }
    func stop() { decoder.stop() }
}

/// Decoder ACKs do not wait for UI. Retain one replaceable pixel buffer rather
/// than enqueuing one main-thread task/image for every decoded frame.
final class TahoeDisplayPixelMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: TahoeDisplayPixel?
    private var queued = false
    private let deliver: @MainActor @Sendable (TahoeDisplayPixel) -> Void
    init(deliver: @escaping @MainActor @Sendable (TahoeDisplayPixel) -> Void) { self.deliver = deliver }
    func submit(_ pixel: TahoeDisplayPixel) {
        lock.lock(); latest = pixel
        if queued { lock.unlock(); return }
        queued = true; lock.unlock()
        DispatchQueue.main.async { [self] in
            lock.lock(); let image = latest; latest = nil; queued = false; lock.unlock()
            if let image { deliver(image) }
        }
    }
}
