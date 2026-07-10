import Foundation

/// The release currently installed on this device for an app.
public struct DesiredCurrent: Sendable, Equatable {
    public let releaseId: String
    public let version: String
    public let sequence: Int64

    public init(releaseId: String, version: String, sequence: Int64) {
        self.releaseId = releaseId
        self.version = version
        self.sequence = sequence
    }
}

extension DesiredCurrent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case releaseId = "release_id"
        case version
        case sequence
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.releaseId = (try? c.decode(String.self, forKey: .releaseId)) ?? ""
        self.version = (try? c.decode(String.self, forKey: .version)) ?? ""
        self.sequence = (try? c.decode(Int64.self, forKey: .sequence)) ?? 0
    }
}
