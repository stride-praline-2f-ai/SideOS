import Foundation
import VideoToolbox
import CoreVideo

struct TahoeDisplayPixel: @unchecked Sendable { let buffer: CVPixelBuffer }

/// VideoToolbox owns hardware compression. UIKit capture stays on main; all
/// compression, parameter extraction and network completion work stays here.
final class TahoeDisplayEncoder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SideOS.display.encoder", qos: .userInitiated)
    private var session: VTCompressionSession?
    private var stopped = false
    private let mode: TahoeDisplayMode
    private let output: @Sendable (Data, UInt64) -> Void
    private let failure: @Sendable (String) -> Void
    private let dropped: (@Sendable (UInt64) -> Void)?
    let pool: CVPixelBufferPool
    init(mode: TahoeDisplayMode, output: @escaping @Sendable (Data, UInt64) -> Void, failure: @escaping @Sendable (String) -> Void,
         dropped: (@Sendable (UInt64) -> Void)? = nil) throws {
        self.mode = mode; self.output = output; self.failure = failure; self.dropped = dropped
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: mode.codedWidth, kCVPixelBufferHeightKey as String: mode.codedHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:], kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool else { throw TahoeDisplayError.invalid("Unable to allocate the display buffer pool.") }
        self.pool = pool
        let specification = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true] as CFDictionary
        let result = VTCompressionSessionCreate(allocator: nil, width: Int32(mode.codedWidth), height: Int32(mode.codedHeight), codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification, imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil,
            outputCallback: { context, reference, status, flags, sample in
                guard let context, let reference else { return }
                let sequence = Unmanaged<NSNumber>.fromOpaque(reference).takeRetainedValue().uint64Value
                let owner = Unmanaged<TahoeDisplayEncoder>.fromOpaque(context).takeUnretainedValue()
                owner.queue.async {
                    if flags.contains(.frameDropped), status == noErr {
                        if let dropped = owner.dropped { dropped(sequence) } else { owner.failure("The hardware encoder dropped the test frame.") }
                    } else { owner.completed(sample, status: status, sequence: sequence) }
                }
            }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        guard result == noErr, let session else { throw TahoeDisplayError.invalid("A hardware H.264 encoder is unavailable for this display size (\(result)).") }
        for (key, value) in [(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue as CFTypeRef),
                             (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse as CFTypeRef),
                             (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel as CFTypeRef),
                             (kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: TahoeDisplayTiming.framesPerSecond) as CFTypeRef),
                             (kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: TahoeDisplayTiming.framesPerSecond * 2) as CFTypeRef),
                             (kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: min(24_000_000, max(4_000_000, mode.width * mode.height * 4))) as CFTypeRef)] {
            let status = VTSessionSetProperty(session, key: key, value: value)
            guard status == noErr else { throw TahoeDisplayError.invalid("The hardware encoder rejected a required display setting (\(status)).") }
        }
        guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else { throw TahoeDisplayError.invalid("The display encoder could not prepare.") }
    }
    func encode(_ pixel: TahoeDisplayPixel, sequence: UInt64) {
        queue.async { [self] in
            guard !stopped, let session else { return }
            let reference = Unmanaged.passRetained(NSNumber(value: sequence)).toOpaque()
            let result = VTCompressionSessionEncodeFrame(session, imageBuffer: pixel.buffer,
                presentationTimeStamp: CMTime(value: Int64(sequence), timescale: Int32(TahoeDisplayTiming.framesPerSecond)), duration: CMTime(value: 1, timescale: Int32(TahoeDisplayTiming.framesPerSecond)), frameProperties: nil,
                sourceFrameRefcon: reference, infoFlagsOut: nil)
            if result != noErr { Unmanaged<NSNumber>.fromOpaque(reference).release(); failure("The hardware display encoder failed (\(result)).") }
        }
    }
    private func completed(_ sample: CMSampleBuffer?, status: OSStatus, sequence: UInt64) {
        guard !stopped else { return }
        do {
            guard status == noErr, let sample, let format = CMSampleBufferGetFormatDescription(sample), let block = CMSampleBufferGetDataBuffer(sample) else { throw TahoeDisplayError.invalid("The display encoder produced no frame (\(status)).") }
            var sets: [Data] = []
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?, count = 0
                let result = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &count, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                guard result == noErr, let pointer, count > 0, count <= 16_384 else { throw TahoeDisplayError.invalid("Invalid encoder configuration.") }
                sets.append(Data(bytes: pointer, count: count))
            }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0, length < TahoeDisplayPacket.limit - 65_536 else { throw TahoeDisplayError.invalid("Encoded display frame is too large.") }
            var bytes = Data(count: length)
            let copied = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            guard copied == noErr else { throw TahoeDisplayError.invalid("Cannot copy the encoded display frame.") }
            output(try TahoeDisplayFrame(width: mode.codedWidth, height: mode.codedHeight, sequence: sequence, parameters: sets).packet(bytes), sequence)
        } catch { failure(error.localizedDescription) }
    }
    func stop() {
        queue.async { [self] in
            stopped = true
            if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(session); self.session = nil }
        }
    }
    deinit { if let session { VTCompressionSessionInvalidate(session) } }
}

