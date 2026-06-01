import Foundation
import CryptoKit

internal enum CanonicalMessage {
    /// Empty-body SHA-256 hex.
    static let emptyBodySHA256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    static func build(timestamp: String, nonce: String, method: String, path: String, body: Data) -> Data {
        precondition(!path.contains("?"), "signing: path must not contain a query string: \(path)")
        let bodyHex = body.isEmpty ? emptyBodySHA256Hex : Data(SHA256.hash(data: body)).hexString
        let text = "\(timestamp)\n\(nonce)\n\(method.uppercased())\n\(path)\n\(bodyHex)"
        return Data(text.utf8)
    }
}
