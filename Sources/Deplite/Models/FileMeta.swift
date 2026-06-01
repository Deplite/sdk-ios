import Foundation

/// Metadata for a stored file.
public struct FileMeta: Decodable, Sendable, Equatable {
    public let id: String
    public let bindingId: String?
    public let jobId: String?
    public let filename: String?
    public let contentType: String?
    public let size: Int64?
    public let status: String?
    public let cleanupRule: String?
    public let expiresAt: String?
    public let createdAt: String?
}
