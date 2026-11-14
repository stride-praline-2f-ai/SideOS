import Foundation
import VideoToolbox

private final class DisplayVideoResult: @unchecked Sendable {
    let lock = NSLock(), done = DispatchSemaphore(value: 0)
    var error: String?
    var pixels = 0
    var decoder: TahoeDisplayDecoder?
    func fail(_ message: String) { lock.lock(); error = message; lock.unlock(); done.signal() }
    func receive(_ data: Data) { lock.lock(); let decoder = decoder; lock.unlock(); decoder?.decode(data) }
    func pixel(_ value: TahoeDisplayPixel, mode: TahoeDisplayMode) {
        let buffer = value.buffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetWidth(buffer) == mode.codedWidth, CVPixelBufferGetHeight(buffer) == mode.codedHeight,
              let base = CVPixelBufferGetBaseAddress(buffer) else { fail("Decoded native dimensions differ"); return }
        let pixel = base.advanced(by: CVPixelBufferGetBytesPerRow(buffer) * 20 + 20 * 4).assumingMemoryBound(to: UInt8.self)
        guard abs(Int(pixel[0]) - 40) < 35, abs(Int(pixel[1]) - 120) < 35, abs(Int(pixel[2]) - 200) < 35 else { fail("Decoded colour does not match the captured BGRA surface"); return }
        let clean = CVImageBufferGetCleanRect(buffer)
        guard abs(clean.width - CGFloat(mode.width)) < 0.1, abs(clean.height - CGFloat(mode.height)) < 0.1 else { fail("Odd-size native image crop was lost"); return }
        lock.lock(); pixels += 1; lock.unlock()
    }
}

@main struct DisplayVideoTests {
    static func main() throws {
        let mode = TahoeDisplayMode(width: 641, height: 481, pointsWide: 641, pointsHigh: 481)
        try mode.validate()
        let result = DisplayVideoResult()
        let decoder = TahoeDisplayDecoder(mode: mode, output: { result.pixel($0, mode: mode) },
            consumed: { sequence in if sequence == 1 { result.done.signal() } else { result.fail("Wrong frame acknowledged") } },
            failure: { result.fail($0) })
        result.decoder = decoder
        let encoder = try TahoeDisplayEncoder(mode: mode, output: { data, sequence in
            if sequence == 1 { result.receive(data) } else { result.fail("Wrong frame encoded") }
        }, failure: { result.fail($0) })
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, encoder.pool, &buffer) == kCVReturnSuccess, let buffer else { fatalError("No capture buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<mode.codedHeight {
            for x in 0..<mode.codedWidth {
                let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                base[offset] = 40; base[offset + 1] = 120; base[offset + 2] = 200; base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        encoder.encode(TahoeDisplayPixel(buffer: buffer), sequence: 1)
        guard result.done.wait(timeout: .now() + 15) == .success else { fatalError("Native hardware display encode/decode timed out") }
        result.lock.lock(); let error = result.error, pixels = result.pixels; result.lock.unlock()
        encoder.stop(); decoder.stop()
        if let error { fatalError(error) }
        precondition(pixels == 1)
        print("Native hardware H.264 capture-buffer → encoded framing → decoder → BGRA pixels, odd-size clean aperture and decode ACK passed. This is a Mac codec test, not an iOS hosted-scene capture test.")
    }
}
