import Foundation
import Network
import Security
import SwiftUI

struct TahoeDisplayPeer: Identifiable, Equatable, Sendable {
    static let service = "_sideos-screen._tcp"
    let name: String
    let endpoint: NWEndpoint
    var id: String { name }
    var label: String { "SideOS · " + name.suffix(6) }
    init?(_ endpoint: NWEndpoint) {
        guard case .service(let name, let type, let domain, _) = endpoint,
              type == Self.service, domain == "local.", name.hasPrefix("SideOS-"),
              UUID(uuidString: String(name.dropFirst(7))) != nil else { return nil }
        self.name = name; self.endpoint = endpoint
    }
}

@MainActor final class TahoeDisplayDiscovery: ObservableObject {
    @Published private(set) var peers: [TahoeDisplayPeer] = []
    private var browser: NWBrowser?
    private var token = UUID()
    func start() {
        stop(); let run = token
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]; parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: TahoeDisplayPeer.service, domain: "local."), using: parameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let values = results.compactMap { TahoeDisplayPeer($0.endpoint) }
            Task { @MainActor in
                guard let self, self.token == run else { return }
                self.peers = Array(Dictionary(values.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }).values).sorted { $0.name < $1.name }
            }
        }
        browser.start(queue: .global(qos: .utility))
    }
    func stop() { token = UUID(); browser?.cancel(); browser = nil; peers = [] }
    deinit { browser?.cancel() }
}

enum TahoeDisplayConnectionState: Sendable { case waiting, connected, failed }

