import Foundation
import CryptoKit

internal struct Ed25519Key {
    let privateKey: Curve25519.Signing.PrivateKey

    static func generate() -> Ed25519Key { Ed25519Key(privateKey: Curve25519.Signing.PrivateKey()) }

    static func fromRawSeed(_ raw: Data) throws -> Ed25519Key {
        guard raw.count == 32 else { throw DepliteError.invalidPrivateKey }
        do {
            let pk = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            return Ed25519Key(privateKey: pk)
        } catch {
            throw DepliteError.invalidPrivateKey
        }
    }

    var rawSeed: Data { privateKey.rawRepresentation }
    var rawPublicKey: Data { privateKey.publicKey.rawRepresentation }

    func sign(_ message: Data) throws -> Data {
        do { return try privateKey.signature(for: message) }
        catch { throw DepliteError.signing(reason: "\(error)") }
    }

    /// Ed25519 SPKI DER prefix (RFC 8410): 12 bytes + 32-byte raw key.
    func publicKeyPEM() -> String {
        let prefix: [UInt8] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00]
        var der = Data(prefix)
        der.append(rawPublicKey)
        return Self.wrapPEM(der: der, label: "PUBLIC KEY")
    }

    /// Extract raw 32-byte public key from an SPKI PEM. Returns nil on failure.
    static func rawPublicKeyFromPEM(_ pem: String) -> Data? {
        guard let der = stripPEM(pem, expectedLabel: "PUBLIC KEY") else { return nil }
        guard der.count == 44 else { return nil }
        let prefix: [UInt8] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00]
        guard Array(der.prefix(12)) == prefix else { return nil }
        return der.suffix(32)
    }

    static func verify(pem: String, message: Data, signature: Data) -> Bool {
        guard let raw = rawPublicKeyFromPEM(pem) else { return false }
        guard let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return pub.isValidSignature(signature, for: message)
    }

    private static func wrapPEM(der: Data, label: String) -> String {
        let base64 = der.base64EncodedString()
        var lines: [String] = []
        var i = base64.startIndex
        while i < base64.endIndex {
            let j = base64.index(i, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[i..<j]))
            i = j
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----\n"
    }

    private static func stripPEM(_ pem: String, expectedLabel: String) -> Data? {
        let begin = "-----BEGIN \(expectedLabel)-----"
        let end = "-----END \(expectedLabel)-----"
        guard let b = pem.range(of: begin), let e = pem.range(of: end) else { return nil }
        let body = pem[b.upperBound..<e.lowerBound]
        let cleaned = body.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Data(base64Encoded: cleaned)
    }
}
