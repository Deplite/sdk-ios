import Foundation

/// App deploy (OTA) operations exposed by `DepliteAgent.deploy`.
public struct AgentDeploy: Sendable {
    private let http: HTTPClient
    private let agentId: String
    private let key: Ed25519Key
    private let serverPublicKeyPEM: String

    internal init(http: HTTPClient, agentId: String, key: Ed25519Key, serverPublicKeyPEM: String) {
        self.http = http
        self.agentId = agentId
        self.key = key
        self.serverPublicKeyPEM = serverPublicKeyPEM
    }

    /// Fetch this device's desired-state manifests. Each manifest's ed25519
    /// signature is verified against the server key over its raw payload; an
    /// unverifiable manifest aborts the call so callers never see one.
    public func desired() async throws -> [DesiredApp] {
        let data = try await http.signedData(
            agentId: agentId,
            key: key,
            method: "GET",
            path: "/agent/deploy/desired"
        )
        let root: CanonicalNode
        do {
            root = try CanonicalJSON.parse(String(decoding: data, as: UTF8.self))
        } catch {
            throw DepliteError.decoding(underlying: error, body: String(decoding: data, as: UTF8.self))
        }
        guard case .object(let rootEntries) = root,
              let appsNode = value(rootEntries, "apps"),
              case .array(let apps) = appsNode else {
            return []
        }

        var out: [DesiredApp] = []
        for env in apps {
            guard case .object(let envEntries) = env,
                  let payloadNode = value(envEntries, "payload"),
                  case .object = payloadNode else {
                throw DepliteError.verification(reason: "deploy manifest missing payload")
            }
            let signature = value(envEntries, "signature").flatMap { node -> String? in
                if case .string(let s) = node { return s }
                return nil
            }
            guard verifyManifest(payload: payloadNode, signature: signature) else {
                throw DepliteError.verification(
                    reason: "deploy manifest signature verification failed for \(slug(of: payloadNode))"
                )
            }
            let json = CanonicalJSON.toJSONData(payloadNode)
            out.append(try JSONDecoder().decode(DesiredApp.self, from: json))
        }
        return out
    }

    /// Report this device's current app state to the backend.
    public func report(_ input: DeviceReportInput) async throws {
        let body = ReportRequest(
            applicationId: input.applicationId,
            currentVersion: input.currentVersion,
            currentReleaseId: input.currentReleaseId,
            currentSequence: input.currentSequence,
            state: input.state?.rawValue,
            error: input.error
        )
        try await http.signedVoid(
            agentId: agentId,
            key: key,
            method: "POST",
            path: "/agent/deploy/report",
            body: body
        )
    }

    private func verifyManifest(payload: CanonicalNode, signature: String?) -> Bool {
        guard let signature = signature, !signature.isEmpty,
              let sigBytes = Data(base64Encoded: signature) else {
            return false
        }
        let canonical = Data(CanonicalJSON.encode(payload).utf8)
        return Ed25519Key.verify(pem: serverPublicKeyPEM, message: canonical, signature: sigBytes)
    }

    private func value(_ entries: [(String, CanonicalNode)], _ key: String) -> CanonicalNode? {
        for (k, v) in entries where k == key { return v }
        return nil
    }

    private func slug(of payload: CanonicalNode) -> String {
        guard case .object(let entries) = payload,
              let node = value(entries, "slug"),
              case .string(let s) = node else {
            return "unknown app"
        }
        return s
    }

    internal struct ReportRequest: Encodable {
        let applicationId: String
        let currentVersion: String?
        let currentReleaseId: String?
        let currentSequence: Int64?
        let state: String?
        let error: String?
    }
}
