import Foundation
import Network

private final class DisplayNetworkResult: @unchecked Sendable {
    let lock = NSLock()
    let bound = DispatchSemaphore(value: 0), accepted = DispatchSemaphore(value: 0), rejected = DispatchSemaphore(value: 0)
    let pendingReleased = DispatchSemaphore(value: 0)
    var port: UInt16 = 0
    var server: TahoeDisplayTransport?
    var client: TahoeDisplayTransport?
    var authenticated = false
    var invalidDelivered = false
    func listen(_ port: UInt16) { lock.lock(); self.port = port; lock.unlock(); bound.signal() }
    func sendAccept(_ mode: TahoeDisplayMode) { lock.lock(); let server = server; lock.unlock(); server?.send(TahoeDisplayControl(type: "accept", mode: mode)) }
    func sendOffer(_ mode: TahoeDisplayMode) { lock.lock(); let client = client; authenticated = true; lock.unlock(); client?.send(TahoeDisplayControl(type: "offer", mode: mode)) }
}

@main struct DisplayTransportTests {
    static func main() throws {
        let key = try TahoeDisplayTransport.newKey()
        let mode = TahoeDisplayMode(width: 640, height: 480, pointsWide: 640, pointsHigh: 480)
        let result = DisplayNetworkResult()
        let server = TahoeDisplayTransport(status: { _, state in if state == .failed { result.rejected.signal() } }, packet: { packet in
            guard let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data) else { return }
            if command.type == "offer", command.mode == mode { result.sendAccept(mode) }
            else { result.lock.lock(); result.invalidDelivered = true; result.lock.unlock() }
        }, listening: { result.listen($0) })
        result.server = server
        server.host(key: key, name: "SideOS-" + UUID().uuidString, advertise: false)
        precondition(result.bound.wait(timeout: .now() + 10) == .success, "No local TLS listener")
        let client = TahoeDisplayTransport(status: { _, state in if state == .connected { result.sendOffer(mode) } }, packet: { packet in
            if let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data), command.type == "accept", command.mode == mode { result.accepted.signal() }
        })
        result.client = client
        client.connect(endpoint: nil, host: "127.0.0.1", port: result.port, key: key)
        precondition(result.accepted.wait(timeout: .now() + 15) == .success, "TLS-PSK display negotiation failed")
        // Bypass the sending API's own validation to exercise peer rejection.
        client.send(TahoeDisplayPacket(kind: 1, data: Data(#"{"version":1,"type":"key","code":4,"down":true}"#.utf8)), completion: { _ in })
        precondition(result.rejected.wait(timeout: .now() + 10) == .success, "An input command did not terminate the display-only connection")
        result.lock.lock(); let invalid = result.invalidDelivered; result.lock.unlock()
        precondition(!invalid)
        server.stop(); client.stop()

        let bad = DisplayNetworkResult()
        let second = TahoeDisplayTransport(status: { _, _ in }, packet: { _ in bad.lock.lock(); bad.invalidDelivered = true; bad.lock.unlock() }, listening: { bad.listen($0) })
        second.host(key: key, name: "SideOS-" + UUID().uuidString, advertise: false)
        precondition(bad.bound.wait(timeout: .now() + 10) == .success)
        let wrong = TahoeDisplayTransport(status: { _, state in
            if state == .connected { bad.lock.lock(); bad.authenticated = true; bad.lock.unlock() }
            if state == .failed { bad.rejected.signal() }
        }, packet: { _ in })
        wrong.connect(endpoint: nil, host: "127.0.0.1", port: bad.port, key: try TahoeDisplayTransport.newKey())
        precondition(bad.rejected.wait(timeout: .now() + 15) == .success, "Wrong key did not fail TLS pairing")
        bad.lock.lock(); let authenticated = bad.authenticated, delivered = bad.invalidDelivered; bad.lock.unlock()
        precondition(!authenticated && !delivered, "Unauthenticated peer reached display traffic")
        second.stop(); wrong.stop()

        let stalled = DisplayNetworkResult()
        let recoverable = TahoeDisplayTransport(handshakeTimeout: 2, status: { text, state in
            if state == .waiting && text.hasPrefix("Pairing took too long") { stalled.pendingReleased.signal() }
            if state == .failed { stalled.rejected.signal() }
        }, packet: { packet in
            if let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data), command.type == "offer" { stalled.sendAccept(mode) }
        }, listening: { stalled.listen($0) })
        stalled.server = recoverable
        recoverable.host(key: key, name: "SideOS-" + UUID().uuidString, advertise: false)
        precondition(stalled.bound.wait(timeout: .now() + 10) == .success)
        let raw = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: stalled.port)!, using: .tcp)
        raw.start(queue: .global())
        precondition(stalled.pendingReleased.wait(timeout: .now() + 10) == .success, "Stalled unauthenticated handshake did not release its slot")
        raw.cancel()
        let valid = TahoeDisplayTransport(status: { _, state in if state == .connected { stalled.sendOffer(mode) } }, packet: { packet in
            if let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data), command.type == "accept" { stalled.accepted.signal() }
        })
        stalled.client = valid
        valid.connect(endpoint: nil, host: "127.0.0.1", port: stalled.port, key: key)
        precondition(stalled.accepted.wait(timeout: .now() + 10) == .success, "A valid viewer could not pair on the original listener after a stalled handshake")
        precondition(stalled.rejected.wait(timeout: .now()) == .timedOut, "An unauthenticated timeout shut down hosting")
        valid.stop(); recoverable.stop()
        let concurrent = DisplayNetworkResult()
        let pooled = TahoeDisplayTransport(status: { _, _ in }, packet: { packet in
            if let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data), command.type == "offer" { concurrent.sendAccept(mode) }
        }, listening: { concurrent.listen($0) })
        concurrent.server = pooled
        pooled.host(key: key, name: "SideOS-" + UUID().uuidString, advertise: false)
        precondition(concurrent.bound.wait(timeout: .now() + 10) == .success)
        let tcpReady = DispatchSemaphore(value: 0)
        let blocker = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: concurrent.port)!, using: .tcp)
        blocker.stateUpdateHandler = { state in if case .ready = state { tcpReady.signal() } }
        blocker.start(queue: .global())
        precondition(tcpReady.wait(timeout: .now() + 5) == .success)
        let legitimate = TahoeDisplayTransport(status: { _, state in if state == .connected { concurrent.sendOffer(mode) } }, packet: { packet in
            if let command = try? JSONDecoder().decode(TahoeDisplayControl.self, from: packet.data), command.type == "accept" { concurrent.accepted.signal() }
        })
        concurrent.client = legitimate
        legitimate.connect(endpoint: nil, host: "127.0.0.1", port: concurrent.port, key: key)
        precondition(concurrent.accepted.wait(timeout: .now() + 8) == .success, "An unauthenticated stalled peer monopolized pairing before its deadline")
        blocker.cancel(); legitimate.stop(); pooled.stop()
        print("Native Network.framework TLS-PSK pairing, wrong-key refusal and inbound remote-input rejection passed over loopback. This is not a physical Wi-Fi/device test.")
    }
}
