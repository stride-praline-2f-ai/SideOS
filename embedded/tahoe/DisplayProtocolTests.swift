import Foundation

@main struct DisplayProtocolTests {
    static func rejects(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Invalid peer data was accepted") } catch { }
    }
    static func main() throws {
        let captureTime = Duration.milliseconds(4)
        precondition(captureTime + TahoeDisplayTiming.delay(afterCapture: captureTime) == TahoeDisplayTiming.frameInterval,
                     "Capture time must count toward the frame period")
        precondition(TahoeDisplayTiming.delay(afterCapture: TahoeDisplayTiming.frameInterval * 2) == .milliseconds(1),
                     "Slow captures must yield, without catch-up bursts or a tight main-thread loop")
        let mode = TahoeDisplayMode(width: 2853, height: 2007, pointsWide: 1284, pointsHigh: 903)
        try mode.validate()
        precondition(mode.codedWidth == 2854 && mode.codedHeight == 2008)
        for bad in [TahoeDisplayMode(width: .max, height: 2007, pointsWide: 1284, pointsHigh: 903),
                    TahoeDisplayMode(width: 1280, height: 720, pointsWide: 640, pointsHigh: 900),
                    TahoeDisplayMode(width: 4096, height: 4096, pointsWide: 2048, pointsHigh: 2048)] { rejects { try bad.validate() } }
        for type in ["key", "button", "move", "scroll", "launch", "open", "clipboard", "file"] {
            rejects { try TahoeDisplayControl(type: type).validate() }
        }
        var wrong = TahoeDisplayControl(type: "offer", mode: mode); wrong.version = 999
        rejects { try wrong.validate() }
        rejects { try TahoeDisplayControl(type: "accept").validate() }
        rejects { try TahoeDisplayControl(type: "ack", sequence: 0).validate() }
        let one = try TahoeDisplayPacket(kind: 1, data: JSONEncoder().encode(TahoeDisplayControl(type: "offer", mode: mode))).encoded()
        let two = try TahoeDisplayPacket(kind: 2, data: Data(repeating: 0x19, count: 131_111)).encoded()
        var wire = one; wire.append(two)
        for split in [1, 3, 4, 5, 127, 4096, 65_536] {
            var parser = TahoeDisplayParser(), output: [TahoeDisplayPacket] = [], cursor = 0
            while cursor < wire.count { let end = min(wire.count, cursor + split); output += try parser.append(wire.subdata(in: cursor..<end)); cursor = end }
            precondition(output.count == 2 && output[0].kind == 1 && output[1].data.count == 131_111)
        }
        rejects { var parser = TahoeDisplayParser(); _ = try parser.append(Data([0xff, 0xff, 0xff, 0xff])) }
        rejects { var parser = TahoeDisplayParser(); _ = try parser.append(Data([0, 0, 0, 2, 3, 1])) }
        rejects { var parser = TahoeDisplayParser(); _ = try parser.append(Data(repeating: 0, count: 65_537)) }
        let header = TahoeDisplayFrame(width: mode.codedWidth, height: mode.codedHeight, sequence: 1, parameters: [Data([1, 2]), Data([3, 4])])
        let packed = try header.packet(Data([5, 6, 7]))
        let (decoded, sample) = try TahoeDisplayFrame.unpack(packed, mode: mode)
        precondition(decoded.sequence == 1 && sample == Data([5, 6, 7]))
        rejects { _ = try TahoeDisplayFrame.unpack(Data([0, 2, 0, 0, 0]), mode: mode) }
        rejects { _ = try TahoeDisplayFrame.unpack(TahoeDisplayFrame(width: 2853, height: 2007, sequence: 1, parameters: header.parameters).packet(Data([1])), mode: mode) }
        let credits = TahoeDisplayCredits()
        precondition(credits.begin(1) && credits.begin(2) && !credits.begin(3))
        credits.consumed(99); precondition(!credits.begin(3))
        credits.consumed(1); credits.consumed(1); precondition(!credits.begin(3))
        credits.sent(1, okay: true); precondition(credits.begin(3))
        credits.sent(2, okay: true); precondition(!credits.begin(4))
        credits.consumed(2); precondition(credits.begin(4))
        credits.sent(3, okay: false); precondition(credits.begin(5))
        credits.reset(); precondition(credits.begin(1))
        var state = TahoeWindowState(); state.setCanvas(CGSize(width: 1024, height: 768))
        let localCanvas = state.canvas
        let ids = TahoeWindowKind.allCases.map { state.open($0, title: $0.rawValue) }
        let frames = Dictionary(uniqueKeysWithValues: state.windows.map { ($0.id, $0.frame) })
        state.moveToWirelessDisplay(ids[0], enabled: true)
        precondition(state.windows.first?.onWirelessDisplay != true, "No transfer without a negotiated display")
        state.setWirelessCanvas(CGSize(width: 1284, height: 903))
        for id in ids {
            state.moveToWirelessDisplay(id, enabled: true)
            let window = state.windows.first { $0.id == id }!
            precondition(window.onWirelessDisplay == true && state.wirelessActiveID == id && state.isVisible(window))
            precondition(state.displayFrame(window) == CGRect(x: 0, y: 0, width: 1284, height: 903))
            precondition(window.frame == frames[id], "Transfers must retain the main-display restore frame")
        }
        state.toggleFullscreen(ids.last!)
        precondition(state.fullscreenID == nil, "A projected app must never own primary fullscreen")
        precondition(state.canvas == localCanvas && state.windows.count == ids.count)
        let last = ids.last!; state.minimize(last)
        precondition(state.wirelessActiveID != last)
        state.focus(last); precondition(state.wirelessActiveID == last)
        state.close(last); precondition(state.wirelessActiveID != last)
        var restored = TahoeWindowState()
        restored.restore(state.windows, active: state.activeID, space: 0, spaces: 3)
        precondition(restored.windows.allSatisfy { $0.onWirelessDisplay != true })
        state.setWirelessCanvas(nil)
        precondition(state.wirelessCanvas == nil && state.wirelessActiveID == nil && state.windows.allSatisfy { $0.onWirelessDisplay != true })
        for window in state.windows { precondition(window.frame == frames[window.id]) }
        print("Wireless display: hostile framing/metadata, no-input protocol, native odd-size geometry, reordered ACKs, bounded credits, all app-kind placements and disconnect/restore recovery passed.")
    }
}
