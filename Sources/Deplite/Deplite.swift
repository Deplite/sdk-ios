import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Entry point for External mode — call Deplite from your app, CI, or server.
public final class Deplite: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://api.deplite.io/v1")!

    public let apiToken: String
    public let baseURL: URL
    public let triggers: Triggers
    public let files: Files
    /// Introspection of `apiToken` itself.
    public let token: Token
    /// Agents this token can reach.
    public let agents: Agents
    /// Workflows this token can run.
    public let workflows: Workflows

    public init(
        apiToken: String,
        baseURL: URL = Deplite.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.apiToken = apiToken
        self.baseURL = baseURL
        let http = HTTPClient(baseURL: baseURL, session: session)
        self.triggers = Triggers(http: http, apiToken: apiToken)
        self.files = Files(http: http, apiToken: apiToken, session: session)
        self.token = Token(http: http, apiToken: apiToken)
        self.agents = Agents(http: http, apiToken: apiToken)
        self.workflows = Workflows(http: http, apiToken: apiToken)
    }

    /// Register the current device or service as a Deplite agent.
    public static func register(
        installCode: String,
        name: String,
        hostname: String? = nil,
        os: String? = nil,
        agentVersion: String? = nil,
        baseURL: URL = Deplite.defaultBaseURL,
        session: URLSession = .shared
    ) async throws -> Registration {
        let keys = Ed25519Key.generate()
        let http = HTTPClient(baseURL: baseURL, session: session)
        let req = EnrollRequest(
            name: name,
            hostname: hostname,
            os: os,
            agentVersion: agentVersion,
            publicKey: keys.publicKeyPEM()
        )
        let res: EnrollResponse = try await http.bearer(
            bearer: installCode,
            method: "POST",
            path: "/agent/enroll",
            body: req
        )
        let identity = AgentIdentity(
            agentId: res.agentId,
            organizationId: res.organizationId,
            baseURL: HTTPClient.trim(baseURL),
            serverPublicKeyPEM: res.serverPublicKey
        )
        return Registration(identity: identity, privateKey: keys.rawSeed)
    }

    internal struct EnrollRequest: Encodable {
        let name: String
        let hostname: String?
        let os: String?
        let agentVersion: String?
        let publicKey: String
    }

    internal struct EnrollResponse: Decodable {
        let agentId: String
        let organizationId: String
        let serverPublicKey: String
    }
}
