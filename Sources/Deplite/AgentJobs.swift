import Foundation

/// Job lifecycle operations for an embedded agent.
public struct AgentJobs: Sendable {
    private let http: HTTPClient
    private let agentId: String
    private let key: Ed25519Key

    internal init(http: HTTPClient, agentId: String, key: Ed25519Key) {
        self.http = http
        self.agentId = agentId
        self.key = key
    }

    @discardableResult
    public func appendLogs(jobId: String, items: [LogItem]) async throws -> Int {
        if items.isEmpty { return 0 }
        let wire = items.map { WireLog(seq: $0.seq, stream: $0.stream.rawValue, content: $0.content, stepName: $0.stepName, level: $0.level?.rawValue) }
        let res: LogsResponse = try await http.signed(
            agentId: agentId,
            key: key,
            method: "POST",
            path: "/agent/jobs/\(jobId)/logs",
            body: LogsRequest(items: wire)
        )
        return res.accepted
    }

    public func reportResult(jobId: String, result: JobResult) async throws {
        let body = ResultRequest(
            status: result.status.rawValue,
            exitCode: result.exitCode,
            errorMessage: result.errorMessage,
            output: result.output,
            reason: result.rejection?.reason,
            limitType: result.rejection?.limitType,
            retryAfterSeconds: result.rejection?.retryAfterSeconds,
            bypassedLimits: (result.rejection?.bypassedLimits).flatMap { $0.isEmpty ? nil : $0 }
        )
        try await http.signedVoid(
            agentId: agentId,
            key: key,
            method: "POST",
            path: "/agent/jobs/\(jobId)/result",
            body: body
        )
    }

    internal struct LogsRequest: Encodable { let items: [WireLog] }
    internal struct WireLog: Encodable {
        let seq: Int
        let stream: String
        let content: String
        let stepName: String?
        let level: String?
    }
    internal struct LogsResponse: Decodable { let accepted: Int }
    internal struct ResultRequest: Encodable {
        let status: String
        let exitCode: Int?
        let errorMessage: String?
        let output: JSONValue?
        let reason: String?
        let limitType: String?
        let retryAfterSeconds: Int?
        let bypassedLimits: [String]?
    }
}
