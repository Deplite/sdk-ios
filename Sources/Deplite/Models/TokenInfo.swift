import Foundation

/// Permission carried by a `.storage` grant.
public enum StoragePermission: String, Codable, Sendable {
    case read, write, delete
}

/// A single grant on an API token.
public enum TokenScope: Decodable, Sendable, Equatable {
    case agent(agentIds: [String])
    case trigger(triggerIds: [String])
    /// A nil `bindingIds` means every binding of the organization.
    case storage(bindingIds: [String]?, permissions: [StoragePermission])
    /// A grant type introduced after this SDK version.
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, agentIds, triggerIds, bindingIds, permissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "agent":
            self = .agent(agentIds: try c.decodeIfPresent([String].self, forKey: .agentIds) ?? [])
        case "trigger":
            self = .trigger(triggerIds: try c.decodeIfPresent([String].self, forKey: .triggerIds) ?? [])
        case "storage":
            self = .storage(
                bindingIds: try c.decodeIfPresent([String].self, forKey: .bindingIds),
                permissions: try c.decodeIfPresent([StoragePermission].self, forKey: .permissions) ?? []
            )
        case let other:
            self = .unknown(type: other)
        }
    }
}

/// Per-token rate limit. A nil field means no limit for that window.
public struct TokenRateLimit: Decodable, Sendable, Equatable {
    public let perMinute: Int?
    public let perHour: Int?
    public let perDay: Int?
}

/// Self-description of the API token in use.
public struct TokenInfo: Decodable, Sendable, Equatable {
    public let organizationId: String
    public let name: String
    public let scopes: [TokenScope]
    public let rateLimit: TokenRateLimit
    /// ISO-8601 timestamp, or nil when the token never expires.
    public let expiresAt: String?
}
