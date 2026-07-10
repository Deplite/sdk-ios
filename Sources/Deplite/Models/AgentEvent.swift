import Foundation

/// A typed event from the agent SSE stream.
public enum AgentEvent: Sendable {
    case deploy(payload: DeployPayload, signature: String)
    /// `superseded == true` means a newer release invalidated the job; abort its run.
    case cancel(jobId: String, reason: String?, superseded: Bool, actor: String?)
    case revoke
    case syncWorkflows
    case ping
    case unknown(name: String, data: String)
}
