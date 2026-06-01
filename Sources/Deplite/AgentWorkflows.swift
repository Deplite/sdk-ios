import Foundation

/// Workflow inventory reporting for an embedded agent.
public struct AgentWorkflows: Sendable {
    private let http: HTTPClient
    private let agentId: String
    private let key: Ed25519Key

    internal init(http: HTTPClient, agentId: String, key: Ed25519Key) {
        self.http = http
        self.agentId = agentId
        self.key = key
    }

    @discardableResult
    public func report(_ workflows: [WorkflowReport]) async throws -> Int {
        let res: ReportResponse = try await http.signed(
            agentId: agentId,
            key: key,
            method: "POST",
            path: "/agent/workflows/report",
            body: ReportRequest(workflows: workflows)
        )
        return res.count
    }

    internal struct ReportRequest: Encodable { let workflows: [WorkflowReport] }
    internal struct ReportResponse: Decodable { let count: Int }
}
