import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Response of `Files.presignUpload`.
public struct PresignedUpload: Decodable, Sendable, Equatable {
    public let fileId: String
    public let uploadUrl: URL
    public let uploadHeaders: [String: String]?
    public let expiresInSeconds: Int?
}

/// File operations exposed by `Deplite.files`.
public struct Files: Sendable {
    private let http: HTTPClient
    private let apiToken: String
    private let session: URLSession

    internal init(http: HTTPClient, apiToken: String, session: URLSession) {
        self.http = http
        self.apiToken = apiToken
        self.session = session
    }

    public func upload(
        fileURL: URL,
        cleanupRule: CleanupRule = .ttl(seconds: 86_400),
        filename: String? = nil,
        contentType: String? = nil,
        bindingId: String? = nil
    ) async throws -> FileMeta {
        let presign = try await presignUpload(
            cleanupRule: cleanupRule,
            filename: filename ?? fileURL.lastPathComponent,
            contentType: contentType,
            bindingId: bindingId
        )
        try await putBytes(presign.uploadUrl, fileURL: fileURL, contentType: contentType, extra: presign.uploadHeaders)
        return try await completeUpload(fileId: presign.fileId)
    }

    public func presignUpload(
        cleanupRule: CleanupRule,
        filename: String? = nil,
        contentType: String? = nil,
        bindingId: String? = nil
    ) async throws -> PresignedUpload {
        if case .onJobEnd = cleanupRule {
            throw DepliteError.signing(reason: "onJobEnd cleanup is only available on embedded agent uploads")
        }
        let req = PresignRequest(
            bindingId: bindingId,
            filename: filename,
            contentType: contentType,
            cleanupRule: cleanupRule.wireValue,
            ttlSeconds: cleanupRule.ttlSeconds
        )
        return try await http.bearer(
            bearer: apiToken,
            method: "POST",
            path: "/storage/files/presign-upload",
            body: req
        )
    }

    public func completeUpload(fileId: String) async throws -> FileMeta {
        try await http.bearer(
            bearer: apiToken,
            method: "POST",
            path: "/storage/files/\(fileId)/complete",
            body: nil as EmptyBody?
        )
    }

    public func downloadURL(fileId: String) async throws -> URL {
        let res: DownloadResponse = try await http.bearer(
            bearer: apiToken,
            method: "GET",
            path: "/storage/files/\(fileId)/download-url",
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
        try await http.bearer(
            bearer: apiToken,
            method: "GET",
            path: "/storage/files/\(fileId)",
            body: nil as EmptyBody?
        )
    }

    public func list(bindingId: String? = nil, status: String? = nil) async throws -> [FileMeta] {
        var qs: [String] = []
        if let b = bindingId { qs.append("bindingId=\(b)") }
        if let s = status { qs.append("status=\(s)") }
        let suffix = qs.isEmpty ? "" : "?" + qs.joined(separator: "&")
        return try await http.bearer(
            bearer: apiToken,
            method: "GET",
            path: "/storage/files\(suffix)",
            body: nil as EmptyBody?
        )
    }

    public func delete(fileId: String) async throws {
        try await http.bearerVoid(
            bearer: apiToken,
            method: "DELETE",
            path: "/storage/files/\(fileId)",
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
        let bindingId: String?
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
