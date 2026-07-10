import Foundation

/// A workflow the current API token can run.
public struct WorkflowSummary: Decodable, Sendable, Equatable {
    public let id: String
    public let agentId: String
    public let name: String
    public let description: String?
    public let version: String?
    /// Input schema of the workflow, or nil when it declares no params.
    public let paramsSchema: [WorkflowParam]?
}
