import Foundation

/// A typed event from the agent SSE stream.
public enum AgentEvent: Sendable {
    case deploy(payload: DeployPayload, signature: String)
    case revoke
    case syncWorkflows
    case ping
    case unknown(name: String, data: String)
}
