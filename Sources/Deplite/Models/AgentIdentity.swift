import Foundation

/// Non-secret identity returned by registration. Safe to persist anywhere.
public struct AgentIdentity: Codable, Sendable, Equatable {
    public let agentId: String
    public let organizationId: String
    public let baseURL: URL
    public let serverPublicKeyPEM: String

    public init(agentId: String, organizationId: String, baseURL: URL, serverPublicKeyPEM: String) {
        self.agentId = agentId
        self.organizationId = organizationId
        self.baseURL = baseURL
        self.serverPublicKeyPEM = serverPublicKeyPEM
    }
}
