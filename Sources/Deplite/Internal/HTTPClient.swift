import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal struct EmptyResponse: Decodable {}

internal final class HTTPClient: @unchecked Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession) {
        self.baseURL = HTTPClient.trim(baseURL)
        self.session = session
    }

    static func trim(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.hasSuffix("/"), let u = URL(string: String(s.dropLast())) { return u }
        return url
    }

    static func defaultEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }

    static func defaultDecoder() -> JSONDecoder { JSONDecoder() }

    private static let encoder = defaultEncoder()
    private static let decoder = defaultDecoder()

    // MARK: - Bearer

    func bearer<Req: Encodable, Res: Decodable>(
        bearer: String,
        method: String,
        path: String,
        body: Req?,
        extraHeaders: [String: String]? = nil
    ) async throws -> Res {
        let bytes: Data? = try encode(body)
        return try await execute(method: method, path: path, bodyBytes: bytes) { req in
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            extraHeaders?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        }
    }

    func bearerVoid<Req: Encodable>(
        bearer: String,
        method: String,
        path: String,
        body: Req?,
        extraHeaders: [String: String]? = nil
    ) async throws {
        let _: EmptyResponse = try await self.bearer(
            bearer: bearer as String, method: method, path: path, body: body, extraHeaders: extraHeaders
        )
    }

    // MARK: - Signed

    func signed<Req: Encodable, Res: Decodable>(
        agentId: String,
        key: Ed25519Key,
        method: String,
        path: String,
        body: Req?
    ) async throws -> Res {
        let bytes: Data = try encode(body) ?? Data()
        let ts = String(Int(Date().timeIntervalSince1970))
        let nonce = Nonce.next()
        let canonical = CanonicalMessage.build(timestamp: ts, nonce: nonce, method: method, path: path, body: bytes)
        let signature = try key.sign(canonical).base64EncodedString()

        return try await execute(method: method, path: path, bodyBytes: body == nil ? nil : bytes) { req in
            req.setValue(agentId, forHTTPHeaderField: "x-agent-id")
            req.setValue(ts, forHTTPHeaderField: "x-timestamp")
            req.setValue(nonce, forHTTPHeaderField: "x-nonce")
            req.setValue(signature, forHTTPHeaderField: "x-signature")
        }
    }

    func signedVoid<Req: Encodable>(
        agentId: String,
        key: Ed25519Key,
        method: String,
        path: String,
        body: Req?
    ) async throws {
        let _: EmptyResponse = try await signed(agentId: agentId, key: key, method: method, path: path, body: body)
    }

    // MARK: - Plumbing

    private func encode<T: Encodable>(_ body: T?) throws -> Data? {
        guard let body = body else { return nil }
        if body is EmptyBody { return nil }
        return try Self.encoder.encode(body)
    }

    private func execute<Res: Decodable>(
        method: String,
        path: String,
        bodyBytes: Data?,
        configure: (inout URLRequest) -> Void
    ) async throws -> Res {
        let urlString = baseURL.absoluteString + (path.hasPrefix("/") ? path : "/" + path)
        guard let url = URL(string: urlString) else {
            throw DepliteError.api(statusCode: 0, body: "invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        if let body = bodyBytes {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        configure(&req)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw DepliteError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DepliteError.api(statusCode: 0, body: String(data: data, encoding: .utf8) ?? "")
        }

        let bodyString = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw DepliteError.unauthorized(statusCode: http.statusCode, body: bodyString)
            }
            throw DepliteError.api(statusCode: http.statusCode, body: bodyString)
        }

        if Res.self == EmptyResponse.self || data.isEmpty {
            return EmptyResponse() as! Res
        }
        do {
            return try Self.decoder.decode(Res.self, from: data)
        } catch {
            throw DepliteError.decoding(underlying: error, body: bodyString)
        }
    }
}

/// Sentinel meaning "no body" — used when the generic `Req` is non-optional.
internal struct EmptyBody: Encodable {}
