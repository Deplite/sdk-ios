import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MockURLProtocol: URLProtocol {
    struct CapturedRequest {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
        let chunkDelay: TimeInterval

        init(status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], body: Data = Data(), chunkDelay: TimeInterval = 0) {
            self.status = status
            self.headers = headers
            self.body = body
            self.chunkDelay = chunkDelay
        }

        static func json(_ status: Int = 200, _ object: Any) -> Response {
            let body = try! JSONSerialization.data(withJSONObject: object)
            return Response(status: status, body: body)
        }

        static func sse(_ raw: String) -> Response {
            Response(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(raw.utf8))
        }
    }

    nonisolated(unsafe) static var queue: [Response] = []
    nonisolated(unsafe) static var captured: [CapturedRequest] = []
    static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queue = []; captured = []
    }

    static func enqueue(_ response: Response) {
        lock.lock(); defer { lock.unlock() }
        queue.append(response)
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Capture
        var headers: [String: String] = [:]
        for (k, v) in (request.allHTTPHeaderFields ?? [:]) { headers[k] = v }
        let body: Data
        if let bs = request.httpBodyStream {
            body = MockURLProtocol.readAll(stream: bs)
        } else {
            body = request.httpBody ?? Data()
        }
        let captured = CapturedRequest(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: headers,
            body: body
        )
        MockURLProtocol.lock.lock()
        MockURLProtocol.captured.append(captured)
        let response = MockURLProtocol.queue.isEmpty ? Response() : MockURLProtocol.queue.removeFirst()
        MockURLProtocol.lock.unlock()

        let urlResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: bufSize)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
