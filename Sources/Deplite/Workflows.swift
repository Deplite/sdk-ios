import Foundation

/// Workflow discovery exposed by `Deplite.workflows`.
public struct Workflows: Sendable {
    private let http: HTTPClient
    private let apiToken: String

    internal init(http: HTTPClient, apiToken: String) {
        self.http = http
        self.apiToken = apiToken
    }

    /// Workflows the token can run. Wraps `GET /workflows`.
    ///
    /// An agent grant, or a trigger granted over a whole agent, contributes every
    /// active workflow of that agent; a trigger granted over a single workflow
    /// contributes only that one. Removed workflows never appear, and a
    /// storage-only token gets an empty list.
    /// Reads are rate-limited per token; a 429 body carries `scope: "token_read"`.
    public func list() async throws -> [WorkflowSummary] {
        try await http.bearer(
            bearer: apiToken,
            method: "GET",
            path: "/workflows",
            body: nil as EmptyBody?
        )
    }
}
