import Foundation

/// Errors raised by the SDK.
public enum DepliteError: Error, Sendable {
    case api(statusCode: Int, body: String)
    case unauthorized(statusCode: Int, body: String)
    case transport(underlying: Error)
    case decoding(underlying: Error, body: String)
    case invalidPrivateKey
    case signing(reason: String)
    case sseClosed(reason: String)
    case verification(reason: String)
}

extension DepliteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .api(let code, _): return "Deplite API error \(code)"
        case .unauthorized(let code, _): return "Deplite unauthorized \(code)"
        case .transport: return "Deplite transport error"
        case .decoding: return "Deplite response decoding error"
        case .invalidPrivateKey: return "Deplite invalid private key"
        case .signing(let reason): return "Deplite signing error: \(reason)"
        case .sseClosed(let reason): return "Deplite SSE closed: \(reason)"
        case .verification(let reason): return "Deplite verification error: \(reason)"
        }
    }
}
