import Foundation
import CryptoKit

@main struct AdapterSignatureTests {
    static func main() throws {
        let key = Curve25519.Signing.PrivateKey()
        var payload = TahoeAdapterPayload(version: 1, minimumHost: "3.1.0", origin: "https://chatgpt.com", script: "/* ⋯ */\nvoid 0;")
        let canonical = try TahoeAdapterSignature.canonical(payload)
        let expected = #"{"minimumHost":"3.1.0","origin":"https://chatgpt.com","script":"/* ⋯ */\nvoid 0;","version":1}"#
        precondition(String(decoding: canonical, as: UTF8.self) == expected, "The signing tool and host must share canonical JSON bytes")
        let signature = try key.signature(for: canonical).base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let data = try JSONEncoder().encode(TahoeSignedAdapter(payload: payload, signature: signature))
        let verified = try TahoeAdapterSignature.verify(data, publicKey: publicKey, hostVersion: "3.1.0")
        precondition(verified.version == 1)
        for version in ["3.0.9", "3.x.1.0", "3..1", "3.1", "-3.1.0"] {
            do { _ = try TahoeAdapterSignature.verify(data, publicKey: publicKey, hostVersion: version); preconditionFailure("Reject incompatible host") } catch { }
        }
        payload.script += "tampered"
        let tampered = try JSONEncoder().encode(TahoeSignedAdapter(payload: payload, signature: signature))
        do { _ = try TahoeAdapterSignature.verify(tampered, publicKey: publicKey, hostVersion: "3.1.0"); preconditionFailure("Reject modified payload") } catch { }
        do { _ = try TahoeAdapterSignature.verify(data, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString(), hostVersion: "3.1.0"); preconditionFailure("Reject wrong owner") } catch { }
        precondition(TahoeAdapterSignature.compatible("3.1.0", host: "3.2.0"))
        print("Signed adapter canonicalization, version policy, valid signature, tampering and wrong-key rejection passed")
    }
}