/// A bounded serial decoder. ACKs follow actual decode completion, independently
/// of presentation. A reconnect has a new decoder, queue and sequence history.
final class TahoeDisplayDecoder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SideOS.display.decoder", qos: .userInitiated)
    private let slots = DispatchSemaphore(value: 2)
    private let lock = NSLock()
    private var stopped = false
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var sets: [Data] = []
    private var sequence: UInt64 = 0
    private var outputStatus: OSStatus = noErr
    private let mode: TahoeDisplayMode
    private let output: @Sendable (TahoeDisplayPixel) -> Void
    private let consumed: @Sendable (UInt64) -> Void
    private let failure: @Sendable (String) -> Void
    init(mode: TahoeDisplayMode, output: @escaping @Sendable (TahoeDisplayPixel) -> Void,
         consumed: @escaping @Sendable (UInt64) -> Void, failure: @escaping @Sendable (String) -> Void) {
        self.mode = mode; self.output = output; self.consumed = consumed; self.failure = failure
    }
    private var active: Bool { lock.lock(); defer { lock.unlock() }; return !stopped }
    func decode(_ data: Data) {
        guard active else { return }
        guard slots.wait(timeout: .now()) == .success else { stop(); failure("The peer exceeded the two-frame decoder window."); return }
        queue.async { [self] in
            var released = false
            defer { if !released { slots.signal() } }
            guard active else { return }
            do {
                let (header, bytes) = try TahoeDisplayFrame.unpack(data, mode: mode)
                guard header.sequence > sequence else { throw TahoeDisplayError.invalid("Stale display frame; reconnect.") }
                sequence = header.sequence
                if sets != header.parameters {
                    if let session { VTDecompressionSessionInvalidate(session); self.session = nil }
                    sets = header.parameters
                    let owners = sets.map { $0 as NSData }
                    var pointers = owners.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }, lengths = owners.map(\.length)
                    var description: CMFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: &pointers, parameterSetSizes: &lengths, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                    guard status == noErr, let description else { throw TahoeDisplayError.invalid("Invalid H.264 display configuration.") }
                    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                    guard dimensions.width == mode.codedWidth, dimensions.height == mode.codedHeight else { throw TahoeDisplayError.invalid("Codec size differs from the paired display.") }
                    format = description
                    var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { context, _, status, _, image, _, _ in
                        guard let context else { return }
                        let owner = Unmanaged<TahoeDisplayDecoder>.fromOpaque(context).takeUnretainedValue()
                        owner.outputStatus = status
                        if status == noErr, let image { owner.deliver(image) }
                    }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
                    let specification = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String: true] as CFDictionary
                    let attributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                      kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
                    guard VTDecompressionSessionCreate(allocator: nil, formatDescription: description, decoderSpecification: specification,
                        imageBufferAttributes: attributes, outputCallback: &callback, decompressionSessionOut: &session) == noErr else {
                        throw TahoeDisplayError.invalid("A hardware display decoder is unavailable.")
                    }
                }
                guard let session, let format else { throw TahoeDisplayError.invalid("The display decoder is not configured.") }
                var block: CMBlockBuffer?
                guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
                    customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block) == noErr, let block else {
                    throw TahoeDisplayError.invalid("Unable to allocate a decoder buffer.")
                }
                let copied = bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count) }
                var sample: CMSampleBuffer?, size = bytes.count
                guard copied == noErr, CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                    sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else {
                    throw TahoeDisplayError.invalid("Invalid decoder sample.")
                }
                outputStatus = noErr
                let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], frameRefcon: nil, infoFlagsOut: nil)
                VTDecompressionSessionWaitForAsynchronousFrames(session)
                guard status == noErr, outputStatus == noErr else { throw TahoeDisplayError.invalid("Hardware display decoding failed.") }
                slots.signal(); released = true
                if active { consumed(header.sequence) }
            } catch { stop(); failure(error.localizedDescription) }
        }
    }
    private func deliver(_ image: CVPixelBuffer) {
        guard active else { return }
        if mode.width != mode.codedWidth || mode.height != mode.codedHeight {
            let aperture: [String: Any] = [kCVImageBufferCleanApertureWidthKey as String: mode.width,
                kCVImageBufferCleanApertureHeightKey as String: mode.height,
                kCVImageBufferCleanApertureHorizontalOffsetKey as String: Double(mode.width - mode.codedWidth) / 2,
                kCVImageBufferCleanApertureVerticalOffsetKey as String: Double(mode.height - mode.codedHeight) / 2]
            CVBufferSetAttachment(image, kCVImageBufferCleanApertureKey, aperture as CFDictionary, .shouldPropagate)
        }
        output(TahoeDisplayPixel(buffer: image))
    }
    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        queue.async { [self] in if let session { VTDecompressionSessionWaitForAsynchronousFrames(session); VTDecompressionSessionInvalidate(session); self.session = nil } }
    }
    deinit { if let session { VTDecompressionSessionInvalidate(session) } }
}
