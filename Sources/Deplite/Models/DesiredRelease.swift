import Foundation

/// The release this device should converge to.
public struct DesiredRelease: Sendable, Equatable {
    public let releaseId: String
    public let version: String
    public let sequence: Int64
    public let channel: String
    public let workflowName: String
    public let checksumSha256: String
    public let size: Int64
    public let downloadUrl: String
    public let downloadExpiresIn: Int64

    public init(
        releaseId: String,
        version: String,
        sequence: Int64,
        channel: String,
        workflowName: String,
        checksumSha256: String,
        size: Int64,
        downloadUrl: String,
        downloadExpiresIn: Int64
    ) {
        self.releaseId = releaseId
        self.version = version
        self.sequence = sequence
        self.channel = channel
        self.workflowName = workflowName
        self.checksumSha256 = checksumSha256
        self.size = size
        self.downloadUrl = downloadUrl
        self.downloadExpiresIn = downloadExpiresIn
    }
}

extension DesiredRelease: Decodable {
    private enum CodingKeys: String, CodingKey {
        case releaseId = "release_id"
        case version
        case sequence
        case channel
        case workflowName = "workflow_name"
        case checksumSha256 = "checksum_sha256"
        case size
        case downloadUrl = "download_url"
        case downloadExpiresIn = "download_expires_in"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.releaseId = (try? c.decode(String.self, forKey: .releaseId)) ?? ""
        self.version = (try? c.decode(String.self, forKey: .version)) ?? ""
        self.sequence = (try? c.decode(Int64.self, forKey: .sequence)) ?? 0
        self.channel = (try? c.decode(String.self, forKey: .channel)) ?? ""
        self.workflowName = (try? c.decode(String.self, forKey: .workflowName)) ?? ""
        self.checksumSha256 = (try? c.decode(String.self, forKey: .checksumSha256)) ?? ""
        self.size = (try? c.decode(Int64.self, forKey: .size)) ?? 0
        self.downloadUrl = (try? c.decode(String.self, forKey: .downloadUrl)) ?? ""
        self.downloadExpiresIn = (try? c.decode(Int64.self, forKey: .downloadExpiresIn)) ?? 0
    }
}
