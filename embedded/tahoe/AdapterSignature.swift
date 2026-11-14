import Foundation
import CryptoKit

struct TahoeAdapterPayload: Codable {
    var version: Int
    var minimumHost: String
    var origin: String
    var script: String
}
struct TahoeSignedAdapter: Codable {
    var payload: TahoeAdapterPayload
    var signature: String
}
enum TahoeAdapterSignature {
    static func canonical(_ payload: TahoeAdapterPayload) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }
    static func verify(_ data: Data, publicKey: String, hostVersion: String) throws -> TahoeAdapterPayload {
        guard data.count <= 524_288, let key = Data(base64Encoded: publicKey), key.count == 32 else { throw failure("Configure the owner's 32-byte Ed25519 public key first.") }
        let signed = try JSONDecoder().decode(TahoeSignedAdapter.self, from: data), payload = signed.payload
        guard (1...1_000_000_000).contains(payload.version), payload.origin == "https://chatgpt.com", !payload.script.isEmpty,
              payload.script.utf8.count <= 262_144, compatible(payload.minimumHost, host: hostVersion),
              let signature = Data(base64Encoded: signed.signature), signature.count == 64 else { throw failure("This adapter is invalid or requires a newer SideOS IPA.") }
        let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: key)
        guard verifier.isValidSignature(signature, for: try canonical(payload)) else { throw failure("The adapter signature does not match the configured owner key.") }
        return payload
    }
    static func compatible(_ required: String, host: String) -> Bool {
        func version(_ value: String) -> [Int]? {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
            let numbers = parts.compactMap { Int($0) }; return numbers.count == 3 ? numbers : nil
        }
        guard let a = version(required), let b = version(host) else { return false }
        for index in 0..<3 { if a[index] != b[index] { return a[index] < b[index] } }
        return true
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "SideOS.Adapter", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
