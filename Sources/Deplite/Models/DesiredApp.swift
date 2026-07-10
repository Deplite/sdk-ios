import Foundation

/// One app's signed desired-state manifest. Order releases by `sequence`
/// (integer); `version` is display-only.
public struct DesiredApp: Sendable, Equatable {
    public let applicationId: String
    public let slug: String
    public let channel: String
    public let updateWorkflow: String
    public let current: DesiredCurrent?
    public let desired: DesiredRelease?
    public let minVersion: String?
    public let minSequence: Int64
    public let forced: Bool
    public let issuedAt: Int64
    public let nonce: String

    public init(
        applicationId: String,
        slug: String,
        channel: String,
        updateWorkflow: String,
        current: DesiredCurrent?,
        desired: DesiredRelease?,
        minVersion: String?,
        minSequence: Int64,
        forced: Bool,
        issuedAt: Int64,
        nonce: String
    ) {
        self.applicationId = applicationId
        self.slug = slug
        self.channel = channel
        self.updateWorkflow = updateWorkflow
        self.current = current
        self.desired = desired
        self.minVersion = minVersion
        self.minSequence = minSequence
        self.forced = forced
        self.issuedAt = issuedAt
        self.nonce = nonce
    }
}

extension DesiredApp: Decodable {
    private enum CodingKeys: String, CodingKey {
        case applicationId = "application_id"
        case slug
        case channel
        case updateWorkflow = "update_workflow"
        case current
        case desired
        case minVersion = "min_version"
        case minSequence = "min_sequence"
        case forced
        case issuedAt = "issued_at"
        case nonce
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.applicationId = (try? c.decode(String.self, forKey: .applicationId)) ?? ""
        self.slug = (try? c.decode(String.self, forKey: .slug)) ?? ""
        self.channel = (try? c.decode(String.self, forKey: .channel)) ?? ""
        self.updateWorkflow = (try? c.decode(String.self, forKey: .updateWorkflow)) ?? ""
        self.current = try? c.decode(DesiredCurrent.self, forKey: .current)
        self.desired = try? c.decode(DesiredRelease.self, forKey: .desired)
        self.minVersion = try? c.decode(String.self, forKey: .minVersion)
        self.minSequence = (try? c.decode(Int64.self, forKey: .minSequence)) ?? 0
        self.forced = (try? c.decode(Bool.self, forKey: .forced)) ?? false
        self.issuedAt = (try? c.decode(Int64.self, forKey: .issuedAt)) ?? 0
        self.nonce = (try? c.decode(String.self, forKey: .nonce)) ?? ""
    }
}
