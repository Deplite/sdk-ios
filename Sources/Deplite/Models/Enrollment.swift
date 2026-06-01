import Foundation

/// Output of `Deplite.enroll`. Caller persists both fields.
public struct Enrollment: Sendable, Equatable {
    public let identity: AgentIdentity
    public let privateKey: Data

    public init(identity: AgentIdentity, privateKey: Data) {
        self.identity = identity
        self.privateKey = privateKey
    }
}
