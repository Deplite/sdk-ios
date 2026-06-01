import Foundation

/// Result of a trigger invocation.
public struct TriggerRunResult: Decodable, Sendable, Equatable {
    public let jobId: String
    public let status: String
    public let idempotent: Bool
    public let timedOut: Bool
    public let exitCode: Int?
    public let errorMessage: String?
    public let output: JSONValue?
    public let statusUrl: URL?

    private enum CodingKeys: String, CodingKey {
        case jobId, status, idempotent, timedOut, exitCode, errorMessage, output, statusUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jobId = try c.decode(String.self, forKey: .jobId)
        self.status = try c.decode(String.self, forKey: .status)
        self.idempotent = (try? c.decode(Bool.self, forKey: .idempotent)) ?? false
        self.timedOut = (try? c.decode(Bool.self, forKey: .timedOut)) ?? false
        self.exitCode = try? c.decode(Int.self, forKey: .exitCode)
        self.errorMessage = try? c.decode(String.self, forKey: .errorMessage)
        self.output = try? c.decode(JSONValue.self, forKey: .output)
        self.statusUrl = try? c.decode(URL.self, forKey: .statusUrl)
    }
}
