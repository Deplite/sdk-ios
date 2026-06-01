import Foundation

internal enum Nonce {
    static func next() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.hexString
    }
}

internal extension Array where Element == UInt8 {
    var hexString: String {
        let alphabet: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
        var out = ""
        out.reserveCapacity(count * 2)
        for b in self {
            out.append(alphabet[Int(b >> 4)])
            out.append(alphabet[Int(b & 0x0f)])
        }
        return out
    }
}

internal extension Data {
    var hexString: String { Array(self).hexString }
}
