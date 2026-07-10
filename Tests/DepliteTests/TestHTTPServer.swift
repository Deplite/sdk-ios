import Foundation
import Network

/// Minimal loopback HTTP/1.1 server so tests exercise real URLSession networking.
final class TestHTTPServer: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data

        static func json(_ status: Int, _ body: Data) -> Response {
            Response(status: status, headers: ["Content-Type": "application/json"], body: body)
        }

        static func json(_ status: Int, _ text: String) -> Response {
            json(status, Data(text.utf8))
        }
    }

    enum Reply {
        case http(Response)
        case sse([String])
    }

    struct StartError: Error {}

    private(set) var port: UInt16 = 0
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/v1")! }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "deplite.test.http")
    private let handler: (Request) -> Reply
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init(handler: @escaping (Request) -> Reply) throws {
        self.handler = handler
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        self.listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard let port = listener.port?.rawValue, port != 0 else {
            listener.cancel()
            throw StartError()
        }
        self.port = port
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let open = connections
        connections = []
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    private func accept(_ conn: NWConnection) {
        lock.lock()
        connections.append(conn)
        lock.unlock()
        conn.start(queue: queue)
        receive(on: conn, buffered: Data())
    }

    private func receive(on conn: NWConnection, buffered: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffered
            if let data { buf.append(data) }
            if let request = Self.parse(buf) {
                self.respond(request, on: conn)
            } else if error == nil, !isComplete {
                self.receive(on: conn, buffered: buf)
            } else {
                conn.cancel()
            }
        }
    }

    private static func parse(_ buf: Data) -> Request? {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buf[buf.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buf.endIndex - bodyStart >= contentLength else { return nil }
        let body = Data(buf[bodyStart..<bodyStart + contentLength])
        let path = requestLine[1].components(separatedBy: "?")[0]
        return Request(method: requestLine[0].uppercased(), path: path, headers: headers, body: body)
    }

    private func respond(_ request: Request, on conn: NWConnection) {
        switch handler(request) {
        case .http(let res):
            var head = "HTTP/1.1 \(res.status) \(res.status == 200 ? "OK" : "Error")\r\n"
            for (k, v) in res.headers { head += "\(k): \(v)\r\n" }
            head += "Content-Length: \(res.body.count)\r\nConnection: close\r\n\r\n"
            var out = Data(head.utf8)
            out.append(res.body)
            conn.send(content: out, contentContext: .finalMessage, isComplete: true,
                      completion: .contentProcessed { _ in })
        case .sse(let frames):
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
                self?.sendFrames(frames, on: conn)
            })
        }
    }

    private func sendFrames(_ frames: [String], on conn: NWConnection) {
        guard let frame = frames.first else {
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                      completion: .contentProcessed { _ in })
            return
        }
        let rest = Array(frames.dropFirst())
        // separate segments per frame, closer to a real event stream
        queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            conn.send(content: Data(frame.utf8), completion: .contentProcessed { _ in
                self?.sendFrames(rest, on: conn)
            })
        }
    }
}
