import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Entry point for Embedded mode — your app acts as a Deplite agent.
public final class DepliteAgent: @unchecked Sendable {
    public let identity: AgentIdentity
    public let workflows: AgentWorkflows
    public let jobs: AgentJobs
    public let files: AgentFiles

    private let http: HTTPClient
    private let key: Ed25519Key
    private let session: URLSession

    public init(
        identity: AgentIdentity,
        privateKey: Data,
        session: URLSession = .shared
    ) throws {
        self.identity = identity
        self.key = try Ed25519Key.fromRawSeed(privateKey)
        self.session = session
        self.http = HTTPClient(baseURL: identity.baseURL, session: session)
        self.workflows = AgentWorkflows(http: http, agentId: identity.agentId, key: key)
        self.jobs = AgentJobs(http: http, agentId: identity.agentId, key: key)
        self.files = AgentFiles(http: http, agentId: identity.agentId, key: key, session: session)
    }

    public func heartbeat() async throws {
        try await http.signedVoid(
            agentId: identity.agentId,
            key: key,
            method: "POST",
            path: "/agent/heartbeat",
            body: nil as EmptyBody?
        )
    }

    public func updateIdentity(
        hostname: String? = nil,
        os: String? = nil,
        agentVersion: String? = nil
    ) async throws {
        try await http.signedVoid(
            agentId: identity.agentId,
            key: key,
            method: "PATCH",
            path: "/agent/identity",
            body: IdentityPatch(hostname: hostname, os: os, agentVersion: agentVersion)
        )
    }

    public func events() -> AsyncThrowingStream<AgentEvent, Error> {
        let raw = SSEStream.open(
            baseURL: http.baseURL,
            path: "/agent/stream",
            agentId: identity.agentId,
            key: key,
            session: session
        )
        let serverPub = identity.serverPublicKeyPEM
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await ev in raw {
                        continuation.yield(parseAgentEvent(name: ev.name, data: ev.data, serverPublicKeyPEM: serverPub))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    internal struct IdentityPatch: Encodable {
        let hostname: String?
        let os: String?
        let agentVersion: String?
    }
}

internal func parseAgentEvent(name: String, data: String, serverPublicKeyPEM: String) -> AgentEvent {
    switch name {
    case "deploy": return parseDeploy(data: data, serverPublicKeyPEM: serverPublicKeyPEM)
    case "revoke": return .revoke
    case "sync_workflows", "workflows-refresh": return .syncWorkflows
    case "ping": return .ping
    default: return .unknown(name: name, data: data)
    }
}

private func parseDeploy(data: String, serverPublicKeyPEM: String) -> AgentEvent {
    let envelope: CanonicalNode
    do { envelope = try CanonicalJSON.parse(data) }
    catch { return .unknown(name: "deploy", data: data) }

    guard case .object(let entries) = envelope else { return .unknown(name: "deploy", data: data) }
    var payloadNode: CanonicalNode? = nil
    var signatureString: String? = nil
    for (k, v) in entries {
        if k == "payload" { payloadNode = v }
        else if k == "signature", case .string(let s) = v { signatureString = s }
    }
    guard let payload = payloadNode, let signature = signatureString else {
        return .unknown(name: "deploy", data: data)
    }

    let canonical = Data(CanonicalJSON.encode(payload).utf8)
    guard let sigBytes = Data(base64Encoded: signature) else {
        return .unknown(name: "deploy", data: data)
    }
    guard Ed25519Key.verify(pem: serverPublicKeyPEM, message: canonical, signature: sigBytes) else {
        return .unknown(name: "deploy", data: data)
    }

    let translated = CanonicalJSON.translateDeployKeys(payload)
    let json = CanonicalJSON.toJSONData(translated)
    do {
        let decoded = try JSONDecoder().decode(DeployPayload.self, from: json)
        return .deploy(payload: decoded, signature: signature)
    } catch {
        return .unknown(name: "deploy", data: data)
    }
}
