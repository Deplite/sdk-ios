import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal struct RawSSEEvent: Sendable {
    let name: String
    let data: String
}

internal enum SSEStream {
    static func open(
        baseURL: URL,
        path: String,
        agentId: String,
        key: Ed25519Key,
        session: URLSession
    ) -> AsyncThrowingStream<RawSSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let ts = String(Int(Date().timeIntervalSince1970))
                    let nonce = Nonce.next()
                    let canonical = CanonicalMessage.build(timestamp: ts, nonce: nonce, method: "GET", path: path, body: Data())
                    let signature = try key.sign(canonical).base64EncodedString()

                    let urlString = baseURL.absoluteString + (path.hasPrefix("/") ? path : "/" + path)
                    guard let url = URL(string: urlString) else {
                        throw DepliteError.api(statusCode: 0, body: "invalid SSE URL")
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue(agentId, forHTTPHeaderField: "x-agent-id")
                    req.setValue(ts, forHTTPHeaderField: "x-timestamp")
                    req.setValue(nonce, forHTTPHeaderField: "x-nonce")
                    req.setValue(signature, forHTTPHeaderField: "x-signature")

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: req)
                    } catch {
                        throw DepliteError.transport(underlying: error)
                    }

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw DepliteError.unauthorized(statusCode: http.statusCode, body: "")
                        }
                        throw DepliteError.api(statusCode: http.statusCode, body: "")
                    }

                    var lineBuf: [UInt8] = []
                    var eventName: String? = nil
                    var dataLines: [String] = []

                    func dispatch() {
                        if eventName != nil || !dataLines.isEmpty {
                            let name = eventName ?? "message"
                            let data = dataLines.joined(separator: "\n")
                            continuation.yield(RawSSEEvent(name: name, data: data))
                        }
                        eventName = nil
                        dataLines = []
                    }

                    func handle(line: String) {
                        if line.isEmpty {
                            dispatch()
                            return
                        }
                        if line.hasPrefix(":") { return }
                        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                        let field = String(parts[0])
                        var value = parts.count > 1 ? String(parts[1]) : ""
                        if value.hasPrefix(" ") { value.removeFirst() }
                        switch field {
                        case "event": eventName = value
                        case "data": dataLines.append(value)
                        case "id", "retry": break
                        default: break
                        }
                    }

                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A { // \n
                            // strip trailing CR if present
                            if lineBuf.last == 0x0D { lineBuf.removeLast() }
                            let line = String(bytes: lineBuf, encoding: .utf8) ?? ""
                            lineBuf.removeAll(keepingCapacity: true)
                            handle(line: line)
                        } else {
                            lineBuf.append(byte)
                        }
                    }
                    // flush trailing line if any
                    if !lineBuf.isEmpty {
                        let line = String(bytes: lineBuf, encoding: .utf8) ?? ""
                        handle(line: line)
                    }
                    dispatch()
                    continuation.finish(throwing: DepliteError.sseClosed(reason: "stream ended"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
