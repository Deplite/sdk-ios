import Foundation
import CryptoKit

/// Verifier-side simulation of the Deplite backend. Crypto and canonical-message
/// reconstruction are implemented independently of the SDK internals so the
/// tests check both ends of the protocol rather than the SDK against itself.
final class TestDepliteServer: @unchecked Sendable {
    static let installCode = "ic-e2e-install-code"
    static let agentId = "agent-e2e-1"
    static let organizationId = "org-e2e-1"

    let serverKey = Curve25519.Signing.PrivateKey()
    var baseURL: URL { http.baseURL }

    var sseFrames: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _sseFrames }
        set { lock.lock(); defer { lock.unlock() }; _sseFrames = newValue }
    }
    var desiredResponseBody: String {
        get { lock.lock(); defer { lock.unlock() }; return _desiredResponseBody }
        set { lock.lock(); defer { lock.unlock() }; _desiredResponseBody = newValue }
    }
    var verifiedCalls: [String] { lock.lock(); defer { lock.unlock() }; return _verifiedCalls }
    var enrollRequestBody: [String: Any] { lock.lock(); defer { lock.unlock() }; return _enrollRequestBody }
    var deployReportBody: [String: Any] { lock.lock(); defer { lock.unlock() }; return _deployReportBody }
    var jobLogsBody: [String: Any] { lock.lock(); defer { lock.unlock() }; return _jobLogsBody }
    var jobResultBody: [String: Any] { lock.lock(); defer { lock.unlock() }; return _jobResultBody }

    private var http: TestHTTPServer!
    private let lock = NSLock()
    private var agentPublicKey: Curve25519.Signing.PublicKey?
    private var seenNonces: Set<String> = []
    private var _verifiedCalls: [String] = []
    private var _enrollRequestBody: [String: Any] = [:]
    private var _deployReportBody: [String: Any] = [:]
    private var _jobLogsBody: [String: Any] = [:]
    private var _jobResultBody: [String: Any] = [:]
    private var _sseFrames: [String] = []
    private var _desiredResponseBody = #"{"apps":[]}"#

    init() throws {
        http = try TestHTTPServer { [weak self] req in
            self?.route(req) ?? .http(.json(500, "{}"))
        }
    }

    func stop() { http.stop() }

    var serverPublicKeyPEM: String {
        Self.spkiPEM(rawPublicKey: serverKey.publicKey.rawRepresentation)
    }

    /// Sign already-canonical JSON bytes the way the backend signer does.
    func signCanonical(_ payload: String) -> String {
        try! serverKey.signature(for: Data(payload.utf8)).base64EncodedString()
    }

    private func route(_ req: TestHTTPServer.Request) -> TestHTTPServer.Reply {
        guard req.path.hasPrefix("/v1/") else { return .http(.json(404, "{}")) }
        let path = String(req.path.dropFirst("/v1".count))

        if req.method == "POST", path == "/agent/enroll" { return enroll(req) }

        guard verifySignedRequest(req, path: path) else {
            return .http(.json(401, #"{"error":"signature verification failed"}"#))
        }
        lock.lock()
        _verifiedCalls.append("\(req.method) \(path)")
        lock.unlock()

        let json = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:]
        switch (req.method, path) {
        case ("POST", "/agent/heartbeat"):
            return .http(.json(200, "{}"))
        case ("PATCH", "/agent/identity"):
            return .http(.json(200, "{}"))
        case ("POST", "/agent/workflows/report"):
            let count = (json["workflows"] as? [Any])?.count ?? 0
            return .http(.json(200, #"{"count":\#(count)}"#))
        case ("POST", let p) where p.hasPrefix("/agent/jobs/") && p.hasSuffix("/logs"):
            lock.lock(); _jobLogsBody = json; lock.unlock()
            let accepted = (json["items"] as? [Any])?.count ?? 0
            return .http(.json(200, #"{"accepted":\#(accepted)}"#))
        case ("POST", let p) where p.hasPrefix("/agent/jobs/") && p.hasSuffix("/result"):
            lock.lock(); _jobResultBody = json; lock.unlock()
            return .http(.json(200, "{}"))
        case ("GET", "/agent/deploy/desired"):
            return .http(.json(200, desiredResponseBody))
        case ("POST", "/agent/deploy/report"):
            lock.lock(); _deployReportBody = json; lock.unlock()
            return .http(.json(200, "{}"))
        case ("GET", "/agent/stream"):
            return .sse(sseFrames)
        default:
            return .http(.json(404, "{}"))
        }
    }

    private func enroll(_ req: TestHTTPServer.Request) -> TestHTTPServer.Reply {
        guard req.headers["authorization"] == "Bearer \(Self.installCode)" else {
            return .http(.json(401, #"{"error":"invalid install code"}"#))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any],
              let pem = json["publicKey"] as? String,
              let raw = Self.rawKey(fromSPKIPEM: pem),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            return .http(.json(400, #"{"error":"invalid public key"}"#))
        }
        lock.lock()
        agentPublicKey = key
        _enrollRequestBody = json
        lock.unlock()
        let body = try! JSONSerialization.data(withJSONObject: [
            "agentId": Self.agentId,
            "organizationId": Self.organizationId,
            "serverPublicKey": serverPublicKeyPEM,
        ])
        return .http(.json(200, body))
    }

    private func verifySignedRequest(_ req: TestHTTPServer.Request, path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let key = agentPublicKey,
              req.headers["x-agent-id"] == Self.agentId,
              let ts = req.headers["x-timestamp"],
              let tsValue = Int(ts),
              abs(Int(Date().timeIntervalSince1970) - tsValue) <= 300,
              let nonce = req.headers["x-nonce"],
              seenNonces.insert(nonce).inserted,
              let signature = req.headers["x-signature"].flatMap({ Data(base64Encoded: $0) }) else {
            return false
        }
        let bodyHex = SHA256.hash(data: req.body).map { String(format: "%02x", $0) }.joined()
        let message = "\(ts)\n\(nonce)\n\(req.method)\n\(path)\n\(bodyHex)"
        return key.isValidSignature(signature, for: Data(message.utf8))
    }

    private static let ed25519SPKIPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])

    static func spkiPEM(rawPublicKey: Data) -> String {
        var der = ed25519SPKIPrefix
        der.append(rawPublicKey)
        return "-----BEGIN PUBLIC KEY-----\n\(der.base64EncodedString())\n-----END PUBLIC KEY-----\n"
    }

    static func rawKey(fromSPKIPEM pem: String) -> Data? {
        let base64 = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard let der = Data(base64Encoded: base64),
              der.count == 44,
              der.prefix(12) == ed25519SPKIPrefix else {
            return nil
        }
        return der.suffix(32)
    }
}
