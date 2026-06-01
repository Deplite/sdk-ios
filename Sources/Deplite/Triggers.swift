import Foundation

/// Trigger operations exposed by `Deplite.triggers`.
public struct Triggers: Sendable {
    private let http: HTTPClient
    private let apiToken: String

    internal init(http: HTTPClient, apiToken: String) {
        self.http = http
        self.apiToken = apiToken
    }

    /// Invoke a trigger. Wraps `POST /triggers/{triggerId}/run`.
    public func run(
        triggerId: String,
        params: JSONValue? = nil,
        workflowName: String? = nil,
        ref: String? = nil,
        debug: Bool = false,
        idempotencyKey: String? = nil
    ) async throws -> TriggerRunResult {
        let body = RunRequest(
            workflowName: workflowName,
            ref: ref,
            debug: debug ? true : nil,
            params: params
        )
        let headers: [String: String]? = idempotencyKey.map { ["Idempotency-Key": $0] }
        return try await http.bearer(
            bearer: apiToken,
            method: "POST",
            path: "/triggers/\(triggerId)/run",
            body: body,
            extraHeaders: headers
        )
    }

    internal struct RunRequest: Encodable {
        let workflowName: String?
        let ref: String?
        let debug: Bool?
        let params: JSONValue?
    }
}
