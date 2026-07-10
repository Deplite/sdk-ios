import Foundation

/// Introspection of the API token in use, exposed by `Deplite.token`.
public struct Token: Sendable {
    private let http: HTTPClient
    private let apiToken: String

    internal init(http: HTTPClient, apiToken: String) {
        self.http = http
        self.apiToken = apiToken
    }

    /// Name, grants, rate limits and expiry of the token. Wraps `GET /token`.
    ///
    /// Callable with any token, whatever its grants. Reads are rate-limited per
    /// token; a 429 body carries `scope: "token_read"`.
    public func info() async throws -> TokenInfo {
        try await http.bearer(
            bearer: apiToken,
            method: "GET",
            path: "/token",
            body: nil as EmptyBody?
        )
    }
}
