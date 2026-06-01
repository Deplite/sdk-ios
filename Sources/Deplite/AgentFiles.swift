import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Agent-scope file operations (signed, job-bound).
public struct AgentFiles: Sendable {
    private let http: HTTPClient
    private let agentId: String
    private let key: Ed25519Key
    private let session: URLSession

    internal init(http: HTTPClient, agentId: String, key: Ed25519Key, session: URLSession) {
        self.http = http
        self.agentId = agentId
        self.key = key
        self.session = session
    }

    public func upload(
        jobId: String,
        fileURL: URL,
        cleanupRule: CleanupRule = .onJobEnd,
        filename: String? = nil,
        contentType: String? = nil
    ) async throws -> FileMeta {
        let presign = try await presignUpload(
            jobId: jobId,
            cleanupRule: cleanupRule,
            filename: filename ?? fileURL.lastPathComponent,
            contentType: contentType
        )
        try await putBytes(presign.uploadUrl, fileURL: fileURL, contentType: contentType, extra: presign.uploadHeaders)
        return try await complete(fileId: presign.fileId)
    }

    public func presignUpload(
        jobId: String,
        cleanupRule: CleanupRule = .onJobEnd,
        filename: String? = nil,
        contentType: String? = nil
    ) async throws -> PresignedUpload {
        let req = PresignRequest(
            filename: filename,
            contentType: contentType,
            cleanupRule: cleanupRule.wireValue,
            ttlSeconds: cleanupRule.ttlSeconds
        )
        return try await http.signed(
            agentId: agentId,
            key: key,
            method: "POST",
            path: "/agent/jobs/\(jobId)/files/presign-upload",
            body: req
        )
    }

    public func complete(fileId: String) async throws -> FileMeta {
        try await http.signed(
            agentId: agentId,
            key: key,
            method: "POST",
            path: "/agent/files/\(fileId)/complete",
            body: nil as EmptyBody?
        )
    }

    public func downloadURL(fileId: String) async throws -> URL {
        let res: DownloadResponse = try await http.signed(
            agentId: agentId,
            key: key,
            method: "GET",
            path: "/agent/files/\(fileId)/download-url",
            body: nil as EmptyBody?
        )
        return res.downloadUrl
    }

    @discardableResult
    public func download(fileId: String, to destination: URL) async throws -> URL {
        let url = try await downloadURL(fileId: fileId)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw DepliteError.transport(underlying: error) }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DepliteError.api(statusCode: http.statusCode, body: "")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination)
        return destination
    }

    public func get(fileId: String) async throws -> FileMeta {
        try await http.signed(
            agentId: agentId,
            key: key,
            method: "GET",
            path: "/agent/files/\(fileId)",
            body: nil as EmptyBody?
        )
    }

    public func delete(fileId: String) async throws {
        try await http.signedVoid(
            agentId: agentId,
            key: key,
            method: "DELETE",
            path: "/agent/files/\(fileId)",
            body: nil as EmptyBody?
        )
    }

    private func putBytes(_ url: URL, fileURL: URL, contentType: String?, extra: [String: String]?) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        if let ct = contentType { req.setValue(ct, forHTTPHeaderField: "Content-Type") }
        extra?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (_, response): (Data, URLResponse)
        do { (_, response) = try await session.upload(for: req, fromFile: fileURL) }
        catch { throw DepliteError.transport(underlying: error) }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DepliteError.api(statusCode: http.statusCode, body: "")
        }
    }

    internal struct PresignRequest: Encodable {
        let filename: String?
        let contentType: String?
        let cleanupRule: String
        let ttlSeconds: Int64?
    }
    internal struct DownloadResponse: Decodable {
        let downloadUrl: URL
        let expiresInSeconds: Int?
    }
}