/// Network state is confined to one serial queue. Callbacks are immutable and
/// installed before starting. The receiver can never issue application input.
final class TahoeDisplayTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SideOS.display.network", qos: .userInitiated)
    private let status: @Sendable (String, TahoeDisplayConnectionState) -> Void
    private let packet: @Sendable (TahoeDisplayPacket) -> Void
    private let listening: @Sendable (UInt16) -> Void
    private var listener: NWListener?
    private var connection: NWConnection?
    private var parser = TahoeDisplayParser()
    private var watchdog: DispatchSourceTimer?
    private var generation = UUID()
    private var connected = false
    private var pending: [ObjectIdentifier: NWConnection] = [:]
    private var handshakeSecond = 0
    private var handshakesInSecond = 0
    private var lastReceive = ProcessInfo.processInfo.systemUptime
    private var controlsInSecond = 0
    private var controlSecond = 0
    private var sends = 0
    private let handshakeTimeout: TimeInterval

    init(handshakeTimeout: TimeInterval = 12,
         status: @escaping @Sendable (String, TahoeDisplayConnectionState) -> Void,
         packet: @escaping @Sendable (TahoeDisplayPacket) -> Void,
         listening: @escaping @Sendable (UInt16) -> Void = { _ in }) {
        self.status = status; self.packet = packet; self.listening = listening
        self.handshakeTimeout = min(12, max(0.5, handshakeTimeout))
    }
    static func newKey() throws -> String {
        var data = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, data.count, &data) == errSecSuccess else { throw TahoeDisplayError.invalid("Unable to generate a pairing key.") }
        return Data(data).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func parameters(_ key: String) throws -> NWParameters {
        guard key.utf8.count == 43, key.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }),
              let bytes = Data(base64Encoded: key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="), bytes.count == 32 else { throw TahoeDisplayError.invalid("Enter the host's complete 43-character pairing key.") }
        let canonical = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard canonical == key else { throw TahoeDisplayError.invalid("The pairing key is not valid. Copy it again from the host.") }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
        sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
        let secret = bytes.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("SideOSDisplay-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, secret as __DispatchData, identity as __DispatchData)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.connectionTimeout = 10
        let result = NWParameters(tls: tls, tcp: tcp)
        result.prohibitedInterfaceTypes = [.cellular]; result.includePeerToPeer = false
        return result
    }
    func host(key: String, name: String, advertise: Bool = true) {
        queue.async { [self] in
            do {
                let listener = try NWListener(using: Self.parameters(key), on: .any)
                self.listener = listener
                if advertise { listener.service = NWListener.Service(name: name, type: TahoeDisplayPeer.service, domain: "local.") }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, let listener, self.listener === listener else { return }
                    if case .ready = state, let port = listener.port { self.listening(port.rawValue); self.status("Waiting for a paired display.", .waiting) }
                    if case .failed = state { self.fail("Cannot start the display link. Check Local Network permission.") }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    self.acceptIncoming(connection)
                }
                listener.start(queue: queue)
            } catch { fail(error.localizedDescription) }
        }
    }
    func connect(endpoint: NWEndpoint?, host: String, port: UInt16, key: String) {
        queue.async { [self] in
            do {
                let target: NWEndpoint
                if let endpoint {
                    guard TahoeDisplayPeer(endpoint) != nil else { throw TahoeDisplayError.invalid("Invalid nearby display host.") }
                    target = endpoint
                } else {
                    guard port > 0, let ip = IPv4Address(host) else { throw TahoeDisplayError.invalid("Enter a private IPv4 address and valid port.") }
                    let bytes = [UInt8](ip.rawValue)
                    guard bytes[0] == 10 || bytes[0] == 127 || (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254) else { throw TahoeDisplayError.invalid("Use an address on your own local network.") }
                    target = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
                }
                attach(NWConnection(to: target, using: try Self.parameters(key)))
            } catch { fail(error.localizedDescription) }
        }
    }
    private static func peerHost(_ connection: NWConnection) -> NWEndpoint.Host? {
        if case .hostPort(let host, _) = connection.endpoint { return host }; return nil
    }
    private func acceptIncoming(_ incoming: NWConnection) {
        let second = Int(ProcessInfo.processInfo.systemUptime)
        if second != handshakeSecond { handshakeSecond = second; handshakesInSecond = 0 }
        let sameHost = pending.values.filter { Self.peerHost($0) == Self.peerHost(incoming) }.count
        guard connection == nil, pending.count < 4, sameHost < 2, handshakesInSecond < 8 else { incoming.cancel(); return }
        handshakesInSecond += 1
        let id = ObjectIdentifier(incoming), run = generation
        pending[id] = incoming
        incoming.stateUpdateHandler = { [weak self, weak incoming] state in
            guard let self, let incoming, self.generation == run, self.pending[id] === incoming else { return }
            switch state {
            case .ready:
                self.pending.removeValue(forKey: id)
                guard self.connection == nil else { incoming.cancel(); return }
                self.connection = incoming
                for other in self.pending.values { other.stateUpdateHandler = nil; other.cancel() }
                self.pending.removeAll()
                self.activate(incoming, run: run)
            case .failed, .cancelled:
                self.rejectPending(incoming, message: "Pairing failed. Waiting for a viewer with the correct key.")
            default: break
            }
        }
        incoming.start(queue: queue)
        queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self, weak incoming] in
            guard let self, let incoming, self.generation == run, self.pending[id] === incoming else { return }
            self.rejectPending(incoming, message: "Pairing took too long. Still waiting for a paired viewer.")
        }
    }
    private func attach(_ connection: NWConnection) {
        self.connection = connection; let run = generation
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection, self.generation == run else { return }
            if case .ready = state { self.activate(connection, run: run) }
            if case .failed = state { self.fail("Display connection failed. Check the pairing key and local network.") }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self, weak connection] in
            guard let self, let connection, self.generation == run, self.connection === connection, !self.connected else { return }
            self.fail("Pairing timed out. Check the key and Local Network permission.")
        }
    }
    private func activate(_ connection: NWConnection, run: UUID) {
        connected = true; lastReceive = ProcessInfo.processInfo.systemUptime
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection, self.generation == run else { return }
            if case .failed = state { self.fail("Display connection failed. Check the local network.") }
        }
        status("Encrypted display connected.", .connected); receive(connection, run: run)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastReceive > 12 { self.fail("Display disconnected or timed out.") }
            else { self.send(TahoeDisplayControl(type: "ping")) }
        }
        watchdog = timer; timer.resume()
    }
    private func rejectPending(_ incoming: NWConnection, message: String) {
        guard pending.removeValue(forKey: ObjectIdentifier(incoming)) != nil else { return }
        incoming.stateUpdateHandler = nil; incoming.cancel()
        // Authentication failure owns no session: keep listening and preserve
        // other pending viewers, the current key and desktop state.
        if !connected { status(message, .waiting) }
    }
    private func receive(_ connection: NWConnection, run: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.connection === connection, self.generation == run else { return }
            do {
                if let data, !data.isEmpty {
                    self.lastReceive = ProcessInfo.processInfo.systemUptime
                    for value in try self.parser.append(data) {
                        if value.kind == 1 {
                            guard value.data.count <= 65_536 else { throw TahoeDisplayError.invalid("Control packet too large.") }
                            let second = Int(self.lastReceive)
                            if self.controlSecond != second { self.controlSecond = second; self.controlsInSecond = 0 }
                            self.controlsInSecond += 1
                            guard self.controlsInSecond <= 100 else { throw TahoeDisplayError.invalid("Display control rate exceeded.") }
                            let command = try JSONDecoder().decode(TahoeDisplayControl.self, from: value.data); try command.validate()
                            if command.type == "ping" { self.send(TahoeDisplayControl(type: "pong")); continue }
                            if command.type == "pong" { continue }
                            if command.type == "bye" { self.fail("The other device stopped the display."); return }
                        }
                        self.packet(value)
                    }
                }
                if complete || error != nil { self.fail("The display connection ended.") }
                else { self.receive(connection, run: run) }
            } catch { self.fail(error.localizedDescription) }
        }
    }
    func send(_ command: TahoeDisplayControl) {
        guard (try? command.validate()) != nil, let data = try? JSONEncoder().encode(command) else { return }
        send(TahoeDisplayPacket(kind: 1, data: data), completion: { _ in })
    }
    func send(_ value: TahoeDisplayPacket, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard connected, let connection, sends < 64, let data = try? value.encoded() else { completion(false); return }
            sends += 1; let run = generation
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == run else { completion(false); return }
                self.sends -= 1; completion(error == nil)
                if error != nil { self.fail("Sending the display failed.") }
            })
        }
    }
    private func fail(_ message: String) { stopNow(); status(message, .failed) }
    private func stopNow() {
        generation = UUID(); connected = false
        watchdog?.cancel(); watchdog = nil
        for incoming in pending.values { incoming.stateUpdateHandler = nil; incoming.cancel() }
        pending.removeAll(); handshakesInSecond = 0
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        listener?.newConnectionHandler = nil; listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        parser = TahoeDisplayParser(); sends = 0
    }
    func stop() { queue.async { [self] in stopNow() } }
}
