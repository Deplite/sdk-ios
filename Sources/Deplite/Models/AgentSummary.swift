import Foundation

/// Lifecycle state of an agent.
public enum AgentStatus: String, Decodable, Sendable {
    case pending, connected, disconnected, revoked
}

/// An agent (device) the current API token can reach.
public struct AgentSummary: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let hostname: String?
    public let os: String?
    public let agentVersion: String?
    public let status: AgentStatus
    /// ISO-8601 timestamp of the last contact, or nil if never seen.
    public let lastSeenAt: String?
    /// ISO-8601 timestamp of the install.
    public let registeredAt: String

    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, os, agentVersion, status, lastSeenAt
        case registeredAt = "enrolledAt"
    }
}
