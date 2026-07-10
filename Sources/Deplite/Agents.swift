import Foundation

/// Agent discovery exposed by `Deplite.agents`.
public struct Agents: Sendable {
    private let http: HTTPClient
    private let apiToken: String

    internal init(http: HTTPClient, apiToken: String) {
        self.http = http
        self.apiToken = apiToken
    }

    /// Agents (devices) the token can reach. Wraps `GET /agents`.
    ///
    /// The listing covers the token's grants only, never the whole organization:
    /// an agent grant contributes its agents, a trigger grant contributes the
    /// agent behind each trigger, and a storage-only token gets an empty list.
    /// Reads are rate-limited per token; a 429 body carries `scope: "token_read"`.
    public func list() async throws -> [AgentSummary] {
        try await http.bearer(
            bearer: apiToken,
            method: "GET",
            path: "/agents",
            body: nil as EmptyBody?
        )
    }
}
