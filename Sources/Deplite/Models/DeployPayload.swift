import Foundation

/// Payload of an `AgentEvent.deploy` event.
public struct DeployPayload: Sendable, Equatable {
    public let jobId: String
    public let workflowName: String
    public let debug: Bool
    public let ref: String?
    public let params: JSONValue?
    public let issuedAt: Int64
    public let nonce: String
    public let force: Bool
    public let forceReason: String?

    public init(
        jobId: String,
        workflowName: String,
        debug: Bool = false,
        ref: String? = nil,
        params: JSONValue? = nil,
        issuedAt: Int64 = 0,
        nonce: String = "",
        force: Bool = false,
        forceReason: String? = nil
    ) {
        self.jobId = jobId
        self.workflowName = workflowName
        self.debug = debug
        self.ref = ref
        self.params = params
        self.issuedAt = issuedAt
        self.nonce = nonce
        self.force = force
        self.forceReason = forceReason
    }
}

extension DeployPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case jobId, workflowName, debug, ref, params, issuedAt, nonce, force, forceReason
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jobId = try c.decode(String.self, forKey: .jobId)
        self.workflowName = try c.decode(String.self, forKey: .workflowName)
        self.debug = (try? c.decode(Bool.self, forKey: .debug)) ?? false
        self.ref = try? c.decode(String.self, forKey: .ref)
        self.params = try? c.decode(JSONValue.self, forKey: .params)
        self.issuedAt = (try? c.decode(Int64.self, forKey: .issuedAt)) ?? 0
        self.nonce = (try? c.decode(String.self, forKey: .nonce)) ?? ""
        self.force = (try? c.decode(Bool.self, forKey: .force)) ?? false
        self.forceReason = try? c.decode(String.self, forKey: .forceReason)
    }
}
